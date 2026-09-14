import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../ui/shared/bottom_bars_gutter.dart';
import '../ui/shared/fast_artwork_widget.dart';
import '../utils/format_utils.dart';
import '../utils/palette_compute.dart';
import '../services/playback_controller.dart';
import '../services/app_state_controller.dart';
import '../widgets/universal_song_tile.dart';
import '../ui/shared/app_empty_state.dart';
import 'now_playing_page.dart';

class SmartPlaylistPage extends StatefulWidget {
  const SmartPlaylistPage({
    super.key,
    required this.player,
    required this.title,
    required this.description,
    required this.icon,
    required this.songs,
    required this.librarySongs,
    required this.onQueueChanged,
    required this.selectedTabIndex,
    required this.onNavigateTab,
    this.embeddedInHome = false,
    this.onClose,
    required this.onOpenNowPlaying,
    required this.onPlayAll,
    required this.onPlaySong,
    this.onShuffle,
  });

  final AudioPlayer player;
  final String title;
  final String description;
  final IconData icon;
  final List<SongModel> songs;
  final List<SongModel> librarySongs;
  final Function(List<SongModel>) onQueueChanged;
  final int selectedTabIndex;
  final ValueChanged<int> onNavigateTab;
  final bool embeddedInHome;
  final VoidCallback? onClose;
  final Function(SongModel) onOpenNowPlaying;
  final Future<void> Function()? onPlayAll;
  final Future<void> Function(SongModel) onPlaySong;
  final Future<void> Function()? onShuffle;

  @override
  State<SmartPlaylistPage> createState() => _SmartPlaylistPageState();
}

class _SmartPlaylistPageState extends State<SmartPlaylistPage> {
  late final ScrollController _scrollController;
  bool _isScrolled = false;

