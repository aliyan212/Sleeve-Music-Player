import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';
import '../main.dart';
import '../services/settings_service.dart';
import '../dialogs/customize_tabs_dialog.dart';

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget buildSectionHeader(String title, IconData icon) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(width: 12),
            Text(
              title.toUpperCase(),
              style: textTheme.labelLarge?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      );
    }

    Widget buildThemeCard({
      required String title,
      required String subtitle,
      required IconData icon,
      required AppThemeMode mode,
      required bool isSelected,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Material(
          color: isSelected
              ? cs.primaryContainer.withValues(alpha: 0.22)
              : cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: isSelected
                  ? cs.primary
                  : cs.outlineVariant.withValues(alpha: 0.35),
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? cs.primary
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget buildSubOptionCard({
      required String title,
      required String subtitle,
      required bool isSelected,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Material(
          color: isSelected
              ? cs.primaryContainer.withValues(alpha: 0.18)
              : cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isSelected
                  ? cs.primary
                  : cs.outlineVariant.withValues(alpha: 0.3),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_off_rounded,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.4),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Appearance', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([themeNotifier, SettingsService.instance]),
        builder: (context, _) {
          final currentMode = themeNotifier.appThemeMode;
          final currentOledStyle = themeNotifier.oledStyle;
          final currentBgStyle = SettingsService.instance.nowPlayingBgStyle;

          return ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              buildSectionHeader('Theme Mode', Icons.palette_rounded),
              buildThemeCard(
                title: 'System Default',
                subtitle: 'Automatically follow device system brightness',
                icon: Icons.brightness_auto_rounded,
                mode: AppThemeMode.system,
                isSelected: currentMode == AppThemeMode.system,
                onTap: () => themeNotifier.setAppThemeMode(AppThemeMode.system),
              ),
              buildThemeCard(
                title: 'Light Theme',
                subtitle: 'Crisp, high-clarity Material 3 light theme',
                icon: Icons.light_mode_rounded,
                mode: AppThemeMode.light,
                isSelected: currentMode == AppThemeMode.light,
                onTap: () => themeNotifier.setAppThemeMode(AppThemeMode.light),
              ),
              buildThemeCard(
                title: 'Dark (Material)',
                subtitle: 'Dynamic tonal dark theme with extracted accent surfaces',
                icon: Icons.dark_mode_rounded,
                mode: AppThemeMode.dark,
                isSelected: currentMode == AppThemeMode.dark,
                onTap: () => themeNotifier.setAppThemeMode(AppThemeMode.dark),
              ),
              buildThemeCard(
                title: 'Dark (OLED Pure Black)',
                subtitle: 'Pure #000000 black background optimized for OLED/AMOLED screens',
                icon: Icons.contrast_rounded,
                mode: AppThemeMode.darkOled,
                isSelected: currentMode == AppThemeMode.darkOled,
                onTap: () => themeNotifier.setAppThemeMode(AppThemeMode.darkOled),
              ),

              if (themeNotifier.isOled) ...[
                buildSectionHeader('OLED Surface Style', Icons.layers_rounded),
                buildSubOptionCard(
                  title: 'Hybrid OLED (Recommended)',
                  subtitle: 'Pitch-black main background with subtle elevated container cards for clear visual hierarchy',
                  isSelected: currentOledStyle == OledStyle.hybrid,
                  onTap: () => themeNotifier.setOledStyle(OledStyle.hybrid),
                ),
                buildSubOptionCard(
                  title: 'Total Black OLED',
                  subtitle: 'Pure black on every card, dialog, and container with crisp subtle outline borders',
                  isSelected: currentOledStyle == OledStyle.total,
                  onTap: () => themeNotifier.setOledStyle(OledStyle.total),
                ),
              ],

              buildSectionHeader('Now Playing Background', Icons.wallpaper_rounded),
              buildSubOptionCard(
                title: 'Material Mesh Gradient (Default)',
                subtitle: 'Fluid multi-point ambient gradient animated with extracted artwork colors',
                isSelected: currentBgStyle != 'frostedGlass',
                onTap: () => SettingsService.instance.setNowPlayingBgStyle('mesh'),
              ),
              buildSubOptionCard(
                title: 'Frosted Glass Artwork',
                subtitle: 'Full-bleed album cover heavily blurred with a translucent glass scrim',
                isSelected: currentBgStyle == 'frostedGlass',
                onTap: () => SettingsService.instance.setNowPlayingBgStyle('frostedGlass'),
              ),

              buildSectionHeader('Display & Navigation', Icons.dock_rounded),
              SwitchListTile.adaptive(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                title: const Text('Keep Screen Awake', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'Prevent screen from turning off while using the app',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
                secondary: Icon(Icons.lightbulb_rounded, color: cs.onSurfaceVariant),
                value: SettingsService.instance.keepScreenAwake,
                onChanged: (val) {
                  HapticFeedback.selectionClick();
                  SettingsService.instance.setKeepScreenAwake(val);
                },
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                leading: Icon(Icons.dock_rounded, color: cs.onSurfaceVariant),
                title: const Text('Bottom Navigation Bar', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'Customize which tabs appear in the dock',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  HapticFeedback.selectionClick();
                  showCustomizeTabsDialog(context);
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
