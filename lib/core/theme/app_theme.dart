import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  system,
  light,
  dark,
  darkOled,
}

enum OledStyle {
  hybrid,
  total,
}

class ThemeNotifier extends ValueNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.system) {
    _loadTheme();
  }

  static const String _themeKey = 'theme_mode';
  static const String _appThemeModeKey = 'app_theme_mode';
  static const String _oledStyleKey = 'oled_style';

  AppThemeMode _appThemeMode = AppThemeMode.system;
  OledStyle _oledStyle = OledStyle.hybrid;

  AppThemeMode get appThemeMode => _appThemeMode;
  OledStyle get oledStyle => _oledStyle;
  bool get isOled => _appThemeMode == AppThemeMode.darkOled;
  bool get oledTotalBlack => isOled && _oledStyle == OledStyle.total;

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedAppModeStr = prefs.getString(_appThemeModeKey);
    final savedOledStyleStr = prefs.getString(_oledStyleKey);

    if (savedOledStyleStr != null) {
      _oledStyle = OledStyle.values.firstWhere(
        (e) => e.name == savedOledStyleStr,
        orElse: () => OledStyle.hybrid,
      );
    }

    if (savedAppModeStr != null) {
      _appThemeMode = AppThemeMode.values.firstWhere(
        (e) => e.name == savedAppModeStr,
        orElse: () => AppThemeMode.system,
      );
    } else {
      final legacyThemeStr = prefs.getString(_themeKey);
      if (legacyThemeStr == 'light') {
        _appThemeMode = AppThemeMode.light;
      } else if (legacyThemeStr == 'dark') {
        _appThemeMode = AppThemeMode.dark;
      } else {
        _appThemeMode = AppThemeMode.system;
      }
    }

    value = switch (_appThemeMode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.darkOled => ThemeMode.dark,
    };
    notifyListeners();
  }

  Future<void> setAppThemeMode(AppThemeMode mode) async {
    _appThemeMode = mode;
    value = switch (mode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.darkOled => ThemeMode.dark,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appThemeModeKey, mode.name);
    final legacyStr = switch (mode) {
      AppThemeMode.system => 'system',
      AppThemeMode.light => 'light',
      AppThemeMode.dark => 'dark',
      AppThemeMode.darkOled => 'dark',
    };
    await prefs.setString(_themeKey, legacyStr);
    notifyListeners();
  }

  Future<void> setOledStyle(OledStyle style) async {
    _oledStyle = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_oledStyleKey, style.name);
    notifyListeners();
  }

  Future<void> toggle() async {
    // Cycle: System -> Light -> Dark (Material) -> Dark (OLED) -> System
    final nextMode = switch (_appThemeMode) {
      AppThemeMode.system => AppThemeMode.light,
      AppThemeMode.light => AppThemeMode.dark,
      AppThemeMode.dark => AppThemeMode.darkOled,
      AppThemeMode.darkOled => AppThemeMode.system,
    };
    await setAppThemeMode(nextMode);
  }

  bool get isDark => value == ThemeMode.dark;

  String get themeMenuLabel {
    return switch (_appThemeMode) {
      AppThemeMode.system => 'Theme: System',
      AppThemeMode.light => 'Theme: Light',
      AppThemeMode.dark => 'Theme: Dark (Material)',
      AppThemeMode.darkOled => 'Theme: Dark (OLED)',
    };
  }
}

ThemeData buildTheme(
  ColorScheme rawScheme,
  Brightness brightness, {
  bool isOled = false,
  bool oledTotalBlack = false,
}) {
    final isDark = brightness == Brightness.dark;
    final scheme = (isDark && isOled)
        ? rawScheme.copyWith(
            surface: Colors.black,
            surfaceDim: Colors.black,
            surfaceBright: oledTotalBlack ? Colors.black : const Color(0xFF16181D),
            surfaceContainerLowest: Colors.black,
            surfaceContainerLow: oledTotalBlack ? Colors.black : const Color(0xFF101216),
            surfaceContainer: oledTotalBlack ? Colors.black : const Color(0xFF16181F),
            surfaceContainerHigh: oledTotalBlack ? const Color(0xFF0E0F12) : const Color(0xFF1E2028),
            surfaceContainerHighest: oledTotalBlack ? const Color(0xFF16181E) : const Color(0xFF262832),
          )
        : rawScheme;

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );

    final textTheme = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    final titleLarge = textTheme.titleLarge?.copyWith(
      // Slightly softened weight and spacing for a cleaner look
      fontWeight: FontWeight.w700,
      letterSpacing: -0.15,
    );
    final titleMedium = textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
    );
    final labelMedium = textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.15,
    );

    return base.copyWith(
      textTheme: textTheme.copyWith(
        titleLarge: titleLarge,
        titleMedium: titleMedium,
        labelMedium: labelMedium,
      ),
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor: (isDark && isOled) ? Colors.black : scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: titleLarge,
        toolbarTextStyle: textTheme.bodyMedium,
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        },
      ),
      navigationBarTheme: NavigationBarThemeData(
        // Balanced height with comfortable breathing room
        height: 72,
        backgroundColor: Colors.transparent,
        // Tone down indicator to be subtler
        indicatorColor: scheme.primaryContainer.withValues(alpha: 0.14),
        // Use a smaller label and soften unselected color; selected label slightly bolder
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            fontSize: 12.5,
            color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          );
        }),
        // Consistent, slightly smaller icons and color resolve
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            size: 22,
          );
        }),
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thickness: WidgetStatePropertyAll(4),
        radius: Radius.circular(999),
        interactive: true,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        horizontalTitleGap: 12,
        minLeadingWidth: 40,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
        textStyle: WidgetStatePropertyAll(textTheme.bodyMedium),
        hintStyle: WidgetStatePropertyAll(
          textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
      searchViewTheme: SearchViewThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        dividerColor: scheme.outlineVariant.withValues(alpha: 0.35),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: scheme.outlineVariant.withValues(alpha: 0.2),
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 4,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        modalBackgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        elevation: 12,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: labelMedium,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
          textStyle: labelMedium,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: labelMedium),
      ),
      chipTheme: ChipThemeData(
        labelStyle: labelMedium?.copyWith(color: scheme.onSecondaryContainer),
        backgroundColor: scheme.secondaryContainer,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
    );
  }