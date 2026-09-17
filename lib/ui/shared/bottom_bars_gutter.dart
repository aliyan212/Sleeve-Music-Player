// ignore_for_file: deprecated_member_use
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../services/playback_controller.dart';
import '../../widgets/mini_player.dart';

/// Reserves scrollable space at the bottom of list pages so the last item can
/// be scrolled fully above the mini-player and the navigation bar, which are
/// overlaid on top of the body via `extendBody: true`.
///
/// The gutter grows when a song is loaded (mini-player visible) so the last
/// row is never hidden behind the player.
Widget buildBottomBarsGutter(
  BuildContext context, {
  bool includeMiniPlayer = true,
  double extraPadding = 0,
}) {
  // Gutter space set to 1.5 cards height (standard card is 80px -> 120px total).
  const double cardHeight = 80.0;
  const double gutterHeight = cardHeight * 1.5;
  return SliverToBoxAdapter(
    child: SizedBox(height: gutterHeight + extraPadding),
  );
}

Widget buildDetailBottomBars({
  required BuildContext context,
  required AudioPlayer player,
  required List<SongModel> songs,
  required int? currentIndex,
  required Function(List<SongModel>) onQueueChanged,
  required Function(SongModel) onOpenNowPlaying,
  required int selectedTabIndex,
  required ValueChanged<int> onNavigateTab,
  bool enableHero = false,
}) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bottomInset = MediaQuery.of(context).padding.bottom;
  final bottomMargin = bottomInset > 0 ? 4.0 : 10.0;
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      MiniPlayer(
        controller: playbackController,
        songs: songs,
        currentIndex: currentIndex,
        onQueueChanged: onQueueChanged,
        onTap: onOpenNowPlaying,
        enableHero: enableHero,
      ),
      SafeArea(
        top: false,
        child: Container(
          margin: EdgeInsets.fromLTRB(16, 0, 16, bottomMargin),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: isDark ? 0.82 : 0.90),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.18),
                    width: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: NavigationBar(
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  selectedIndex: selectedTabIndex,
                  onDestinationSelected: (index) {
                    HapticFeedback.selectionClick();
                    onNavigateTab(index);
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.album_outlined),
                      selectedIcon: Icon(Icons.album_rounded),
                      label: 'Albums',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.people_outline_rounded),
                      selectedIcon: Icon(Icons.people_rounded),
                      label: 'Album Artists',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.queue_music_outlined),
                      selectedIcon: Icon(Icons.queue_music_rounded),
                      label: 'Playlists',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}