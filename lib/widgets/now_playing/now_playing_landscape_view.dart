import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

/// Fullscreen landscape presentation for Now Playing.
/// Features side-by-side artwork with floating playback overlay controls,
/// track metadata, and an integrated synchronized lyrics panel.
class NowPlayingLandscapeView extends StatelessWidget {
  final bool isDark;
  final Color textColor;
  final Color textColorSecondary;
  final Color iconBgColor;
  final Color iconFgColor;
  final Color? primaryColor;
  final SongModel displayedSong;
  final AudioPlayer player;
  final Animation<double> artworkPulseAnimation;
  final bool controlsVisible;
  final VoidCallback onToggleControls;
  final Widget Function(double side) artworkPageViewBuilder;
  final Widget lyricsView;
  final VoidCallback onOpenArtist;
  final VoidCallback onOpenAlbum;

  const NowPlayingLandscapeView({
    super.key,
    required this.isDark,
    required this.textColor,
    required this.textColorSecondary,
    required this.iconBgColor,
    required this.iconFgColor,
    required this.primaryColor,
    required this.displayedSong,
    required this.player,
    required this.artworkPulseAnimation,
    required this.controlsVisible,
    required this.onToggleControls,
    required this.artworkPageViewBuilder,
    required this.lyricsView,
    required this.onOpenArtist,
    required this.onOpenAlbum,
  });

  @override
  Widget build(BuildContext context) {
    final lyricsPanelBg = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Theme.of(context)
            .colorScheme
            .primary
            .withValues(alpha: isDark ? 0.10 : 0.06),
        Theme.of(context)
            .colorScheme
            .surface
            .withValues(alpha: isDark ? 0.14 : 0.10),
      ],
    );

    final mediaPadding = MediaQuery.paddingOf(context);
    final safeLeft = math.max(20.0, mediaPadding.left);
    final safeRight = math.max(20.0, mediaPadding.right);
    final safeTop = math.max(8.0, mediaPadding.top);
    final safeBottom = math.max(12.0, mediaPadding.bottom);

    return Padding(
      padding: EdgeInsets.fromLTRB(safeLeft, safeTop, safeRight, safeBottom),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW =
              constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
          final maxH =
              constraints.maxHeight.isFinite ? constraints.maxHeight : 400.0;

          const panelGap = 24.0;
          const minLyricsW = 280.0;
          const metadataHeight = 96.0;
          const artworkSpacing = 12.0;

          final maxSideByHeight = maxH - metadataHeight - artworkSpacing;
          final maxSideByWidth = maxW - minLyricsW - panelGap;
          final side =
              math.min(maxSideByHeight, maxSideByWidth).clamp(150.0, 380.0);
          final leftW = side;

          final pulse = Tween<double>(begin: 1.0, end: 1.02).animate(
            CurvedAnimation(
              parent: artworkPulseAnimation,
              curve: Curves.easeInOut,
            ),
          );

          final artwork = ScaleTransition(
            scale: pulse,
            child: SizedBox(
              width: side,
              height: side,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: (primaryColor ?? Colors.black).withValues(
                        alpha: 0.45,
                      ),
                      blurRadius: 36,
                      spreadRadius: 6,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: 0.25,
                      ),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: artworkPageViewBuilder(side),
              ),
            ),
          );

          final artworkStack = Center(
            child: GestureDetector(
              onTap: onToggleControls,
              child: SizedBox(
                width: side,
                height: side,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: TweenAnimationBuilder<double>(
                        duration: const Duration(
                          milliseconds: 180,
                        ),
                        curve: Curves.easeOut,
                        tween: Tween<double>(
                          begin: 0,
                          end: controlsVisible ? 8 : 0,
                        ),
                        builder: (context, sigma, _) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: ImageFiltered(
                              imageFilter: ImageFilter.blur(
                                sigmaX: sigma,
                                sigmaY: sigma,
                              ),
                              child: artwork,
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 10,
                      child: AnimatedOpacity(
                        duration: const Duration(
                          milliseconds: 180,
                        ),
                        opacity: controlsVisible ? 1 : 0,
                        child: IgnorePointer(
                          ignoring: !controlsVisible,
                          child: Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surface
                                      .withValues(
                                        alpha: isDark ? 0.28 : 0.40,
                                      ),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white10
                                        : Colors.black12,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    999,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton.filledTonal(
                                      onPressed: player.hasPrevious
                                          ? () => player.seekToPrevious()
                                          : null,
                                      icon: const Icon(
                                        Icons.skip_previous_rounded,
                                      ),
                                      style: IconButton.styleFrom(
                                        backgroundColor:
                                            iconBgColor.withValues(
                                          alpha: 0.30,
                                        ),
                                        foregroundColor: iconFgColor,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    StreamBuilder<PlayerState>(
                                      stream: player.playerStateStream,
                                      builder: (context, snap) {
                                        final playing =
                                            (snap.data?.playing ?? false) &&
                                                snap.data?.processingState !=
                                                    ProcessingState.completed;
                                        return IconButton.filledTonal(
                                          onPressed: playing
                                              ? player.pause
                                              : () async {
                                                  if (player.processingState ==
                                                      ProcessingState
                                                          .completed) {
                                                    await player.seek(
                                                      Duration.zero,
                                                    );
                                                  }
                                                  player.play();
                                                },
                                          icon: Icon(
                                            playing
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                          ),
                                          style: IconButton.styleFrom(
                                            backgroundColor:
                                                iconBgColor.withValues(
                                              alpha: 0.30,
                                            ),
                                            foregroundColor: iconFgColor,
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                    IconButton.filledTonal(
                                      onPressed: player.hasNext
                                          ? () => player.seekToNext()
                                          : null,
                                      icon: const Icon(
                                        Icons.skip_next_rounded,
                                      ),
                                      style: IconButton.styleFrom(
                                        backgroundColor:
                                            iconBgColor.withValues(
                                          alpha: 0.30,
                                        ),
                                        foregroundColor: iconFgColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          final metadata = SizedBox(
            width: side,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayedSong.title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onOpenArtist();
                  },
                  child: Text(
                    displayedSong.artist ?? "Unknown Artist",
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: textColor.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onOpenAlbum();
                  },
                  child: Text(
                    displayedSong.album ?? "Unknown Album",
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: textColorSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: leftW,
                child: Center(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        artworkStack,
                        const SizedBox(height: artworkSpacing),
                        metadata,
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: panelGap),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: lyricsPanelBg,
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: lyricsView,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
