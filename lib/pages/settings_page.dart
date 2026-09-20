import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../services/app_state_controller.dart';
import '../services/settings_service.dart';
import '../dialogs/customize_tabs_dialog.dart';
import '../widgets/search/app_search_view.dart';
import '../services/sleep_timer_service.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget buildSectionTitle(String title, IconData icon) {
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

    Widget buildListTile({
      required String title,
      required String subtitle,
      required IconData icon,
      required VoidCallback onTap,
      Widget? trailing,
    }) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        leading: Icon(icon, color: cs.onSurfaceVariant),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        trailing: trailing,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          buildSectionTitle('Appearance & Navigation', Icons.palette_rounded),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, themeMode, _) {
              return buildListTile(
                title: 'App Theme',
                subtitle: themeNotifier.themeMenuLabel,
                icon: Icons.brightness_6_rounded,
                onTap: () => themeNotifier.toggle(),
              );
            },
          ),
          ListenableBuilder(
            listenable: SettingsService.instance,
            builder: (context, _) {
              return SwitchListTile.adaptive(
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
              );
            },
          ),
          buildListTile(
            title: 'Bottom Navigation Bar',
            subtitle: 'Customize which tabs appear in the dock',
            icon: Icons.dock_rounded,
            onTap: () => showCustomizeTabsDialog(context),
          ),

          buildSectionTitle('Library & Storage', Icons.folder_rounded),
          ListenableBuilder(
            listenable: SettingsService.instance,
            builder: (context, _) {
              return SwitchListTile.adaptive(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                title: const Text('Filter Short Tracks', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'Hide audio files shorter than 60 seconds (requires rescan)',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
                secondary: Icon(Icons.timer_off_rounded, color: cs.onSurfaceVariant),
                value: SettingsService.instance.filterShortTracks,
                onChanged: (val) {
                  HapticFeedback.selectionClick();
                  SettingsService.instance.setFilterShortTracks(val);
                },
              );
            },
          ),
          buildListTile(
            title: 'Manage Audio Folders',
            subtitle: 'Select which folders are scanned for music',
            icon: Icons.folder_copy_rounded,
            onTap: () => AppStateController.instance.openManageFoldersDialog(context),
          ),
          buildListTile(
            title: 'Rescan Library',
            subtitle: 'Manually refresh tags, covers, and track files',
            icon: Icons.refresh_rounded,
            onTap: () {
              AppStateController.instance.ensureLibraryPermissionAndLoad();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Library scan initiated.')),
              );
            },
          ),

          buildSectionTitle('Search & Discovery', Icons.search_rounded),
          buildListTile(
            title: 'Search Categories',
            subtitle: 'Choose which categories appear in search results',
            icon: Icons.tune_rounded,
            onTap: () {
              SearchCategoryManager.showSettingsSheet(context);
            },
          ),
          buildListTile(
            title: 'Clear Search History',
            subtitle: 'Remove all recent search queries',
            icon: Icons.history_rounded,
            onTap: () async {
              await SearchHistoryManager.clearHistory();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Search history cleared.')),
                );
              }
            },
          ),

          buildSectionTitle('Playback', Icons.play_circle_rounded),
          buildListTile(
            title: 'Sleep Timer',
            subtitle: 'Automatically pause playback after a set time',
            icon: Icons.bedtime_rounded,
            onTap: () => SleepTimerService.instance.showSleepTimerDialog(context),
          ),

          buildSectionTitle('About', Icons.info_rounded),
          buildListTile(
            title: 'About Sleeve Music',
            subtitle: 'Version information and licenses',
            icon: Icons.info_outline_rounded,
            onTap: () => AppStateController.instance.openAboutPage(context),
          ),
        ],
      ),
    );
  }
}
