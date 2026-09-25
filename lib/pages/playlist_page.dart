import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import '../services/playback_controller.dart';
import '../utils/palette_compute.dart';
import '../ui/shared/fast_artwork_widget.dart';
import '../utils/format_utils.dart';
import '../utils/song_sort_utils.dart';
import '../ui/shared/bottom_bars_gutter.dart';
import '../ui/shared/app_action_sheet.dart';
import '../widgets/universal_song_tile.dart';
import '../dialogs/add_songs_sheet.dart';
import '../widgets/multi_select_action_bar.dart';
import '../ui/shared/app_empty_state.dart';
import 'now_playing_page.dart';
export 'smart_playlist_page.dart';

enum PlaylistSort { manual, artist, albumArtist, year, albumArtistYear }


class UserPlaylistPage extends StatefulWidget {
  const UserPlaylistPage({super.key, 
    required this.player,
    required this.playlistId,
    required this.playlistName,
    required this.initialSongIds,
    required this.librarySongs,
    required this.onQueueChanged,
    required this.selectedTabIndex,
    required this.onNavigateTab,
    this.embeddedInHome = false,
    this.onClose,
    required this.onOpenNowPlaying,
    required this.playFromQueue,
    required this.onUpdateSongIds,
  });

  final AudioPlayer player;
  final String playlistId;
  final String playlistName;
  final List<int> initialSongIds;
  final List<SongModel> librarySongs;
  final Function(List<SongModel>) onQueueChanged;
  final int selectedTabIndex;
  final ValueChanged<int> onNavigateTab;
  final bool embeddedInHome;
  final VoidCallback? onClose;
  final Function(SongModel) onOpenNowPlaying;
  final Future<void> Function(List<SongModel> songs, int initialIndex)
  playFromQueue;
  final Future<void> Function(String playlistId, List<int> newSongIds)
  onUpdateSongIds;

  @override
  State<UserPlaylistPage> createState() => UserPlaylistPageState();
}

