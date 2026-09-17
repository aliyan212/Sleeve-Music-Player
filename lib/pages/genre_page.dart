import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../data/models/album_stat.dart';
import '../data/models/genre_stat.dart';
import '../services/app_state_controller.dart';
import '../services/playback_controller.dart';
import '../ui/shared/bottom_bars_gutter.dart';
import '../ui/shared/fast_artwork_widget.dart';
import '../utils/format_utils.dart';
import '../utils/palette_compute.dart';
import '../utils/song_sort_utils.dart';
import '../widgets/genre_collage_artwork.dart';
import '../widgets/universal_song_tile.dart';

class GenrePage extends StatefulWidget {
  final GenreStat genre;
  final bool embeddedInHome;
  final VoidCallback? onClose;
  final Function(SongModel) onOpenNowPlaying;
  final Function(SongModel) onOpenAlbum;
  final Function(SongModel)? onOpenArtist;

  const GenrePage({
    super.key,
    required this.genre,
    this.embeddedInHome = false,
    this.onClose,
    required this.onOpenNowPlaying,
    required this.onOpenAlbum,
    this.onOpenArtist,
  });

  @override
  State<GenrePage> createState() => _GenrePageState();
}

class _GenrePageState extends State<GenrePage> {
  Color? _accentColor;
  final Set<int> _selectedSongIds = <int>{};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _extractPalette();
  }

  Future<void> _extractPalette() async {
    final rep = widget.genre.representativeSong;
    if (rep == null) return;
    final albumId = rep.albumId ?? rep.id;
    final bytes = await queryArtworkBytesCached(albumId, type: ArtworkType.ALBUM, size: 200);
    if (bytes != null && mounted) {
      final palette = await computePaletteFromBytes(bytes);
      final pInt = palette['primary'];
      if (pInt != null && mounted) {
        setState(() {
          _accentColor = Color(pInt);
        });
      }
    }
  }

  List<SongModel> _getGenreSongs(AppStateController appState) {
    final target = widget.genre.name.toLowerCase();
    return appState.songs.where((s) {
      final raw = s.genre?.trim();
      if (raw == null || raw.isEmpty) {
        return target == 'unknown genre';
      }
      final parts = raw
          .split(RegExp(r'[/;]'))
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty);
      return parts.contains(target);
    }).toList(growable: false);
  }

  List<ArtistAlbum> _getGenreAlbums(List<SongModel> songs) {
    final Map<String, List<SongModel>> songsByAlbumKey = {};
    for (final s in songs) {
      final key = albumIdentityKey(s);
      (songsByAlbumKey[key] ??= <SongModel>[]).add(s);
    }

    final albums = <ArtistAlbum>[];
    for (final entry in songsByAlbumKey.entries) {
      final albumSongs = entry.value;
      albumSongs.sort(compareDiscAndTrack);
      final title = (albumSongs.first.album ?? '').trim().isEmpty
          ? 'Unknown Album'
          : albumSongs.first.album!.trim();
      int year = 0;
      for (final s in albumSongs) {
        final y = yearFromSong(s);
        if (y > 0 && (year == 0 || y < year)) year = y;
      }
      int totalMs = 0;
      for (final s in albumSongs) {
        totalMs += (s.duration ?? 0);
      }
      albums.add(
        ArtistAlbum(
          albumId: albumSongs.first.albumId ?? 0,
          title: title,
          year: year,
          trackCount: albumSongs.length,
          totalDurationMs: totalMs,
          representativeSong: albumSongs.first,
        ),
      );
    }

    albums.sort((a, b) {
      final comp = b.trackCount.compareTo(a.trackCount);
      if (comp != 0) return comp;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return albums;
  }

  void _toggleSelectSong(SongModel song) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedSongIds.contains(song.id)) {
        _selectedSongIds.remove(song.id);
        if (_selectedSongIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedSongIds.add(song.id);
        _isSelectionMode = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appState = AppStateController.instance;
    final genreSongs = _getGenreSongs(appState);
    final albums = _getGenreAlbums(genreSongs);

    final effectiveAccent = _accentColor ?? cs.primary;

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSelectionMode) {
          setState(() {
            _isSelectionMode = false;
            _selectedSongIds.clear();
          });
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: CustomScrollView(
          slivers: [
            // Sliver App Bar
            SliverAppBar(
              expandedHeight: 260,
              pinned: true,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () {
                  if (_isSelectionMode) {
                    setState(() {
                      _isSelectionMode = false;
                      _selectedSongIds.clear();
                    });
                  } else if (widget.onClose != null) {
                    widget.onClose!();
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
              title: Text(
                widget.genre.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              actions: [
                if (_isSelectionMode)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: Text(
                        '${_selectedSongIds.length} selected',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            effectiveAccent.withValues(alpha: 0.35),
                            theme.scaffoldBackgroundColor,
                          ],
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 36),
                            GenreCollageArtwork(
                              genre: widget.genre,
                              size: 110,
                              borderRadius: 20,
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                widget.genre.name,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${genreSongs.length} tracks • ${albums.length} albums • ${formatPlaylistDuration(widget.genre.totalDurationMs)}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Play / Shuffle Buttons
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: genreSongs.isEmpty
                            ? null
                            : () async {
                                await playbackController.playFromQueue(
                                  genreSongs,
                                  initialIndex: 0,
                                );
                              },
                        icon: const Icon(Icons.play_arrow_rounded, size: 22),
                        label: const Text(
                          'Play All',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: genreSongs.isEmpty
                            ? null
                            : () async {
                                final shuffled = List<SongModel>.from(genreSongs)
                                  ..shuffle();
                                await playbackController.playFromQueue(
                                  shuffled,
                                  initialIndex: 0,
                                );
                              },

                        icon: const Icon(Icons.shuffle_rounded, size: 20),
                        label: const Text(
                          'Shuffle',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Albums Carousel (if more than 1 album)
            if (albums.length > 1) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        'Albums in ${widget.genre.name}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${albums.length}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 190,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: albums.length,
                    itemBuilder: (context, index) {
                      final album = albums[index];
                      return GestureDetector(
                        onTap: () => widget.onOpenAlbum(album.representativeSong),
                        child: Container(
                          width: 130,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: FastArtworkWidget(
                                  id: album.albumId,
                                  type: ArtworkType.ALBUM,
                                  width: 130,
                                  height: 130,
                                  nullArtworkWidget: Container(
                                    width: 130,
                                    height: 130,
                                    color: cs.surfaceContainerHighest,
                                    child: Icon(
                                      Icons.album_rounded,
                                      size: 48,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                album.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '${album.trackCount} tracks',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],

            // Tracks Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  'Tracks',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // Tracks List
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final song = genreSongs[index];
                  final isSelected = _selectedSongIds.contains(song.id);

                  final isCurrent = playbackController.currentSongId == song.id;
                  final isPlaying = isCurrent && playbackController.player.playing;

                  return UniversalSongTile(
                    key: ValueKey('genre_song_${song.id}'),
                    song: song,
                    isCurrent: isCurrent,
                    isPlaying: isPlaying,
                    isSelectionMode: _isSelectionMode,
                    isSelected: isSelected,
                    onTap: () {
                      if (_isSelectionMode) {
                        _toggleSelectSong(song);
                        return;
                      }
                      HapticFeedback.selectionClick();
                      playbackController.playFromQueue(genreSongs, initialIndex: index);
                    },
                    onLongPress: () => _toggleSelectSong(song),
                  );
                },
                childCount: genreSongs.length,
              ),
            ),

            // Gutter space for bottom bar
            buildBottomBarsGutter(context),

          ],
        ),
      ),
    );
  }
}
