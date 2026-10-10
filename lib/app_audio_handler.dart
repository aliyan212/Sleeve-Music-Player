import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'services/app_lifecycle_observer.dart';

/// Audio handler backing the media notification / lockscreen controls.
///
/// Keep this file minimal and reliable: it should never block app startup.
class AppAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  AppAudioHandler(this.player) {
    unawaited(_initAudioSession());

    _playerStateSub = player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        unawaited(_handlePlaybackCompleted());
      }
      _syncPositionTimer();
      _broadcastState();
    });
    _currentIndexSub = player.currentIndexStream.listen((_) {
      _handleSequenceState(player.sequenceState);
      _broadcastState();
    });
    _sequenceStateSub = player.sequenceStateStream.listen(_handleSequenceState);
    _shuffleSub = player.shuffleModeEnabledStream.listen(
      (_) => _broadcastState(),
    );
    _loopSub = player.loopModeStream.listen((_) => _broadcastState());

    appIsForeground.addListener(() {
      if (appIsForeground.value && player.playing) {
        _broadcastState();
      }
    });

    _broadcastState();
  }

  final AudioPlayer player;

  static const Duration _restartTrackThreshold = Duration(seconds: 10);

  static const String _actionToggleShuffle = 'toggleShuffle';
  static const String _actionToggleRepeat = 'toggleRepeat';
  static const String _actionCloseApp = 'closeApp';

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<int?>? _currentIndexSub;
  StreamSubscription<SequenceState?>? _sequenceStateSub;
  StreamSubscription<bool>? _shuffleSub;
  StreamSubscription<LoopMode>? _loopSub;
  StreamSubscription<void>? _becomingNoisySub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  Timer? _positionUpdateTimer;

  bool _suspendStateUpdates = false;
  bool _playInterrupted = false;
  DateTime? _lastInterruptionResumedAt;

  bool get playInterrupted => _playInterrupted;
  DateTime? get lastInterruptionResumedAt => _lastInterruptionResumedAt;

  void cancelInterruptionResume() {
    _playInterrupted = false;
    _lastInterruptionResumedAt = null;
  }

  AudioSession? _session;

  // ── Audio session ──────────────────────────────────────────────────

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      _session = session;
      await session.configure(
        const AudioSessionConfiguration.music(),
      );

      // Headphones unplugged / BT disconnect → pause smoothly.
      _becomingNoisySub ??= session.becomingNoisyEventStream.listen((_) async {
        await _handleBecomingNoisy();
      });

      _interruptionSub ??=
          session.interruptionEventStream.listen(_handleInterruption);
    } catch (_) {
      // Ignore: audio session not available on some platforms.
    }
  }

  Future<void> _handleBecomingNoisy() async {
    final now = DateTime.now();
    if (_lastInterruptionResumedAt != null &&
        now.difference(_lastInterruptionResumedAt!) <
            const Duration(seconds: 5)) {
      // Ignore noisy broadcast caused by in-call audio route / SCO teardown
      // that Android fires 1-3 seconds after a call ends.
      return;
    }

    _playInterrupted = false;
    if (player.playing) {
      try {
        await player.pause();
      } catch (_) {}
      _broadcastState();
    }
  }

  Future<void> _handleInterruption(AudioInterruptionEvent event) async {
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.pause:
          if (player.playing) {
            _playInterrupted = true;
            try {
              await player.pause();
            } catch (_) {}
          }
          break;
        case AudioInterruptionType.duck:
          // Android OS automatically ducks media at hardware level when
          // androidWillPauseWhenDucked is false. Do not alter volume or pause.
          break;
        case AudioInterruptionType.unknown:
          // Permanent focus loss (e.g. another media app took playback focus).
          _playInterrupted = false;
          _lastInterruptionResumedAt = null;
          try {
            await player.pause();
          } catch (_) {}
          break;
      }
    } else {
      switch (event.type) {
        case AudioInterruptionType.pause:
          if (_playInterrupted) {
            _playInterrupted = false;
            _lastInterruptionResumedAt = DateTime.now();
            try {
              await _session?.setActive(true);
              await player.play();
            } catch (_) {}
          }
          break;
        case AudioInterruptionType.duck:
        case AudioInterruptionType.unknown:
          _playInterrupted = false;
          break;
      }
    }
  }

  @visibleForTesting
  Future<void> handleInterruptionForTesting(AudioInterruptionEvent event) =>
      _handleInterruption(event);

  @visibleForTesting
  Future<void> handleBecomingNoisyForTesting() => _handleBecomingNoisy();

  @visibleForTesting
  void setLastInterruptionResumedAtForTesting(DateTime? time) {
    _lastInterruptionResumedAt = time;
  }

  // ── Playback lifecycle ─────────────────────────────────────────────

  Future<void> disposePlayer() async {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = null;
    _playInterrupted = false;
    await _interruptionSub?.cancel();
    _interruptionSub = null;
    await _playerStateSub?.cancel();
    await _currentIndexSub?.cancel();
    await _sequenceStateSub?.cancel();
    await _shuffleSub?.cancel();
    await _loopSub?.cancel();
    await _becomingNoisySub?.cancel();
    await player.dispose();
  }

  Future<void> _handlePlaybackCompleted() async {
    try {
      await player.pause();
      await player.seek(Duration.zero);
    } catch (_) {}
  }

  void _syncPositionTimer() {
    final isActuallyPlaying = player.playing &&
        player.processingState != ProcessingState.completed;
    if (isActuallyPlaying) {
      _positionUpdateTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
        // Only broadcast periodic position ticks when in foreground.
        // In background, Android MediaSession natively interpolates progress at 1.0x speed.
        if (appIsForeground.value) {
          _broadcastState();
        }
      });
    } else {
      _positionUpdateTimer?.cancel();
      _positionUpdateTimer = null;
    }
  }

  int _queueWindowStartIndex = 0;
  static const int _kQueueWindowRadius = 25;

  void _handleSequenceState(SequenceState? state) {
    if (_suspendStateUpdates) return;
    final seq = state?.sequence ?? const <IndexedAudioSource>[];
    if (seq.isEmpty) {
      _queueWindowStartIndex = 0;
      queue.add(const <MediaItem>[]);
      return;
    }

    final totalLength = seq.length;
    final idx = state?.currentIndex ?? 0;

    // Window around currentIndex (±25 tracks, ~50 total) to prevent Android
    // TransactionTooLargeException across Binder IPC when playlists contain
    // hundreds or thousands of tracks.
    final start = (idx - _kQueueWindowRadius).clamp(0, totalLength - 1);
    final end = (idx + _kQueueWindowRadius + 1).clamp(start + 1, totalLength);
    _queueWindowStartIndex = start;

    final windowSources = seq.sublist(start, end);
    final items = windowSources
        .map(_mediaItemFromSource)
        .whereType<MediaItem>()
        .toList(growable: false);

    queue.add(items);

    if (idx >= 0 && idx < totalLength) {
      final currentItem = _mediaItemFromSource(seq[idx]);
      if (currentItem != null) {
        mediaItem.add(currentItem);
      }
    }
  }

  MediaItem? _mediaItemFromSource(IndexedAudioSource source) {
    final tag = source.tag;
    if (tag is MediaItem) return tag;
    return null;
  }

  // ── Notification / broadcast ───────────────────────────────────────

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  AudioServiceRepeatMode _repeatModeFromLoop(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return AudioServiceRepeatMode.none;
      case LoopMode.one:
        return AudioServiceRepeatMode.one;
      case LoopMode.all:
        return AudioServiceRepeatMode.all;
    }
  }

  List<MediaControl> _notificationControls() {
    final shuffleEnabled = player.shuffleModeEnabled;
    final loopMode = player.loopMode;
    final isActuallyPlaying = player.playing &&
        player.processingState != ProcessingState.completed;

    final rightButton = !isActuallyPlaying
        ? MediaControl.custom(
            androidIcon: 'drawable/ic_close',
            label: 'Close',
            name: _actionCloseApp,
          )
        : MediaControl.custom(
            androidIcon: switch (loopMode) {
              LoopMode.off => 'drawable/ic_repeat_off',
              LoopMode.all => 'drawable/ic_repeat',
              LoopMode.one => 'drawable/ic_repeat_one',
            },
            label: switch (loopMode) {
              LoopMode.off => 'Repeat off',
              LoopMode.all => 'Repeat all',
              LoopMode.one => 'Repeat one',
            },
            name: _actionToggleRepeat,
          );

    return [
      MediaControl.custom(
        androidIcon: shuffleEnabled
            ? 'drawable/ic_shuffle_on'
            : 'drawable/ic_shuffle_off',
        label: shuffleEnabled ? 'Shuffle ON' : 'Shuffle OFF',
        name: _actionToggleShuffle,
      ),
      MediaControl.skipToPrevious,
      isActuallyPlaying ? MediaControl.pause : MediaControl.play,
      MediaControl.skipToNext,
      rightButton,
    ];
  }

  void _broadcastState() {
    if (_suspendStateUpdates) return;
    final isActuallyPlaying = player.playing &&
        player.processingState != ProcessingState.completed;

    playbackState.add(
      playbackState.value.copyWith(
        controls: _notificationControls(),
        androidCompactActionIndices: const [0, 2, 4],
        systemActions: const {MediaAction.seek},
        processingState: _mapProcessingState(player.processingState),
        playing: isActuallyPlaying,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: (player.currentIndex != null && queue.hasValue && queue.value.isNotEmpty)
            ? (player.currentIndex! - _queueWindowStartIndex).clamp(0, queue.value.length - 1)
            : null,
        repeatMode: _repeatModeFromLoop(player.loopMode),
        shuffleMode: player.shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  void setStateBroadcastSuspended(bool suspended) {
    if (_suspendStateUpdates == suspended) return;
    _suspendStateUpdates = suspended;
    if (!suspended) {
      _handleSequenceState(player.sequenceState);
      _broadcastState();
    }
  }

  // ── Transport controls ─────────────────────────────────────────────

  @override
  Future<void> play() async {
    _playInterrupted = false;
    _lastInterruptionResumedAt = null;
    if (player.processingState == ProcessingState.completed) {
      await player.seek(Duration.zero);
    }
    try {
      await _session?.setActive(true);
    } catch (_) {}
    return player.play();
  }

  @override
  Future<void> pause() {
    _playInterrupted = false;
    _lastInterruptionResumedAt = null;
    return player.pause();
  }

  @override
  Future<void> stop() async {
    _playInterrupted = false;
    _lastInterruptionResumedAt = null;
    await player.stop();
    await playbackState.firstWhere(
      (s) => s.processingState == AudioProcessingState.idle,
    );
    try {
      await _session?.setActive(false);
    } catch (_) {}
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() => player.seekToNext();

  @override
  Future<void> skipToPrevious() async {
    final pos = player.position;
    if (pos > _restartTrackThreshold) {
      await player.seek(Duration.zero);
      return;
    }

    if (player.hasPrevious) {
      await player.seekToPrevious();
    } else {
      await player.seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) =>
      player.seek(Duration.zero, index: _queueWindowStartIndex + index);

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    switch (name) {
      case _actionToggleShuffle:
        final enable = !player.shuffleModeEnabled;
        await player.setShuffleModeEnabled(enable);
        if (enable) {
          await player.shuffle();
        }
        _broadcastState();
        break;
      case _actionToggleRepeat:
        final next = switch (player.loopMode) {
          LoopMode.off => LoopMode.all,
          LoopMode.all => LoopMode.one,
          LoopMode.one => LoopMode.off,
        };
        await player.setLoopMode(next);
        _broadcastState();
        break;
      case _actionCloseApp:
        customEvent.add(<String, dynamic>{'type': 'exit'});
        await stop();
        break;
    }
    return super.customAction(name, extras);
  }
}

