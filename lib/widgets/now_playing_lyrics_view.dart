import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/foundation.dart';
import '../utils/lyrics.dart';

import 'lyrics/synced_lyrics_view.dart';

class NowPlayingLyricsView extends StatelessWidget {
  const NowPlayingLyricsView({
    super.key,
    required this.rawLyrics,
    required this.isSynced,
    required this.lrcLines,
    required this.activeLyricIndex,
    required this.itemScrollController,
    required this.itemPositionsListener,
    required this.displayedArtworkBytes,
    required this.currentLyricIndex,
    required this.player,
    required this.onPauseAutoScroll,
    required this.alignmentForLine,
  });

  final String? rawLyrics;
  final bool isSynced;
  final List<LyricLine> lrcLines;
  final ValueListenable<int> activeLyricIndex;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final Uint8List? displayedArtworkBytes;
  final int currentLyricIndex;
  final AudioPlayer player;
  final VoidCallback onPauseAutoScroll;
  final double Function(int) alignmentForLine;

  @override
  Widget build(BuildContext context) {
    return SyncedLyricsView(
      rawLyrics: rawLyrics,
      isSynced: isSynced,
      lrcLines: lrcLines,
      activeLyricIndex: activeLyricIndex,
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      displayedArtworkBytes: displayedArtworkBytes,
      onSeek: (time) {
        onPauseAutoScroll();
        player.seek(time);
      },
      onUserScroll: onPauseAutoScroll,
      initialScrollIndex: currentLyricIndex >= 0 ? currentLyricIndex : 0,
      initialAlignment: alignmentForLine(
        currentLyricIndex >= 0 ? currentLyricIndex : 0,
      ),
    );
  }
}

