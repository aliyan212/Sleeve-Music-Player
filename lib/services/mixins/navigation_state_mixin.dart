import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../data/models/album_stat.dart';
import '../../data/models/genre_stat.dart';
import '../../main.dart';
import '../../pages/album_page.dart';
import '../../pages/artist_page.dart';
import '../../pages/genre_page.dart';
import '../../pages/now_playing_page.dart';
import '../../platform_exit.dart';
import '../../utils/song_sort_utils.dart';
import '../../widgets/search/app_search_view.dart';
import '../playback_controller.dart';

/// Mixin managing app-wide navigation state, tabs, inline detail pages,
/// and full-screen / dialog transitions (Now Playing, Albums, Artists, Search).
mixin NavigationStateMixin on ChangeNotifier {
  // Dependencies satisfied by AppStateController or companion mixins:
  List<SongModel> get songs;
  void updateSongMetadataInPlace(SongModel updatedSong);
  void updateSongsMetadataInPlace(List<SongModel> updatedSongs);

  final SearchController searchController = SearchController();

  late int selectedTabIndex;
  bool nowPlayingRouteActive = false;
  DateTime? _lastNowPlayingClosedAt;

  bool hideBottomBars = false;
  Widget? inlineDetailContent;

  bool isSelectionMode = false;
  final Set<int> selectedSongIds = <int>{};


  void selectTab(int index) {
    if (selectedTabIndex != index) {
      HapticFeedback.selectionClick();
    }
    if (isSelectionMode) exitSelectionMode();
    if (inlineDetailContent != null) {
      inlineDetailContent = null;
    }
    selectedTabIndex = index;
    notifyListeners();
  }

  void showInlineDetail(Widget detailContent) {
    inlineDetailContent = detailContent;
    hideBottomBars = false;
    notifyListeners();
  }

  void closeInlineDetail() {
    if (inlineDetailContent == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    inlineDetailContent = null;
    notifyListeners();
  }

  void openSearch({SearchFilter initialFilter = SearchFilter.all}) {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    if (inlineDetailContent != null) {
      inlineDetailContent = null;
    }
    final ctx = navigatorKey.currentContext;
    if (ctx != null) {
      AppSearchView.show(ctx, initialFilter: initialFilter);
    }
  }

  void enterSelectionMode({int? initialSongId}) {
    if (searchController.isAttached && searchController.isOpen) {
      searchController.closeView(searchController.text);
      FocusManager.instance.primaryFocus?.unfocus();
    }
    isSelectionMode = true;
    selectedSongIds.clear();
    if (initialSongId != null) selectedSongIds.add(initialSongId);
    notifyListeners();
  }

  void exitSelectionMode() {
    if (!isSelectionMode) return;
    isSelectionMode = false;
    selectedSongIds.clear();
    notifyListeners();
  }

  void toggleSelectedSongId(int songId) {
    if (selectedSongIds.contains(songId)) {
      selectedSongIds.remove(songId);
      if (selectedSongIds.isEmpty) isSelectionMode = false;
    } else {
      selectedSongIds.add(songId);
      isSelectionMode = true;
    }
    notifyListeners();
  }

  void selectAllSongs(Iterable<int> songIds) {
    selectedSongIds.addAll(songIds);
    isSelectionMode = selectedSongIds.isNotEmpty;
    notifyListeners();
  }

  void deselectAllSongs() {
    selectedSongIds.clear();
    notifyListeners();
  }

  Future<bool> deleteSelectedSongs(BuildContext context) async {
    final toDelete = songs
        .where((s) => selectedSongIds.contains(s.id))
        .toList(growable: false);
    if (toDelete.isEmpty) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${toDelete.length} track${toDelete.length == 1 ? '' : 's'}?'),
        content: const Text(
          'This will permanently delete the selected audio files from your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    int deletedCount = 0;
    for (final s in toDelete) {
      try {
        final f = File(s.data);
        if (await f.exists()) {
          await f.delete();
          deletedCount++;
        }
      } catch (_) {}
    }

    final deletedIds = toDelete.map((s) => s.id).toSet();
    songs.removeWhere((s) => deletedIds.contains(s.id));
    selectedSongIds.removeWhere(deletedIds.contains);
    if (selectedSongIds.isEmpty) isSelectionMode = false;
    notifyListeners();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted $deletedCount track${deletedCount == 1 ? '' : 's'}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return true;
  }

  void openAboutPage(BuildContext context) {
    context.pushNamed('about');
  }

  Future<void> confirmQuit(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    final shouldQuit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Quit app?'),
          content: const Text('This will completely close the app.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: isDark ? cs.errorContainer : cs.error,
                foregroundColor: isDark ? cs.onErrorContainer : cs.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Quit'),
            ),
          ],
        );
      },
    );

    if (shouldQuit == true) {
      await PlatformExit.quit();
    }
  }

  Future<void> openNowPlaying(BuildContext context, SongModel song) async {
    if (nowPlayingRouteActive) return;
    final lastClosed = _lastNowPlayingClosedAt;
    if (lastClosed != null &&
        DateTime.now().difference(lastClosed) <
            const Duration(milliseconds: 500)) {
      return;
    }

    nowPlayingRouteActive = true;
    try {
      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierDismissible: false,
          barrierColor: Colors.transparent,
          barrierLabel: 'Now Playing',
          transitionDuration: const Duration(milliseconds: 360),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, _, _) => NowPlayingPage(
            player: playbackController.player,
            song: song,
            songs: songs,
            onQueueChanged: (_) {},
            onOpenAlbum: (s) => openAlbumPageFromSong(context, s),
            onOpenArtist: (s) => openArtistPageFromSong(context, s),
            onSongUpdated: updateSongMetadataInPlace,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curve = CurveTween(curve: Curves.easeOutCubic);
            final fade = Tween<double>(begin: 0.0, end: 1.0).chain(curve);

            // When returning to the miniplayer (reverse transition / pop),
            // fade out smoothly without sliding down so the gradient doesn't
            // slide down awkwardly while the Hero artwork flies back into place.
            if (animation.status == AnimationStatus.reverse) {
              return FadeTransition(
                opacity: animation.drive(fade),
                child: child,
              );
            }

            final slide = Tween<Offset>(
              begin: const Offset(0.0, 1.0),
              end: Offset.zero,
            ).chain(curve);

            return SlideTransition(
              position: animation.drive(slide),
              child: FadeTransition(
                opacity: animation.drive(fade),
                child: child,
              ),
            );
          },
        ),
      );
    } finally {
      nowPlayingRouteActive = false;
      _lastNowPlayingClosedAt = DateTime.now();
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    }
  }

  void openAlbumPageFromSong(BuildContext context, SongModel song) {
    final albumId = song.albumId;
    if (albumId == null || albumId <= 0) return;

    final albumTitle = (song.album ?? '').trim().isEmpty
        ? 'Unknown Album'
        : song.album!.trim();
    final albumArtist =
        (song.getMap["album_artist"]?.toString().trim().isNotEmpty ?? false)
            ? song.getMap["album_artist"].toString().trim()
            : ((song.artist ?? '').trim().isEmpty
                ? 'Unknown Artist'
                : song.artist!.trim());

    // Use album identity key to group tracks with the same album artist + album
    // name, even if MediaStore assigned different album IDs (e.g. guest features).
    final targetKey = albumIdentityKey(song);
    final albumSongs = songs
        .where((s) => albumIdentityKey(s) == targetKey)
        .toList();
    albumSongs.sort(compareDiscAndTrack);

    final isPushed = nowPlayingRouteActive || inlineDetailContent != null;

    final albumPage = AlbumPage(
      player: playbackController.player,
      albumId: albumId,
      albumTitle: albumTitle,
      albumArtist: albumArtist,
      songs: albumSongs,
      librarySongs: songs,
      onQueueChanged: (_) {},
      selectedTabIndex: selectedTabIndex,
      onNavigateTab: selectTab,
      embeddedInHome: !isPushed,
      onClose: () {
        if (isPushed) {
          if (context.mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        } else {
          closeInlineDetail();
        }
      },
      onOpenNowPlaying: (s) {
        if (nowPlayingRouteActive) {
          if (context.mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return;
          }
        }
        openNowPlaying(context, s);
      },
      onPlaySong: (s) async {
        final albumIndex = albumSongs.indexWhere((x) => x.id == s.id);
        if (albumIndex == -1) return;
        await playbackController.playFromQueue(albumSongs, initialIndex: albumIndex);
      },
      onShuffle: () async {
        if (albumSongs.isEmpty) return;
        final shuffled = List<SongModel>.from(albumSongs)..shuffle();
        await playbackController.playFromQueue(shuffled, initialIndex: 0);
      },
    );

    if (isPushed) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => albumPage,
        ),
      );
    } else {
      showInlineDetail(albumPage);
    }
  }

  void openArtistPageFromSong(BuildContext context, SongModel song) {
    final name = (song.artist ?? '').trim().isEmpty
        ? 'Unknown Artist'
        : song.artist!.trim();
    openArtistPageByName(context, name);
  }

  void openArtistPageByName(BuildContext context, String artistName) {
    final normalizedArtist = artistName.trim();
    if (normalizedArtist.isEmpty) return;

    String norm(String? v) => (v ?? '').trim().toLowerCase();
    final target = norm(normalizedArtist);

    final artistSongs = songs
        .where((s) {
          final a = norm(s.artist);
          final aa = norm(albumArtistFor(s));
          return a == target || aa == target;
        })
        .toList(growable: false);

    if (artistSongs.isEmpty) return;

    // Group into albums by identity key (albumArtist + albumName) instead of
    // raw MediaStore albumId to prevent fragmentation from guest features.
    final Map<String, List<SongModel>> songsByAlbumKey = {};
    for (final s in artistSongs) {
      final key = albumIdentityKey(s);
      (songsByAlbumKey[key] ??= <SongModel>[]).add(s);
    }

    final albums = <ArtistAlbum>[];
    for (final entry in songsByAlbumKey.entries) {
      final songs = entry.value;
      songs.sort(compareDiscAndTrack);

      final title = (songs.first.album ?? '').trim().isEmpty
          ? 'Unknown Album'
          : songs.first.album!.trim();
      int year = 0;
      for (final s in songs) {
        final y = yearFromSong(s);
        if (y > 0 && (year == 0 || y < year)) year = y;
      }

      int totalMs = 0;
      for (final s in songs) {
        totalMs += (s.duration ?? 0);
      }

      // Use the first song's albumId as the representative for artwork lookups.
      final repAlbumId = songs.first.albumId ?? 0;

      albums.add(
        ArtistAlbum(
          albumId: repAlbumId,
          title: title,
          year: year,
          trackCount: songs.length,
          totalDurationMs: totalMs,
          representativeSong: songs.first,
        ),
      );
    }

    // Sort artist's albums chronologically by release year.
    albums.sort((a, b) {
      final ay = a.year == 0 ? 9999 : a.year;
      final by = b.year == 0 ? 9999 : b.year;
      final yc = ay.compareTo(by);
      if (yc != 0) return yc;
      final tc = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      if (tc != 0) return tc;
      return a.albumId.compareTo(b.albumId);
    });

    // Build album songs lookup by identity key for Play All.
    final albumKeyForAlbum = <int, String>{};
    for (final entry in songsByAlbumKey.entries) {
      final repId = entry.value.first.albumId ?? 0;
      albumKeyForAlbum[repId] = entry.key;
    }

    final isPushed = nowPlayingRouteActive || inlineDetailContent != null;

    final artistPage = ArtistPage(
      player: playbackController.player,
      artistName: normalizedArtist,
      albums: albums,
      artistSongs: artistSongs,
      librarySongs: songs,
      onQueueChanged: (_) {},
      selectedTabIndex: selectedTabIndex,
      onNavigateTab: selectTab,
      embeddedInHome: !isPushed,
      onClose: () {
        if (isPushed) {
          if (context.mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        } else {
          closeInlineDetail();
        }
      },
      onOpenNowPlaying: (s) {
        if (nowPlayingRouteActive) {
          if (context.mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return;
          }
        }
        openNowPlaying(context, s);
      },
      onOpenAlbum: (s) => openAlbumPageFromSong(context, s),
      onPlayAll: albums.isEmpty
          ? null
          : () async {
              final queue = <SongModel>[];
              for (final a in albums) {
                final key = albumKeyForAlbum[a.albumId] ?? '';
                final list = songsByAlbumKey[key] ?? const <SongModel>[];
                final sorted = List<SongModel>.from(list);
                sorted.sort(compareDiscAndTrack);
                queue.addAll(sorted);
              }
              if (queue.isEmpty) return;
              await playbackController.playFromQueue(queue, initialIndex: 0);
            },
      onShuffleAll: artistSongs.isEmpty
          ? null
          : () async {
              final queue = List<SongModel>.from(artistSongs);
              queue.shuffle();
              await playbackController.playFromQueue(queue, initialIndex: 0);
            },
    );

    if (isPushed) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => artistPage,
        ),
      );
    } else {
      showInlineDetail(artistPage);
    }
  }

  void openComposerPageByName(BuildContext context, String composerName) {
    final normalizedComposer = composerName.trim();
    if (normalizedComposer.isEmpty) return;

    String norm(String? v) => (v ?? '').trim().toLowerCase();
    final target = norm(normalizedComposer);

    final composerSongs = songs
        .where((s) {
          final c = norm(s.composer ?? (s.getMap['composer'] as String?));
          return c == target;
        })
        .toList(growable: false);

    if (composerSongs.isEmpty) return;

    final Map<String, List<SongModel>> songsByAlbumKey = {};
    for (final s in composerSongs) {
      final key = albumIdentityKey(s);
      (songsByAlbumKey[key] ??= <SongModel>[]).add(s);
    }

    final albums = <ArtistAlbum>[];
    for (final entry in songsByAlbumKey.entries) {
      final songs = entry.value;
      songs.sort(compareDiscAndTrack);

      final title = (songs.first.album ?? '').trim().isEmpty
          ? 'Unknown Album'
          : songs.first.album!.trim();
      int year = 0;
      for (final s in songs) {
        final y = yearFromSong(s);
        if (y > 0 && (year == 0 || y < year)) year = y;
      }

      int totalMs = 0;
      for (final s in songs) {
        totalMs += (s.duration ?? 0);
      }

      final repAlbumId = songs.first.albumId ?? 0;

      albums.add(
        ArtistAlbum(
          albumId: repAlbumId,
          title: title,
          year: year,
          trackCount: songs.length,
          totalDurationMs: totalMs,
          representativeSong: songs.first,
        ),
      );
    }

    albums.sort((a, b) {
      final ay = a.year == 0 ? 9999 : a.year;
      final by = b.year == 0 ? 9999 : b.year;
      final yc = ay.compareTo(by);
      if (yc != 0) return yc;
      final tc = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      if (tc != 0) return tc;
      return a.albumId.compareTo(b.albumId);
    });

    final albumKeyForAlbum = <int, String>{};
    for (final entry in songsByAlbumKey.entries) {
      final repId = entry.value.first.albumId ?? 0;
      albumKeyForAlbum[repId] = entry.key;
    }

    final isPushed = nowPlayingRouteActive || inlineDetailContent != null;

    final artistPage = ArtistPage(
      player: playbackController.player,
      artistName: normalizedComposer,
      albums: albums,
      artistSongs: composerSongs,
      librarySongs: songs,
      onQueueChanged: (_) {},
      selectedTabIndex: selectedTabIndex,
      onNavigateTab: selectTab,
      embeddedInHome: !isPushed,
      onClose: () {
        if (isPushed) {
          if (context.mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        } else {
          closeInlineDetail();
        }
      },
      onOpenNowPlaying: (s) {
        if (nowPlayingRouteActive) {
          if (context.mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return;
          }
        }
        openNowPlaying(context, s);
      },
      onOpenAlbum: (s) => openAlbumPageFromSong(context, s),
      onPlayAll: albums.isEmpty
          ? null
          : () async {
              final queue = <SongModel>[];
              for (final a in albums) {
                final key = albumKeyForAlbum[a.albumId] ?? '';
                final list = songsByAlbumKey[key] ?? const <SongModel>[];
                final sorted = List<SongModel>.from(list);
                sorted.sort(compareDiscAndTrack);
                queue.addAll(sorted);
              }
              if (queue.isEmpty) return;
              await playbackController.playFromQueue(queue, initialIndex: 0);
            },
      onShuffleAll: composerSongs.isEmpty
          ? null
          : () async {
              final queue = List<SongModel>.from(composerSongs);
              queue.shuffle();
              await playbackController.playFromQueue(queue, initialIndex: 0);
            },
    );

    if (isPushed) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => artistPage,
        ),
      );
    } else {
      showInlineDetail(artistPage);
    }
  }

  void openGenrePage(BuildContext context, GenreStat genre) {
    final isPushed = nowPlayingRouteActive || inlineDetailContent != null;

    final genrePage = GenrePage(
      genre: genre,
      embeddedInHome: !isPushed,
      onClose: () {
        if (isPushed) {
          if (context.mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        } else {
          closeInlineDetail();
        }
      },
      onOpenNowPlaying: (s) {
        if (nowPlayingRouteActive) {
          if (context.mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return;
          }
        }
        openNowPlaying(context, s);
      },
      onOpenAlbum: (s) => openAlbumPageFromSong(context, s),
      onOpenArtist: (s) => openArtistPageFromSong(context, s),
    );

    if (isPushed) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => genrePage,
        ),
      );
    } else {
      showInlineDetail(genrePage);
    }
  }
}

