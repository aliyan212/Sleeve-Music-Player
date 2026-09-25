import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../pages/queue_page.dart';
import '../../dialogs/tag_editor_dialog.dart';
import '../../dialogs/lyrics_editor_dialog.dart';
import 'package:just_audio/just_audio.dart';
import '../../services/sleep_timer_service.dart';
import '../../dialogs/song_info_dialog.dart';


import '../../utils/tag_write_access.dart';

class NowPlayingHeader extends StatelessWidget {
  const NowPlayingHeader({
    super.key,
    required this.player,
    required this.songs,
    required this.displayedSong,
    required this.rawLyrics,
    required this.isFullscreenLandscape,
    required this.showLyrics,
    required this.isDark,
    required this.textColorSecondary,
    required this.iconBgColor,
    required this.iconFgColor,
    required this.onPop,
    required this.onQueueChanged,
    required this.onSetLyricsVisible,
    required this.onSetFullscreenLandscape,
    required this.onSongUpdated,
    required this.onReloadDisplayedSongMetadata,
    required this.onLoadLyrics,
  });

  final AudioPlayer player;
  final List<SongModel> songs;
  final SongModel displayedSong;
  final String? rawLyrics;
  final bool isFullscreenLandscape;
  final bool showLyrics;
  final bool isDark;
  final Color textColorSecondary;
  final Color iconBgColor;
  final Color iconFgColor;
  final VoidCallback onPop;
  final ValueChanged<List<SongModel>>? onQueueChanged;
  final ValueChanged<bool> onSetLyricsVisible;
  final ValueChanged<bool> onSetFullscreenLandscape;
  final ValueChanged<SongModel>? onSongUpdated;
  final VoidCallback onReloadDisplayedSongMetadata;
  final VoidCallback onLoadLyrics;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 10,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton.filledTonal(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: onPop,
            style: IconButton.styleFrom(
              backgroundColor: iconBgColor,
              foregroundColor: iconFgColor,
            ),
          ),
          Text(
            "Now Playing",
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: textColorSecondary,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isFullscreenLandscape) ...[
                IconButton.filledTonal(
                  tooltip: 'Queue',
                  icon: const Icon(Icons.queue_music_rounded),
                  onPressed: () => Navigator.push(
                    context,
                    PageRouteBuilder(
                      opaque: false,
                      pageBuilder: (_, _, _) => QueuePage(
                        player: player,
                        songs: songs,
                        currentIndex: player.currentIndex ?? 0,
                        onPlayIndex: (index) => player.seek(
                          Duration.zero,
                          index: index,
                        ),
                        onQueueChanged: onQueueChanged ?? (_) {},
                      ),
                      transitionsBuilder: (
                        context,
                        animation,
                        secondaryAnimation,
                        child,
                      ) {
                        return SlideTransition(
                          position: Tween(
                                begin: const Offset(
                                  0.0,
                                  1.0,
                                ),
                                end: Offset.zero,
                              )
                              .chain(
                                CurveTween(
                                  curve: Curves.easeOutCubic,
                                ),
                              )
                              .animate(animation),
                          child: child,
                        );
                      },
                    ),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: iconBgColor,
                    foregroundColor: iconFgColor,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: showLyrics ? 'Show artwork' : 'Show lyrics',
                  icon: Icon(
                    showLyrics
                        ? Icons.image_rounded
                        : Icons.lyrics_rounded,
                  ),
                  onPressed: () => onSetLyricsVisible(!showLyrics),
                  style: IconButton.styleFrom(
                    backgroundColor: iconBgColor,
                    foregroundColor: iconFgColor,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: iconFgColor,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: iconBgColor,
                  foregroundColor: iconFgColor,
                ),
                tooltip: 'More actions',
                onSelected: (value) async {
                  HapticFeedback.selectionClick();
                  if (value == 'fullscreen_toggle') {
                    onSetFullscreenLandscape(!isFullscreenLandscape);
                  } else if (value == 'edit_tags') {
                    final result = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => TagEditorDialog(
                        song: displayedSong,
                        onSaved: onReloadDisplayedSongMetadata,
                        onSongUpdated: (updatedSong) {
                          onSongUpdated?.call(updatedSong);
                        },
                        runWithPlaybackSuspended: (action) =>
                            runWithPlayerPlaybackSuspended(
                              player,
                              player.audioSource,
                              action,
                              targetFilePath: displayedSong.data,
                            ),
                      ),
                    );
                    if (result == true) {
                      onReloadDisplayedSongMetadata();
                    }
                  } else if (value == 'sleep_timer') {
                    SleepTimerService.instance.showSleepTimerDialog(context);
                  } else if (value == 'edit_lyrics') {
                    final result = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => LyricsEditorDialog(
                        song: displayedSong,
                        currentLyrics: rawLyrics,
                        onSaved: onLoadLyrics,
                        onLyricsSaved: (lyrics) {
                          onLoadLyrics();
                        },
                        runWithPlaybackSuspended: (action) =>
                            runWithPlayerPlaybackSuspended(
                              player,
                              player.audioSource,
                              action,
                              targetFilePath: displayedSong.data,
                            ),
                      ),
                    );
                    if (result == true) {
                      onLoadLyrics();
                    }
                  } else if (value == 'song_info') {
                    showSongInfoSheet(context, displayedSong);
                  }
                },
                itemBuilder: (context) {
                  final menuTextColor = isDark
                      ? Colors.white
                      : Colors.black87;
                  final menuIconColor = isDark
                      ? Colors.white70
                      : Colors.black54;
                  final fullscreenLabel = isFullscreenLandscape
                      ? 'Exit fullscreen'
                      : 'Fullscreen';
                  final fullscreenIcon = isFullscreenLandscape
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded;
                  return [
                    PopupMenuItem(
                      value: 'fullscreen_toggle',
                      child: Row(
                        children: [
                          Icon(
                            fullscreenIcon,
                            size: 20,
                            color: menuIconColor,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            fullscreenLabel,
                            style: TextStyle(color: menuTextColor),
                          ),
                        ],
                      ),
                    ),
                    if (!isFullscreenLandscape) ...[
                      PopupMenuItem(
                        value: 'sleep_timer',
                        child: Row(
                          children: [
                            Icon(
                              Icons.bedtime_rounded,
                              size: 20,
                              color: menuIconColor,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Sleep Timer',
                              style: TextStyle(
                                color: menuTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'edit_tags',
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_rounded,
                              size: 20,
                              color: menuIconColor,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Edit Tags',
                              style: TextStyle(
                                color: menuTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'edit_lyrics',
                        child: Row(
                          children: [
                            Icon(
                              Icons.lyrics_rounded,
                              size: 20,
                              color: menuIconColor,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Edit Lyrics',
                              style: TextStyle(
                                color: menuTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'song_info',
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 20,
                              color: menuIconColor,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Song info',
                              style: TextStyle(
                                color: menuTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ];
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