  static final Map<int, ({Color primary, Color secondary, Color tertiary})>
      _paletteCache = {};
  int? _lastPaletteSongId;
  Future<({Color primary, Color secondary, Color tertiary})?>? _paletteFuture;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
  }

  void _handleScroll() {
    final scrolled =
        _scrollController.hasClients && _scrollController.offset > 110;
    if (scrolled != _isScrolled) {
      setState(() => _isScrolled = scrolled);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  static Future<({Color primary, Color secondary, Color tertiary})?>
      _loadPalette(int songId) async {
    final cached = _paletteCache[songId];
    if (cached != null) return cached;
    try {
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

      final val = (primary: primary, secondary: secondary, tertiary: tertiary);
      _paletteCache[songId] = val;
      return val;
    } catch (_) {
      return null;
    }
  }

  void _syncPalette(int? leadSongId) {
    if (leadSongId == _lastPaletteSongId) return;
    _lastPaletteSongId = leadSongId;
    if (leadSongId == null) {
      _paletteFuture = Future.value(null);
      return;
    }
    if (!_paletteCache.containsKey(leadSongId)) {
      final seeded = NowPlayingPage.paletteCache[leadSongId];
      if (seeded != null) {
        _paletteCache[leadSongId] = seeded;
      }
    }
    _paletteFuture = _loadPalette(leadSongId);
  }

  Future<void> _playShuffled() async {
    if (widget.onShuffle != null) {
      await widget.onShuffle!();
      return;
    }
    if (widget.songs.isEmpty) return;
    final shuffled = List<SongModel>.from(widget.songs)..shuffle();
    await playbackController.playFromQueue(shuffled, initialIndex: 0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final leadSongId = widget.songs.isNotEmpty ? widget.songs.first.id : null;
    _syncPalette(leadSongId);

    final totalMs =
        widget.songs.fold<int>(0, (sum, s) => sum + (s.duration ?? 0));
    final subtitle =
        '${widget.songs.length} ${widget.songs.length == 1 ? 'track' : 'tracks'} • ${formatPlaylistDuration(totalMs)}';

    final content = Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: FutureBuilder<({Color primary, Color secondary, Color tertiary})?>(
        future: _paletteFuture,
        initialData: leadSongId != null ? _paletteCache[leadSongId] : null,
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
                                  cs.surface.withValues(
                                      alpha: isDark ? 0.92 : 0.96),
                                  top,
                                )
                              : Colors.transparent,
                          surfaceTintColor: Colors.transparent,
                          foregroundColor: cs.onSurface,
                          leading: widget.embeddedInHome
                              ? IconButton(
                                  tooltip: 'Back',
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  onPressed: widget.onClose,
                                )
                              : (Navigator.canPop(context)
                                  ? IconButton(
                                      tooltip: 'Back',
                                      icon:
                                          const Icon(Icons.arrow_back_rounded),
                                      onPressed: () => Navigator.pop(context),
                                    )
                                  : null),
                          title: AnimatedOpacity(
                            duration: const Duration(milliseconds: 220),
                            opacity: _isScrolled ? 1.0 : 0.0,
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          actions: [
                            if (_isScrolled) ...[
                              IconButton(
                                tooltip: 'Play',
                                icon: const Icon(Icons.play_arrow_rounded),
                                onPressed: widget.songs.isEmpty
                                    ? null
                                    : widget.onPlayAll,
                              ),
                              IconButton(
                                tooltip: 'Shuffle',
                                icon: const Icon(Icons.shuffle_rounded),
                                onPressed: widget.songs.isEmpty
                                    ? null
                                    : _playShuffled,
                              ),
                            ],
                          ],
                        ),
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
                                        color: (bgA ?? cs.primary).withValues(
                                          alpha: isDark ? 0.40 : 0.20,
                                        ),
                                        blurRadius: 28,
                                        offset: const Offset(0, 12),
                                        spreadRadius: -2,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (widget.songs.isNotEmpty)
                                          FastArtworkWidget(
                                            id: widget.songs.first.id,
                                            type: ArtworkType.AUDIO,
                                            width: 160,
                                            height: 160,
                                            artworkFit: BoxFit.cover,
                                            nullArtworkWidget: Container(
                                              color: cs.surfaceContainerHighest,
                                              child: Center(
                                                child: Icon(
                                                  widget.icon,
                                                  color: cs.primary,
                                                  size: 64,
                                                ),
                                              ),
                                            ),
                                          )
                                        else
                                          Container(
                                            color: cs.surfaceContainerHighest,
                                            child: Center(
                                              child: Icon(
                                                widget.icon,
                                                color: cs.primary,
                                                size: 64,
                                              ),
                                            ),
                                          ),
                                        if (widget.songs.isNotEmpty)
                                          Positioned(
                                            right: 8,
                                            bottom: 8,
                                            child: Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: cs.surface
                                                    .withValues(alpha: 0.85),
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                            alpha: 0.25),
                                                    blurRadius: 6,
                                                  ),
                                                ],
                                              ),
                                              child: Icon(
                                                widget.icon,
                                                size: 20,
                                                color: cs.primary,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  widget.title,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.5,
                                        color: cs.onSurface,
                                      ),
                                ),
                                if (widget.description.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    widget.description,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.secondaryContainer.withValues(
                                      alpha: isDark ? 0.35 : 0.6,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    subtitle,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: cs.onSecondaryContainer,
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: widget.songs.isEmpty
                                            ? null
                                            : widget.onPlayAll,
                                        icon: const Icon(
                                            Icons.play_arrow_rounded,
                                            size: 22),
                                        label: const Text(
                                          'Play All',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: FilledButton.tonalIcon(
                                        onPressed: widget.songs.isEmpty
                                            ? null
                                            : _playShuffled,
                                        icon: const Icon(Icons.shuffle_rounded,
                                            size: 20),
                                        label: const Text(
                                          'Shuffle',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (widget.songs.isEmpty)
                          AppEmptyState.sliver(
                            icon: widget.icon,
                            title: 'No tracks yet',
                            message:
                                'Tracks will automatically appear here based on your listening habits.',
                          )
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final song = widget.songs[index];
                                final artistText =
                                    (song.artist ?? '').trim().isEmpty
                                        ? 'Unknown Artist'
                                        : song.artist!.trim();

                                final isCurrent = currentSongId == song.id;
                                final isCurrentlyPlaying =
                                    isCurrent && isAudioPlaying;

                                return UniversalSongTile(
                                  song: song,
                                  subtitle: artistText,
                                  isCurrent: isCurrent,
                                  isPlaying: isCurrentlyPlaying,
                                  artworkSize: 48,
                                  artworkBorderRadius:
                                      BorderRadius.circular(10),
                                  borderRadius: BorderRadius.circular(14),
                                  backgroundColor: Colors.transparent,
                                  borderColor: Colors.transparent,
                                  showMetaDuration: false,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 3.5,
                                  ),
                                  trailing: Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Text(
                                      formatTime(song.duration ?? 0),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures()
                                            ],
                                          ),
                                    ),
                                  ),
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    widget.onPlaySong(song);
                                  },
                                  onLongPress: () {
                                    HapticFeedback.selectionClick();
                                    AppStateController.instance
                                        .showSongOptions(song, index);
                                  },
                                );
                              },
                              childCount: widget.songs.length,
                            ),
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
}
