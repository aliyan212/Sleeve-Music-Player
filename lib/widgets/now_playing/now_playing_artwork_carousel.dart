import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../ui/shared/fast_artwork_widget.dart';
import '../../ui/shared/snappy_artwork_scroll_physics.dart';

class NowPlayingArtworkCarousel extends StatelessWidget {
  const NowPlayingArtworkCarousel({
    super.key,
    required this.player,
    required this.isFullscreen,
    required this.sequence,
    required this.effectiveIndices,
    required this.pageController,
    required this.isProgrammaticPageChange,
    required this.onUserSwipedToPage,
    required this.displayedSong,
    required this.artworkPulseController,
    required this.primaryColor,
    required this.alignment,
  });

  final AudioPlayer player;
  final bool isFullscreen;
  final List<IndexedAudioSource> sequence;
  final List<int> effectiveIndices;
  final PageController pageController;
  final bool isProgrammaticPageChange;
  final ValueChanged<int> onUserSwipedToPage;
  final SongModel displayedSong;
  final AnimationController artworkPulseController;
  final Color? primaryColor;
  final Alignment alignment;

  Widget _buildNowPlayingArtwork({required double side}) {
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(32),
      ),
      child: const Icon(
        Icons.music_note,
        size: 100,
        color: Colors.white38,
      ),
    );
  }

  Widget _buildArtworkPageView({
    required double side,
  }) {
    if (sequence.isEmpty) {
      return _buildNowPlayingArtwork(side: side);
    }

    final itemCount = effectiveIndices.length;

    return PageView.builder(
      controller: pageController,
      physics: SnappyArtworkScrollPhysics(itemCount: itemCount),
      itemCount: itemCount,
      onPageChanged: (page) {
        if (isProgrammaticPageChange) return;
        if (page < 0 || page >= effectiveIndices.length) return;
        onUserSwipedToPage(page);
        final targetSeqIndex = effectiveIndices[page];
        if (targetSeqIndex != player.currentIndex) {
          player.seek(Duration.zero, index: targetSeqIndex);
        }
      },
      itemBuilder: (context, page) {
        if (page < 0 || page >= effectiveIndices.length) {
          return _buildNowPlayingArtwork(side: side);
        }
        final seqIndex = effectiveIndices[page];
        if (seqIndex < 0 || seqIndex >= sequence.length) {
          return _buildNowPlayingArtwork(side: side);
        }
        final currentSource = sequence[seqIndex];
        final tag = currentSource.tag;

        int? songId;
        if (tag is MediaItem) {
          songId = int.tryParse(tag.id);
        } else if (tag is SongModel) {
          songId = tag.id;
        }

        if (songId == null) {
          return _buildNowPlayingArtwork(side: side);
        }

        final artworkWidget = FastArtworkWidget(
          id: songId,
          type: ArtworkType.AUDIO,
          size: 900,
          quality: 100,
          width: side,
          height: side,
          keepOldArtwork: true,
          nullArtworkWidget: Container(
            width: side,
            height: side,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(32),
            ),
            child: const Icon(
              Icons.music_note,
              size: 100,
              color: Colors.white38,
            ),
          ),
        );

        if (!isFullscreen && songId == displayedSong.id) {
          return Hero(
            tag: 'now_playing_artwork_$songId',
            createRectTween: (begin, end) =>
                MaterialRectArcTween(begin: begin, end: end),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: artworkWidget,
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: artworkWidget,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxSide = math.min(constraints.maxWidth, constraints.maxHeight);
        final side = (maxSide.isFinite ? maxSide : 320.0).clamp(160.0, 380.0);

        final pulse = Tween<double>(begin: 1.0, end: 1.02).animate(
          CurvedAnimation(
            parent: artworkPulseController,
            curve: Curves.easeInOut,
          ),
        );

        return Align(
          alignment: alignment,
          child: ScaleTransition(
            scale: pulse,
            child: SizedBox(
              width: side,
              height: side,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (primaryColor ?? Colors.black).withValues(
                        alpha: 0.5,
                      ),
                      blurRadius: 40,
                      spreadRadius: 10,
                      offset: const Offset(0, 15),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: _buildArtworkPageView(
                  side: side,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
