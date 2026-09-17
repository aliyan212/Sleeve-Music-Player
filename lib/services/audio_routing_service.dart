import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AudioOutputDevice {
  const AudioOutputDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.typeLabel,
    this.isBluetooth = false,
    this.isSpeaker = false,
    this.isHeadphones = false,
    this.isCurrent = false,
  });

  final int id;
  final String name;
  final int type;
  final String typeLabel;
  final bool isBluetooth;
  final bool isSpeaker;
  final bool isHeadphones;
  final bool isCurrent;

  factory AudioOutputDevice.fromMap(Map<dynamic, dynamic> map) {
    return AudioOutputDevice(
      id: map['id'] as int? ?? 0,
      name: (map['name'] as String?)?.trim() ?? 'Audio Device',
      type: map['type'] as int? ?? 0,
      typeLabel: map['typeLabel'] as String? ?? 'Audio Output',
      isBluetooth: map['isBluetooth'] as bool? ?? false,
      isSpeaker: map['isSpeaker'] as bool? ?? false,
      isHeadphones: map['isHeadphones'] as bool? ?? false,
      isCurrent: map['isCurrent'] as bool? ?? false,
    );
  }
}

class AudioRoutingService {
  static const MethodChannel _channel = MethodChannel('com.example.music_player/notifications');

  static Future<List<AudioOutputDevice>> getAvailableAudioDevices() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final List<dynamic>? rawList = await _channel.invokeMethod('getAvailableAudioDevices');
        if (rawList == null) return [];
        return rawList
            .whereType<Map<dynamic, dynamic>>()
            .map((m) => AudioOutputDevice.fromMap(m))
            .toList();
      } catch (e) {
        debugPrint('Failed to get available audio devices: $e');
        return [];
      }
    }
    return [];
  }

  static Future<bool> openMediaOutputSwitcher() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final bool? res = await _channel.invokeMethod('openMediaOutputSwitcher');
        return res ?? false;
      } catch (e) {
        debugPrint('Failed to open media output switcher: $e');
        return false;
      }
    }
    return false;
  }

  static Future<bool> setAudioDevice(int? deviceId) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final bool? res = await _channel.invokeMethod('setAudioDevice', {'deviceId': deviceId});
        return res ?? false;
      } catch (e) {
        debugPrint('Failed to set audio device: $e');
        return false;
      }
    }
    return false;
  }

  static Future<void> setSpeakerphoneOn(bool on) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod('setSpeakerphoneOn', {'on': on});
      } catch (e) {
        debugPrint('Failed to set speakerphone: $e');
      }
    } else {
      debugPrint('Audio routing not yet implemented for this platform');
    }
  }

  static Future<void> showAudioOutputDialog(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      backgroundColor: cs.surfaceContainerLow,
      builder: (ctx) {
        return FutureBuilder<List<AudioOutputDevice>>(
          future: getAvailableAudioDevices(),
          builder: (context, snapshot) {
            final isLoading = snapshot.connectionState == ConnectionState.waiting;
            final devices = snapshot.data ?? [];

            // Group: separate Bluetooth from built-in/wired
            final bluetoothDevices = devices.where((d) => d.isBluetooth).toList();
            final otherDevices = devices.where((d) => !d.isBluetooth).toList();

            IconData deviceIcon(AudioOutputDevice d) {
              if (d.isBluetooth) return Icons.bluetooth_audio_rounded;
              if (d.isHeadphones) return Icons.headphones_rounded;
              if (d.isSpeaker) return Icons.volume_up_rounded;
              if (d.type == 11 || d.type == 22) return Icons.usb_rounded;
              if (d.type == 23) return Icons.hearing_rounded;
              return Icons.speaker_rounded;
            }

            Color deviceIconColor(AudioOutputDevice d) {
              if (d.isBluetooth) return Colors.blueAccent;
              if (d.isHeadphones) return Colors.tealAccent;
              if (d.isSpeaker) return cs.primary;
              return cs.onSurfaceVariant;
            }

            Widget buildDeviceTile(AudioOutputDevice d) {
              final icon = deviceIcon(d);
              final iconColor = deviceIconColor(d);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Material(
                  color: d.isCurrent
                      ? cs.primaryContainer.withValues(alpha: 0.35)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: d.isCurrent
                          ? cs.primary.withValues(alpha: 0.45)
                          : cs.outlineVariant.withValues(alpha: 0.25),
                      width: d.isCurrent ? 1.5 : 0.8,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      await setAudioDevice(d.id);
                      if (d.isBluetooth) {
                        // Also trigger native output switcher if user taps Bluetooth device
                        await openMediaOutputSwitcher();
                      }
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: iconColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(icon, color: iconColor, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.name,
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  d.typeLabel,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (d.isCurrent) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_rounded, size: 14, color: cs.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Active',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 20),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Playback Output',
                                  style: textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Choose where your audio plays',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'System Media Switcher',
                            icon: const Icon(Icons.output_rounded, size: 22),
                            onPressed: () async {
                              HapticFeedback.selectionClick();
                              await openMediaOutputSwitcher();
                              if (context.mounted) Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Material(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            await openMediaOutputSwitcher();
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: cs.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(Icons.devices_rounded, size: 20, color: cs.primary),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Open Android Media Output Panel',
                                        style: textTheme.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        'Switch between connected Bluetooth and Cast devices',
                                        style: textTheme.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_forward_rounded, size: 18, color: cs.onSurfaceVariant),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 36),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (devices.isEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                        child: Text(
                          'Connected devices',
                          style: textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                          leading: const Icon(Icons.phone_android_rounded),
                          title: const Text('System Default / Auto'),
                          subtitle: const Text('Plays via system media route'),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setAudioDevice(-1);
                            Navigator.pop(context);
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                          leading: const Icon(Icons.volume_up_rounded),
                          title: const Text('Device Speaker (Force)'),
                          subtitle: const Text('Forces audio to phone speaker'),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setSpeakerphoneOn(true);
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    ] else ...[
                      if (bluetoothDevices.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                          child: Text(
                            'Bluetooth Devices (${bluetoothDevices.length})',
                            style: textTheme.labelMedium?.copyWith(
                              color: Colors.blueAccent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ...bluetoothDevices.map(buildDeviceTile),
                      ],
                      if (otherDevices.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                          child: Text(
                            'Built-in & Wired Devices',
                            style: textTheme.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ...otherDevices.map(buildDeviceTile),
                      ],
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                          leading: Icon(Icons.restart_alt_rounded, color: cs.onSurfaceVariant),
                          title: const Text('Reset to System Default'),
                          subtitle: const Text('Clear forced output routing'),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setAudioDevice(-1);
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
