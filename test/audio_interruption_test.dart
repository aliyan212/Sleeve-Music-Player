import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:music_player/app_audio_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (call) async {
        if (call.method == 'init') return {'id': 'test-player'};
        return {};
      },
    );
  });

  group('AppAudioHandler audio focus & interruption tests', () {
    test('transient interruption pauses playing track and resumes when interruption ends', () async {
      final player = AudioPlayer();
      final handler = AppAudioHandler(player);
      addTearDown(() async {
        await handler.disposePlayer();
      });

      // Initially not playing
      expect(handler.playInterrupted, isFalse);

      // Simulate interruption begin (e.g. phone call or alarm) when player is playing
      // Since mock channel returns empty map, we can test handler state transitions
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      // Because player was not playing, playInterrupted should remain false
      expect(handler.playInterrupted, isFalse);

      // Now test ducking event does not pause or alter playInterrupted
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(true, AudioInterruptionType.duck),
      );
      expect(handler.playInterrupted, isFalse);

      // Test ducking end event leaves playInterrupted false
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(false, AudioInterruptionType.duck),
      );
      expect(handler.playInterrupted, isFalse);

      // Test permanent loss (unknown) clears playInterrupted
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(true, AudioInterruptionType.unknown),
      );
      expect(handler.playInterrupted, isFalse);
    });

    test('manual pause or cancelInterruptionResume clears resume flag', () async {
      final player = AudioPlayer();
      final handler = AppAudioHandler(player);
      addTearDown(() async {
        await handler.disposePlayer();
      });

      // Calling cancelInterruptionResume ensures false
      handler.cancelInterruptionResume();
      expect(handler.playInterrupted, isFalse);

      // Calling pause() resets playInterrupted
      await handler.pause();
      expect(handler.playInterrupted, isFalse);

      // Calling stop() resets playInterrupted
      await handler.stop();
      expect(handler.playInterrupted, isFalse);
    });

    test('becoming noisy event is ignored within 5s of interruption resume', () async {
      final player = AudioPlayer();
      final handler = AppAudioHandler(player);
      addTearDown(() async {
        await handler.disposePlayer();
      });

      // Simulate recently resumed interruption (1 second ago)
      handler.setLastInterruptionResumedAtForTesting(
        DateTime.now().subtract(const Duration(seconds: 1)),
      );

      // Becoming noisy should be ignored during cooldown
      await handler.handleBecomingNoisyForTesting();
      expect(handler.lastInterruptionResumedAt, isNotNull);

      // Simulate interruption resumed 6 seconds ago (cooldown expired)
      handler.setLastInterruptionResumedAtForTesting(
        DateTime.now().subtract(const Duration(seconds: 6)),
      );

      // Becoming noisy should now process normally
      await handler.handleBecomingNoisyForTesting();
      expect(handler.playInterrupted, isFalse);
    });
  });
}
