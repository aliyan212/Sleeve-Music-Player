import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/theme/app_theme.dart';
import 'package:music_player/utils/palette_compute.dart';

void main() {
  group('OLED Theme Builder Tests', () {
    final seedScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00C2A8),
      brightness: Brightness.dark,
    );

    test('buildTheme standard dark mode uses scheme.surface background', () {
      final theme = buildTheme(seedScheme, Brightness.dark, isOled: false);
      expect(theme.scaffoldBackgroundColor, isNot(equals(Colors.black)));
      expect(theme.scaffoldBackgroundColor, equals(seedScheme.surface));
    });

    test('buildTheme Hybrid OLED sets scaffold to black while containers remain distinct', () {
      final theme = buildTheme(seedScheme, Brightness.dark, isOled: true, oledTotalBlack: false);
      expect(theme.scaffoldBackgroundColor, equals(Colors.black));
      expect(theme.colorScheme.surface, equals(Colors.black));
      // In hybrid mode, surfaceContainerLow has subtle contrast
      expect(theme.colorScheme.surfaceContainerLow, isNot(equals(Colors.black)));
    });

    test('buildTheme Total Black OLED sets scaffold and containers to true black', () {
      final theme = buildTheme(seedScheme, Brightness.dark, isOled: true, oledTotalBlack: true);
      expect(theme.scaffoldBackgroundColor, equals(Colors.black));
      expect(theme.colorScheme.surface, equals(Colors.black));
      expect(theme.colorScheme.surfaceContainerLow, equals(Colors.black));
      expect(theme.cardTheme.color, equals(Colors.black));
    });
  });

  group('Monochrome Detection & Palette Tests', () {
    test('isColorAchromatic identifies black, white, and grays', () {
      expect(isColorAchromatic(Colors.black), isTrue);
      expect(isColorAchromatic(Colors.white), isTrue);
      expect(isColorAchromatic(const Color(0xFF141519)), isTrue);
      expect(isColorAchromatic(const Color(0xFF888888)), isTrue);
      expect(isColorAchromatic(const Color(0xFFE0E0E0)), isTrue);
    });

    test('isColorAchromatic rejects saturated colors', () {
      expect(isColorAchromatic(const Color(0xFF00C2A8)), isFalse); // Teal
      expect(isColorAchromatic(const Color(0xFFFF0000)), isFalse); // Red
      expect(isColorAchromatic(const Color(0xFF00FF00)), isFalse); // Green
      expect(isColorAchromatic(const Color(0xFF336699)), isFalse); // Blue
    });

    test('harmonizeBackgroundAccent does not force saturation on monochrome colors', () {
      const pureGrey = Color(0xFF303030);
      final harmonized = harmonizeBackgroundAccent(pureGrey, Colors.black, isDark: true);
      final hsl = HSLColor.fromColor(harmonized);
      expect(hsl.saturation, equals(0.0));
    });
  });
}
