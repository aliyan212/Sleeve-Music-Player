import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'playback_controller.dart';

class SleepTimerService extends ChangeNotifier {
  static final SleepTimerService instance = SleepTimerService._();
  SleepTimerService._();

  Timer? _timer;
  DateTime? _endTime;
  bool _isEndOfSong = false;
  StreamSubscription<int?>? _indexSub;
  StreamSubscription<PlayerState>? _stateSub;
  int? _initialSongIndex;

  bool get isActive => _timer != null || _isEndOfSong;
  bool get isEndOfSong => _isEndOfSong;

  Duration? get remaining {
    if (_isEndOfSong) {
      final pos = playbackController.position ?? Duration.zero;
      final dur = playbackController.duration ?? Duration.zero;
      final rem = dur - pos;
      return rem.isNegative ? Duration.zero : rem;
    }
    return _endTime?.difference(DateTime.now());
  }

  void start(Duration duration) {
    cancel();
    _isEndOfSong = false;
    _endTime = DateTime.now().add(duration);
    _timer = Timer(duration, _onTimerExpired);
    notifyListeners();
    // Also notify periodically to update UI countdown if needed
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (!isActive || _isEndOfSong) {
        t.cancel();
      } else {
        notifyListeners();
      }
    });
  }

  void startForEndOfSong() {
    cancel();
    _isEndOfSong = true;
    _initialSongIndex = playbackController.currentIndex;

    _indexSub = playbackController.player.currentIndexStream.listen((index) {
      if (_initialSongIndex != null && index != _initialSongIndex) {
        _onSongEnded();
      }
    });

    _stateSub = playbackController.player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _onSongEnded();
      }
    });

    notifyListeners();

    // Notify periodically so remaining song duration updates in UI
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_isEndOfSong) {
        t.cancel();
      } else {
        notifyListeners();
      }
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _endTime = null;
    _isEndOfSong = false;
    _initialSongIndex = null;
    _indexSub?.cancel();
    _indexSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    notifyListeners();
  }

  void _onTimerExpired() {
    cancel();
    playbackController.pause();
  }

  void _onSongEnded() {
    cancel();
    playbackController.pause();
  }

  Future<void> showSleepTimerDialog(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final durations = [
      const Duration(minutes: 5),
      const Duration(minutes: 15),
      const Duration(minutes: 30),
      const Duration(minutes: 45),
      const Duration(minutes: 60),
    ];

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return ListenableBuilder(
          listenable: this,
          builder: (context, _) {
            final activeRem = remaining;

            Widget buildTimerTile({
              required IconData icon,
              required String title,
              String? subtitle,
              required VoidCallback onTap,
              bool isSelected = false,
              Color? iconColor,
            }) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Material(
                  color: isSelected
                      ? cs.primaryContainer.withValues(alpha: 0.35)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: isSelected
                          ? cs.primary.withValues(alpha: 0.5)
                          : cs.outlineVariant.withValues(alpha: 0.25),
                      width: isSelected ? 1.5 : 0.8,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: (iconColor ?? cs.primary).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(icon, color: iconColor ?? cs.primary, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                                if (subtitle != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check_circle_rounded, color: cs.primary, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sleep Timer',
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Playback will pause when the timer expires',
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isActive)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.35),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.timer_rounded, color: Colors.redAccent, size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  isEndOfSong
                                      ? 'Stopping at end of song${activeRem != null ? ' (~${activeRem.inMinutes}m ${(activeRem.inSeconds % 60).toString().padLeft(2, '0')}s)' : ''}'
                                      : 'Stopping in ${activeRem != null ? '${activeRem.inMinutes}m ${(activeRem.inSeconds % 60).toString().padLeft(2, '0')}s' : ''}',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    buildTimerTile(
                      icon: Icons.music_note_rounded,
                      title: 'End of current song',
                      subtitle: 'Pauses playback when current song finishes',
                      isSelected: isEndOfSong,
                      iconColor: Colors.deepPurpleAccent,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        startForEndOfSong();
                        Navigator.pop(context);
                      },
                    ),
                    ...durations.map((d) {
                      return buildTimerTile(
                        icon: Icons.timer_outlined,
                        title: '${d.inMinutes} minutes',
                        isSelected: isActive && !isEndOfSong && _endTime != null &&
                            (_endTime!.difference(DateTime.now()).inMinutes - d.inMinutes).abs() < 1,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          start(d);
                          Navigator.pop(context);
                        },
                      );
                    }),
                    if (isActive) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                          leading: const Icon(Icons.timer_off_rounded, color: Colors.redAccent),
                          title: const Text(
                            'Turn off timer',
                            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700),
                          ),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            cancel();
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