class UserPlaylistPageState extends State<UserPlaylistPage> {
  late List<int> _songIds;
  late List<int> _manualSongIds;
  PlaylistSort _playlistSort = PlaylistSort.manual;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;
  bool _selectionMode = false;
  final Set<int> _selectedSongIds = <int>{};
  late final ScrollController _scrollController;
  bool _isScrolled = false;

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final scrolled = _scrollController.offset > 50;
    if (scrolled != _isScrolled) {
      setState(() => _isScrolled = scrolled);
    }
  }

  static final Map<int, ({Color primary, Color secondary, Color tertiary})>
  _playlistPaletteCache = {};
  static const int _playlistPaletteCacheMax = 64;

  Future<({Color primary, Color secondary, Color tertiary})?>? _paletteFuture;
  int? _paletteSongId;

  static Future<({Color primary, Color secondary, Color tertiary})?> _loadPlaylistPalette(
    int songId,
  ) async {
    try {
      final cached = _playlistPaletteCache.remove(songId);
      if (cached != null) {
        _playlistPaletteCache[songId] = cached;
        return cached;
      }

      final bytes = await queryArtworkBytesCached(
        songId,
        type: ArtworkType.AUDIO,
        size: 320,
      );
      if (bytes == null) return null;

      final result = await computePaletteFromBytes(bytes);
      final primaryColorInt = result['primary'] ?? 0xFF303030;
      final secondaryColorInt = result['secondary'] ?? primaryColorInt;
      final tertiaryColorInt = result['tertiary'] ?? secondaryColorInt;

      final primary = boostVibrance(
        Color(primaryColorInt),
        extraSaturation: 0.5,
        extraLightness: 0.08,
      );
      final secondary = boostVibrance(
        Color(secondaryColorInt),
        extraSaturation: 0.42,
        extraLightness: -0.02,
      );
      final tertiary = boostVibrance(
        Color(tertiaryColorInt),
        extraSaturation: 0.46,
        extraLightness: 0.03,
      );

      final value = (
        primary: primary,
        secondary: secondary,
        tertiary: tertiary,
      );
      _playlistPaletteCache.remove(songId);
      _playlistPaletteCache[songId] = value;
      while (_playlistPaletteCache.length > _playlistPaletteCacheMax) {
        _playlistPaletteCache.remove(_playlistPaletteCache.keys.first);
      }
      return value;
    } catch (_) {
      return null;
    }
  }

  void _syncPalette(int? leadSongId) {
    if (leadSongId == _paletteSongId && _paletteFuture != null) return;
    _paletteSongId = leadSongId;
    if (leadSongId != null) {
      if (!_playlistPaletteCache.containsKey(leadSongId)) {
        final seeded = NowPlayingPage.paletteCache[leadSongId];
        if (seeded != null) {
          _playlistPaletteCache[leadSongId] = seeded;
        }
      }
      _paletteFuture = _loadPlaylistPalette(leadSongId);
    } else {
      _paletteFuture = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_handleScroll);
    _songIds = List<int>.from(widget.initialSongIds);
    _manualSongIds = List<int>.from(widget.initialSongIds);
    _searchController.addListener(() {
      final next = _searchController.text.trim();
      if (next == _searchQuery) return;
      setState(() => _searchQuery = next);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Map<int, SongModel> _idToSong() {
    return {for (final s in widget.librarySongs) s.id: s};
  }

  List<int> _visibleSongIds(Map<int, SongModel> map) {
    return _songIds.where(map.containsKey).toList();
  }

  Future<void> _persistSongIds() async {
    await widget.onUpdateSongIds(widget.playlistId, _songIds);
  }



  Future<void> _playShuffledQueue(List<SongModel> songs) async {
    if (songs.isEmpty) return;
    final shuffled = List<SongModel>.from(songs);
    shuffled.shuffle(math.Random());
    await widget.playFromQueue(shuffled, 0);
  }

  void _enterSelectionMode(int songId) {
    setState(() {
      _selectionMode = true;
      _selectedSongIds.add(songId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedSongIds.clear();
    });
  }

  void _toggleSelection(int songId) {
    setState(() {
      if (_selectedSongIds.contains(songId)) {
        _selectedSongIds.remove(songId);
      } else {
        _selectedSongIds.add(songId);
      }
      if (_selectedSongIds.isEmpty) _selectionMode = false;
    });
  }

  Future<void> _removeSongsByIds(List<int> ids, {bool showUndo = true}) async {
    final removeSet = ids.toSet();
    if (removeSet.isEmpty) return;

    final prevSongIds = List<int>.from(_songIds);
    final prevManual = List<int>.from(_manualSongIds);
    final prevSort = _playlistSort;

    setState(() {
      _songIds = _songIds.where((id) => !removeSet.contains(id)).toList();
      _manualSongIds = _manualSongIds
          .where((id) => !removeSet.contains(id))
          .toList();
      _selectedSongIds.removeAll(removeSet);
      if (_selectedSongIds.isEmpty) _selectionMode = false;
    });

    if (_playlistSort == PlaylistSort.manual) {
      await _persistSongIds();
    } else {
      await _applyPlaylistSort(_playlistSort);
    }

    if (!mounted || !showUndo || removeSet.length != 1) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('Removed from playlist'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              setState(() {
                _songIds = List<int>.from(prevSongIds);
                _manualSongIds = List<int>.from(prevManual);
                _playlistSort = prevSort;
              });
              unawaited(_persistSongIds());
            },
          ),
        ),
      );
  }

  Future<void> _confirmRemoveSelected() async {
    if (_selectedSongIds.isEmpty) return;
    final count = _selectedSongIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove songs?'),
        content: Text(
          'Remove $count song${count == 1 ? '' : 's'} from this playlist?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ids = _selectedSongIds.toList(growable: false);
    await _removeSongsByIds(ids, showUndo: false);
  }

  Future<void> _copyPlaylistText(List<SongModel> songs) async {
    final lines = <String>[];
    for (final s in songs) {
      final artist = (s.artist ?? '').trim();
      final text = artist.isEmpty ? s.title : '${s.title} - $artist';
      lines.add(text);
    }
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Playlist copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _copyPlaylistM3u(List<SongModel> songs) async {
    final lines = <String>['#EXTM3U'];
    for (final s in songs) {
      final seconds = ((s.duration ?? 0) / 1000).round();
      final artist = (s.artist ?? '').trim();
      final info = artist.isEmpty ? s.title : '$artist - ${s.title}';
      lines.add('#EXTINF:$seconds,$info');
      lines.add(s.data);
    }
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('M3U playlist copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _sanitizeFileName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'playlist';
    final sanitized = trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return sanitized.isEmpty ? 'playlist' : sanitized;
  }

  Future<void> _exportPlaylistM3u(List<SongModel> songs) async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export is not supported on web builds.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose export folder',
    );
    if (dir == null || dir.trim().isEmpty) return;

    final base = _sanitizeFileName(widget.playlistName);
    final sep = dir.contains('\\') ? '\\' : '/';
    final basePath = dir.endsWith(sep) ? dir : '$dir$sep';
    var path = '$basePath$base.m3u';
    if (await File(path).exists()) {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      path = '$basePath${base}_$stamp.m3u';
    }

    final lines = <String>['#EXTM3U'];
    for (final s in songs) {
      final seconds = ((s.duration ?? 0) / 1000).round();
      final artist = (s.artist ?? '').trim();
      final info = artist.isEmpty ? s.title : '$artist - ${s.title}';
      lines.add('#EXTINF:$seconds,$info');
      lines.add(s.data);
    }
    
    await File(path).writeAsString(lines.join('\n'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playlist exported to $path'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _playlistSortLabel(PlaylistSort mode) {
    switch (mode) {
      case PlaylistSort.manual:
        return 'Manual';
      case PlaylistSort.artist:
        return 'Artist';
      case PlaylistSort.albumArtist:
        return 'Album Artist';
      case PlaylistSort.year:
        return 'Year';
      case PlaylistSort.albumArtistYear:
        return 'Album Artist / Year';
    }
  }

  Future<void> _applyPlaylistSort(PlaylistSort mode) async {
    if (!mounted) return;
    HapticFeedback.selectionClick();
    final map = _idToSong();

    if (mode == PlaylistSort.manual) {
      setState(() {
        _playlistSort = mode;
        _songIds = List<int>.from(_manualSongIds);
      });
      await _persistSongIds();
      return;
    }

    final visible = _visibleSongIds(
      map,
    ).map((id) => map[id]!).toList(growable: false);

    // Precompute album-level year so all tracks in the same album sort together
    // regardless of per-track year tag differences.
    final albumYearMap = computeAlbumYearMap(visible);
    int albumYear(SongModel s) {
      final y = albumYearMap[albumIdentityKey(s)] ?? 0;
      return y == 0 ? 99999 : y;
    }

    final sorted = List<SongModel>.from(visible);
    sorted.sort((a, b) {
      switch (mode) {
        case PlaylistSort.artist:
          final artistComp = compareSortStrings(
            a.artist ?? "",
            b.artist ?? "",
          );
          if (artistComp != 0) return artistComp;
          final titleComp = compareSortStrings(a.title, b.title);
          if (titleComp != 0) return titleComp;
          return a.id.compareTo(b.id);
        case PlaylistSort.albumArtist:
          final artistComp = compareSortStrings(
            albumArtistFor(a),
            albumArtistFor(b),
          );
          if (artistComp != 0) return artistComp;
          final albumComp = compareSortStrings(a.album ?? "", b.album ?? "");
          if (albumComp != 0) return albumComp;
          final trackComp = compareDiscAndTrack(a, b);
          if (trackComp != 0) return trackComp;
          final titleComp = compareSortStrings(a.title, b.title);
          if (titleComp != 0) return titleComp;
          return a.id.compareTo(b.id);
        case PlaylistSort.year:
          final yearComp = albumYear(a).compareTo(albumYear(b));
          if (yearComp != 0) return yearComp;
          final artistComp = compareSortStrings(
            albumArtistFor(a),
            albumArtistFor(b),
          );
          if (artistComp != 0) return artistComp;
          final albumComp = compareSortStrings(a.album ?? "", b.album ?? "");
          if (albumComp != 0) return albumComp;
          final trackComp = compareDiscAndTrack(a, b);
          if (trackComp != 0) return trackComp;
          final titleComp = compareSortStrings(a.title, b.title);
          if (titleComp != 0) return titleComp;
          return a.id.compareTo(b.id);
        case PlaylistSort.albumArtistYear:
        default:
          final artistComp = compareSortStrings(
            albumArtistFor(a),
            albumArtistFor(b),
          );
          if (artistComp != 0) return artistComp;
          final yearComp = albumYear(a).compareTo(albumYear(b));
          if (yearComp != 0) return yearComp;
          final albumComp = compareSortStrings(a.album ?? "", b.album ?? "");
          if (albumComp != 0) return albumComp;
          final trackComp = compareDiscAndTrack(a, b);
          if (trackComp != 0) return trackComp;
          final titleComp = compareSortStrings(a.title, b.title);
          if (titleComp != 0) return titleComp;
          return a.id.compareTo(b.id);
      }
    });

    final missing = _songIds
        .where((id) => !map.containsKey(id))
        .toList(growable: false);
    setState(() {
      _playlistSort = mode;
      _songIds = <int>[...sorted.map((s) => s.id), ...missing];
      _manualSongIds = List<int>.from(_songIds);
    });
    await _persistSongIds();
  }

  void _reorderVisible(int oldIndex, int newIndex) {
    final map = _idToSong();
    final visible = _visibleSongIds(map);
    if (oldIndex < 0 || oldIndex >= visible.length) return;
    if (newIndex < 0 || newIndex > visible.length) return;
    if (newIndex > oldIndex) newIndex -= 1;

    final moved = visible.removeAt(oldIndex);
    visible.insert(newIndex, moved);

    // Preserve any missing ids by appending them at the end.
    final missing = _songIds
        .where((id) => !map.containsKey(id))
        .toList(growable: false);

    setState(() {
      _songIds = <int>[...visible, ...missing];
      _manualSongIds = List<int>.from(_songIds);
      _playlistSort = PlaylistSort.manual;
    });
    unawaited(_persistSongIds());
  }

  Future<void> _addSongs() async {
    final toAdd = await showAddSongsSheet(
      context: context,
      librarySongs: widget.librarySongs,
      existingSongIds: _songIds.toSet(),
    );
    if (toAdd.isEmpty) return;

    final existing = _songIds.toSet();
    final added = <int>[];
    for (final id in toAdd) {
      if (existing.add(id)) added.add(id);
    }
    if (added.isEmpty) return;

    setState(() {
      _songIds = <int>[..._songIds, ...added];
      _manualSongIds = <int>[..._manualSongIds, ...added];
    });
    if (_playlistSort == PlaylistSort.manual) {
      await _persistSongIds();
    } else {
      await _applyPlaylistSort(_playlistSort);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added ${added.length} song${added.length == 1 ? '' : 's'}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showPlaylistOptionsMenu(BuildContext context, List<SongModel> allSongs, int totalMs) {
    final cs = Theme.of(context).colorScheme;
    final firstSongId = allSongs.isNotEmpty ? allSongs.first.id : 0;
    final headerThumbnail = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: firstSongId > 0
          ? FastArtworkWidget(
              id: firstSongId,
              type: ArtworkType.AUDIO,
              width: 48,
              height: 48,
              nullArtworkWidget: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.playlist_play_rounded, color: cs.onSurfaceVariant),
              ),
            )
          : Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.playlist_play_rounded, color: cs.onSurfaceVariant),
            ),
    );

    final headerSubtitle = '${allSongs.length} tracks • ${formatPlaylistDuration(totalMs)}';

    showAppActionSheet<void>(
      context: context,
      headerThumbnail: headerThumbnail,
      headerTitle: widget.playlistName,
      headerSubtitle: headerSubtitle,
      sections: [
        AppActionSection(
          title: 'Playlist Options',
          items: [
            AppActionItem(
              icon: Icons.add_rounded,
              title: 'Add songs',
              subtitle: 'Add more tracks to this playlist',
              onTap: _addSongs,
            ),
            AppActionItem(
              icon: Icons.copy_rounded,
              title: 'Copy track list',
              subtitle: 'Copy track names to clipboard',
              onTap: () => _copyPlaylistText(allSongs),
            ),
            AppActionItem(
              icon: Icons.playlist_add_check_rounded,
              title: 'Copy M3U',
              subtitle: 'Copy M3U playlist format to clipboard',
              onTap: () => _copyPlaylistM3u(allSongs),
            ),
            AppActionItem(
              icon: Icons.file_download_outlined,
              title: 'Export M3U file',
              subtitle: 'Save M3U file to device storage',
              onTap: () => _exportPlaylistM3u(allSongs),
            ),
          ],
        ),
        AppActionSection(
          title: 'Sort Playlist',
          items: [
            AppActionItem(
              icon: Icons.drag_indicator_rounded,
              title: 'Manual (Custom)',
              trailing: _playlistSort == PlaylistSort.manual
                  ? Icon(Icons.check_rounded, color: cs.primary, size: 20)
                  : null,
              onTap: () => _applyPlaylistSort(PlaylistSort.manual),
            ),
            AppActionItem(
              icon: Icons.person_outline_rounded,
              title: 'Artist',
              trailing: _playlistSort == PlaylistSort.artist
                  ? Icon(Icons.check_rounded, color: cs.primary, size: 20)
                  : null,
              onTap: () => _applyPlaylistSort(PlaylistSort.artist),
            ),
            AppActionItem(
              icon: Icons.album_outlined,
              title: 'Album Artist',
              trailing: _playlistSort == PlaylistSort.albumArtist
                  ? Icon(Icons.check_rounded, color: cs.primary, size: 20)
                  : null,
              onTap: () => _applyPlaylistSort(PlaylistSort.albumArtist),
            ),
            AppActionItem(
              icon: Icons.calendar_today_rounded,
              title: 'Year',
              trailing: _playlistSort == PlaylistSort.year
                  ? Icon(Icons.check_rounded, color: cs.primary, size: 20)
                  : null,
              onTap: () => _applyPlaylistSort(PlaylistSort.year),
            ),
            AppActionItem(
              icon: Icons.auto_awesome_rounded,
              title: 'Album Artist / Year',
              trailing: _playlistSort == PlaylistSort.albumArtistYear
                  ? Icon(Icons.check_rounded, color: cs.primary, size: 20)
                  : null,
              onTap: () => _applyPlaylistSort(PlaylistSort.albumArtistYear),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final map = _idToSong();
    final visibleIds = _visibleSongIds(map);
    final allSongs = visibleIds.map((id) => map[id]!).toList(growable: false);

    // Synchronize palette with the leading song in the playlist
    final leadSongId = allSongs.isNotEmpty ? allSongs.first.id : null;
    _syncPalette(leadSongId);

    final query = _searchQuery.trim().toLowerCase();
    final songs = query.isEmpty
        ? allSongs
        : allSongs
              .where((s) {
                final title = s.title.toLowerCase();
                final artist = (s.artist ?? '').toLowerCase();
                final album = (s.album ?? '').toLowerCase();
                return title.contains(query) ||
                    artist.contains(query) ||
                    album.contains(query);
              })
              .toList(growable: false);
    final totalMs = allSongs.fold<int>(0, (sum, s) => sum + (s.duration ?? 0));
    final subtitle =
        '${allSongs.length} tracks • ${formatPlaylistDuration(totalMs)}';
    final canReorder =
        _playlistSort == PlaylistSort.manual &&
        query.isEmpty &&
        !_selectionMode &&
        !_isSearching;

    final content = Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: FutureBuilder<({Color primary, Color secondary, Color tertiary})?>(
        future: _paletteFuture,
        initialData: leadSongId != null ? _playlistPaletteCache[leadSongId] : null,
        builder: (context, snap) {
        final p = snap.data;
        final bgA = p?.primary;
        final bgB = p?.secondary;
        final bgC = p?.tertiary;
        final top = bgA != null
            ? Color.alphaBlend(
                bgA.withValues(alpha: isDark ? 0.22 : 0.12),
                cs.surface,
              )
            : cs.surfaceContainerLow;
        final mid = bgB != null
            ? Color.alphaBlend(
                bgB.withValues(alpha: isDark ? 0.15 : 0.08),
                cs.surface,
              )
            : cs.surface;
        final accent = bgC != null
            ? Color.alphaBlend(
                bgC.withValues(alpha: isDark ? 0.12 : 0.06),
                cs.surface,
              )
            : cs.surface;

        return Stack(
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: p != null
                    ? DecoratedBox(
                        key: ValueKey<int>(Object.hash(bgA, bgB)),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [top, mid, accent, cs.surface],
                            stops: const [0.0, 0.38, 0.72, 1.0],
                          ),
                        ),
                        child: const SizedBox.expand(),
                      )
                    : const SizedBox.expand(key: ValueKey<String>('empty_palette')),
              ),
            ),
            StreamBuilder<int?>(
              stream: widget.player.currentIndexStream,
              builder: (context, _) {
                return StreamBuilder<bool>(
                  stream: widget.player.playingStream,
                  builder: (context, _) {
                    final currentSongId = playbackController.currentSongId;
                    final isAudioPlaying = widget.player.playing;

                    return CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverAppBar(
                          pinned: true,
                          elevation: 0,
                          scrolledUnderElevation: 0,
                          backgroundColor: _isScrolled
                              ? Color.alphaBlend(
                                  cs.surface.withValues(alpha: isDark ? 0.92 : 0.96),
                                  top,
                                )
                              : Colors.transparent,
                          surfaceTintColor: Colors.transparent,
                          foregroundColor: cs.onSurface,
                  leading: _isSearching
                      ? IconButton(
                          tooltip: 'Back',
                          icon: const Icon(Icons.arrow_back_rounded),
                          onPressed: () {
                            FocusScope.of(context).unfocus();
                            FocusManager.instance.primaryFocus?.unfocus();
                            SystemChannels.textInput.invokeMethod('TextInput.hide');
                            setState(() {
                              _isSearching = false;
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : (widget.embeddedInHome
                          ? IconButton(
                              tooltip: 'Back',
                              icon: const Icon(Icons.arrow_back_rounded),
                              onPressed: () {
                                FocusScope.of(context).unfocus();
                                FocusManager.instance.primaryFocus?.unfocus();
                                SystemChannels.textInput.invokeMethod('TextInput.hide');
                                widget.onClose?.call();
                              },
                            )
                          : (Navigator.canPop(context)
                              ? IconButton(
                                  tooltip: 'Back',
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  onPressed: () {
                                    FocusScope.of(context).unfocus();
                                    FocusManager.instance.primaryFocus?.unfocus();
                                    SystemChannels.textInput.invokeMethod('TextInput.hide');
                                    Navigator.pop(context);
                                  },
                                )
                              : null)),
                  title: _isSearching
                      ? TextField(
                          controller: _searchController,
                          autofocus: true,
                          onTapOutside: (_) {
                            FocusScope.of(context).unfocus();
                            FocusManager.instance.primaryFocus?.unfocus();
                            SystemChannels.textInput.invokeMethod('TextInput.hide');
                          },
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: cs.onSurface,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search playlist...',
                            hintStyle: TextStyle(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                            border: InputBorder.none,
                          ),
                        )
                      : (_selectionMode
                          ? Text(
                              '${_selectedSongIds.length} selected',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : AnimatedOpacity(
                              duration: const Duration(milliseconds: 220),
                              opacity: _isScrolled ? 1.0 : 0.0,
                              child: Text(
                                widget.playlistName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )),
                  actions: [
                    if (_isSearching) ...[
                      IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          setState(() {
                            _isSearching = false;
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      ),
                    ] else if (_selectionMode) ...[
                      MultiSelectActionButtons(
                        selectedCount: _selectedSongIds.length,
                        totalCount: songs.length,
                        onToggleSelectAll: () {
                          setState(() {
                            if (_selectedSongIds.length == songs.length) {
                              _selectedSongIds.clear();
                            } else {
                              _selectedSongIds.addAll(songs.map((s) => s.id));
                            }
                          });
                        },
                        onRemove: _confirmRemoveSelected,
                        onCancel: _exitSelectionMode,
                      ),
                    ] else ...[
                      if (_isScrolled) ...[
                        IconButton(
                          tooltip: 'Play',
                          icon: const Icon(Icons.play_arrow_rounded),
                          onPressed: songs.isEmpty
                              ? null
                              : () async => widget.playFromQueue(songs, 0),
                        ),
                        IconButton(
                          tooltip: 'Shuffle',
                          icon: const Icon(Icons.shuffle_rounded),
                          onPressed: allSongs.isEmpty
                              ? null
                              : () async => _playShuffledQueue(allSongs),
                        ),
                      ],
                      IconButton(
                        tooltip: 'Search in playlist',
                        icon: const Icon(Icons.search_rounded),
                        onPressed: () {
                          setState(() => _isSearching = true);
                        },
                      ),
                      IconButton(
                        tooltip: 'More options',
                        icon: const Icon(Icons.more_horiz_rounded),
                        onPressed: () => _showPlaylistOptionsMenu(context, allSongs, totalMs),
                      ),
                    ],
                  ],
                ),
                if (!_isSearching)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: (bgA ?? Colors.black).withValues(
                                    alpha: isDark ? 0.40 : 0.16,
                                  ),
                                  blurRadius: 28,
                                  offset: const Offset(0, 12),
                                  spreadRadius: -2,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: allSongs.isEmpty
                                  ? Container(
                                      color: cs.surfaceContainerHighest,
                                      child: Icon(
                                        Icons.playlist_play_rounded,
                                        color: cs.onSurfaceVariant,
                                        size: 64,
                                      ),
                                    )
                                  : FastArtworkWidget(
                                      id: allSongs.first.id,
                                      type: ArtworkType.AUDIO,
                                      width: 160,
                                      height: 160,
                                      artworkFit: BoxFit.cover,
                                      nullArtworkWidget: Container(
                                        color: cs.surfaceContainerHighest,
                                        child: Icon(
                                          Icons.playlist_play_rounded,
                                          color: cs.onSurfaceVariant,
                                          size: 64,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.playlistName,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_playlistSort != PlaylistSort.manual) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer.withValues(
                                  alpha: isDark ? 0.35 : 0.6,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.sort_rounded,
                                    size: 14,
                                    color: cs.onSecondaryContainer,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Sorted by ${_playlistSortLabel(_playlistSort)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSecondaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: songs.isEmpty
                                      ? null
                                      : () async => widget.playFromQueue(songs, 0),
                                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                                  label: const Text(
                                    'Play',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: allSongs.isEmpty
                                      ? null
                                      : () async => _playShuffledQueue(allSongs),
                                  icon: const Icon(Icons.shuffle_rounded, size: 20),
                                  label: const Text(
                                    'Shuffle',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              IconButton.filledTonal(
                                tooltip: 'Add songs',
                                onPressed: _addSongs,
                                icon: const Icon(Icons.add_rounded),
                              ),
                              const SizedBox(width: 6),
                              IconButton.filledTonal(
                                tooltip: 'More options',
                                onPressed: () => _showPlaylistOptionsMenu(context, allSongs, totalMs),
                                icon: const Icon(Icons.more_horiz_rounded),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if (songs.isEmpty)
                  AppEmptyState.sliver(
                    icon: _isSearching
                        ? Icons.search_off_rounded
                        : Icons.music_note_rounded,
                    title: _isSearching
                        ? 'No matches found'
                        : 'Playlist is empty',
                    message: _isSearching
                        ? 'No songs match "$_searchQuery"'
                        : 'Add tracks from your library to this playlist.',
                    actionLabel: _isSearching ? null : 'Add songs',
                    actionIcon: Icons.add_rounded,
                    onAction: _isSearching ? null : _addSongs,
                  )
                else
                  SliverReorderableList(
                    proxyDecorator: (Widget child, int index, Animation<double> animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (BuildContext context, Widget? child) {
                          final double animValue = Curves.easeOutBack.transform(animation.value);
                          final double scale = lerpDouble(1.0, 1.03, animValue)!;
                          final cs = Theme.of(context).colorScheme;

                          return Transform.scale(
                            scale: scale,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: cs.primary.withValues(alpha: 0.25 * animValue),
                                    blurRadius: 18 * animValue,
                                    offset: Offset(0, 6 * animValue),
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2 * animValue),
                                    blurRadius: 10 * animValue,
                                    offset: Offset(0, 3 * animValue),
                                  ),
                                ],
                              ),
                              child: child,
                            ),
                          );
                        },
                        child: child,
                      );
                    },
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      final artistText = (song.artist ?? '').trim().isEmpty
                          ? 'Unknown Artist'
                          : song.artist!.trim();
                      final isSelected = _selectedSongIds.contains(song.id);
                      final canDismiss = !_selectionMode && !_isSearching;

                      Widget trailing;
                      if (_selectionMode) {
                        trailing = Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleSelection(song.id),
                        );
                      } else if (canReorder) {
                        trailing = ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                            child: Icon(
                              Icons.drag_handle_rounded,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                        );
                      } else {
                        trailing = Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            formatTime(song.duration ?? 0),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        );
                      }

                      final isCurrent = currentSongId == song.id;
                      final isCurrentlyPlaying = isCurrent && isAudioPlaying;

                      final tile = UniversalSongTile(
                        song: song,
                        subtitle: artistText,
                        isSelected: isSelected,
                        isSelectionMode: _selectionMode,
                        isCurrent: isCurrent,
                        isPlaying: isCurrentlyPlaying,
                        artworkSize: 48,
                        artworkBorderRadius: BorderRadius.circular(10),
                        borderRadius: BorderRadius.circular(14),
                        showMetaDuration: false,
                        backgroundColor: isSelected
                            ? cs.secondaryContainer.withValues(
                                alpha: isDark ? 0.35 : 0.6,
                              )
                            : Colors.transparent,
                        borderColor: Colors.transparent,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 3.5,
                        ),
                        trailing: trailing,
                        onTap: () {
                          if (_selectionMode) {
                            _toggleSelection(song.id);
                            return;
                          }
                          HapticFeedback.selectionClick();
                          widget.playFromQueue(songs, index);
                        },
                        onLongPress: () {
                          if (_selectionMode) {
                            _toggleSelection(song.id);
                            return;
                          }
                          HapticFeedback.mediumImpact();
                          _showTrackOptionsSheet(
                            context,
                            song,
                            index,
                            songs,
                            playbackController,
                          );
                        },
                      );

                      return Dismissible(
                        key: ValueKey('playlist_${widget.playlistId}_${song.id}'),
                        direction: canDismiss
                            ? DismissDirection.endToStart
                            : DismissDirection.none,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          color: Colors.redAccent.withValues(alpha: 0.85),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white,
                          ),
                        ),
                        confirmDismiss: (_) async => canDismiss,
                        onDismissed: (_) => _removeSongsByIds([song.id]),
                        child: tile,
                      );
                    },
                    itemCount: songs.length,
                    onReorderStart: (_) => HapticFeedback.mediumImpact(),
                    onReorder: canReorder ? _reorderVisible : (a, b) {},
                  ),
                  buildBottomBarsGutter(context),
                ],
              );
            },
          );
        },
      ),
    ],
  );
      },
    ),
  );

    if (widget.embeddedInHome) return content;

    return Scaffold(
      extendBody: true,
      bottomNavigationBar: StreamBuilder<int?>(
        stream: widget.player.currentIndexStream,
        builder: (context, snapshot) {
          return buildDetailBottomBars(
            context: context,
            player: widget.player,
            songs: widget.librarySongs,
            currentIndex: snapshot.data ?? widget.player.currentIndex,
            onQueueChanged: widget.onQueueChanged,
            onOpenNowPlaying: widget.onOpenNowPlaying,
            selectedTabIndex: widget.selectedTabIndex,
            onNavigateTab: widget.onNavigateTab,
          );
        },
      ),
      body: content,
    );
  }

  void _showTrackOptionsSheet(
    BuildContext context,
    SongModel song,
    int index,
    List<SongModel> songs,
    PlaybackController playbackController,
  ) {
    final songTitle =
        song.title.trim().isEmpty ? 'Unknown Title' : song.title.trim();
    final artist = (song.artist?.trim().isEmpty ?? true)
        ? 'Unknown Artist'
        : song.artist!.trim();

    final cs = Theme.of(context).colorScheme;
    final headerThumbnail = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: FastArtworkWidget(
        id: song.id,
        type: ArtworkType.AUDIO,
        width: 48,
        height: 48,
        nullArtworkWidget: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.music_note_rounded,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );

    showAppActionSheet<void>(
      context: context,
      headerThumbnail: headerThumbnail,
      headerTitle: songTitle,
      headerSubtitle: artist,
      items: [
        AppActionItem(
          icon: Icons.playlist_play_rounded,
          title: 'Play next',
          onTap: () {
            playbackController.insertInQueue(song);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Playing next'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
        AppActionItem(
          icon: Icons.queue_music_rounded,
          title: 'Add to queue',
          onTap: () {
            playbackController.addToQueueEnd(song);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Added to queue'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
        AppActionItem(
          icon: Icons.checklist_rounded,
          title: 'Select track',
          onTap: () {
            _enterSelectionMode(song.id);
          },
        ),
        AppActionItem(
          icon: Icons.delete_outline_rounded,
          title: 'Remove from playlist',
          isDestructive: true,
          onTap: () {
            _removeSongsByIds([song.id]);
          },
        ),
      ],
    );
  }
}

