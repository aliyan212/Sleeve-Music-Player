import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:music_player/data/models/album_stat.dart';
import 'package:music_player/data/models/sort_mode.dart';

/// Represents a single selectable sort option in [AppSortBottomSheet].
class AppSortOption<T> {
  final T value;
  final String title;
  final String? subtitle;
  final IconData icon;
  final String? sectionTitle;

  const AppSortOption({
    required this.value,
    required this.title,
    this.subtitle,
    required this.icon,
    this.sectionTitle,
  });
}

/// Displays an integral, Material 3 bottom sheet for sorting.
Future<void> showAppSortBottomSheet<T>({
  required BuildContext context,
  required String title,
  required String subtitle,
  required T currentSort,
  required List<AppSortOption<T>> options,
  required ValueChanged<T> onSortSelected,
}) {
  HapticFeedback.mediumImpact();
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: false,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      // Group options by section if applicable
      final sections = <String?, List<AppSortOption<T>>>{};
      for (final opt in options) {
        sections.putIfAbsent(opt.sectionTitle, () => []).add(opt);
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Drag Handle ──
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant.withValues(alpha: isDark ? 0.45 : 0.65),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: isDark ? 0.4 : 0.7),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.swap_vert_rounded,
                        color: cs.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Divider(
                height: 1,
                thickness: 1,
                color: cs.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.40),
              ),

              // ── Sort Options List ──
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    for (final entry in sections.entries) ...[
                      if (entry.key != null && entry.key!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                          child: Text(
                            entry.key!.toUpperCase(),
                            style: Theme.of(sheetContext).textTheme.labelMedium?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  fontSize: 11,
                                ),
                          ),
                        ),
                      for (final option in entry.value) ...[
                        _buildSortTile(
                          context: sheetContext,
                          option: option,
                          isSelected: option.value == currentSort,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            HapticFeedback.selectionClick();
                            onSortSelected(option.value);
                          },
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _buildSortTile<T>({
  required BuildContext context,
  required AppSortOption<T> option,
  required bool isSelected,
  required VoidCallback onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2.0),
    child: Material(
      color: isSelected
          ? cs.primary.withValues(alpha: isDark ? 0.16 : 0.10)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected
                      ? cs.primary.withValues(alpha: isDark ? 0.25 : 0.15)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  option.icon,
                  size: 20,
                  color: isSelected ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      option.title,
                      style: TextStyle(
                        color: isSelected ? cs.primary : cs.onSurface,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    if (option.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        option.subtitle!,
                        style: TextStyle(
                          color: isSelected
                              ? cs.primary.withValues(alpha: 0.8)
                              : cs.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelected)
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: cs.onPrimary,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Convenience bottom sheet for Song library sorting.
Future<void> showSongSortBottomSheet(
  BuildContext context, {
  required SortMode currentSort,
  required ValueChanged<SortMode> onSortSelected,
}) {
  return showAppSortBottomSheet<SortMode>(
    context: context,
    title: 'Sort Library',
    subtitle: 'Order tracks in your library',
    currentSort: currentSort,
    onSortSelected: onSortSelected,
    options: const [
      AppSortOption(
        value: SortMode.artist,
        title: 'Track Artist',
        subtitle: 'Alphabetical by track artist',
        icon: Icons.person_rounded,
      ),
      AppSortOption(
        value: SortMode.albumArtist,
        title: 'Album Artist',
        subtitle: 'Alphabetical by album artist',
        icon: Icons.person_outline_rounded,
      ),
      AppSortOption(
        value: SortMode.year,
        title: 'Release Year',
        subtitle: 'Chronological order by year',
        icon: Icons.event_rounded,
      ),
      AppSortOption(
        value: SortMode.albumArtistYear,
        title: 'Album Artist & Year',
        subtitle: 'Grouped by album artist, then year',
        icon: Icons.calendar_view_month_rounded,
      ),
    ],
  );
}

/// Convenience bottom sheet for Albums sorting.
Future<void> showAlbumsSortBottomSheet(
  BuildContext context, {
  required AlbumsSort currentSort,
  required ValueChanged<AlbumsSort> onSortSelected,
}) {
  return showAppSortBottomSheet<AlbumsSort>(
    context: context,
    title: 'Sort Albums',
    subtitle: 'Order albums in your collection',
    currentSort: currentSort,
    onSortSelected: onSortSelected,
    options: const [
      AppSortOption(
        value: AlbumsSort.titleAsc,
        title: 'Title',
        subtitle: 'A → Z',
        icon: Icons.sort_by_alpha_rounded,
        sectionTitle: 'Title',
      ),
      AppSortOption(
        value: AlbumsSort.titleDesc,
        title: 'Title',
        subtitle: 'Z → A',
        icon: Icons.sort_by_alpha_rounded,
        sectionTitle: 'Title',
      ),
      AppSortOption(
        value: AlbumsSort.artistAsc,
        title: 'Artist',
        subtitle: 'A → Z',
        icon: Icons.person_rounded,
        sectionTitle: 'Artist',
      ),
      AppSortOption(
        value: AlbumsSort.artistDesc,
        title: 'Artist',
        subtitle: 'Z → A',
        icon: Icons.person_rounded,
        sectionTitle: 'Artist',
      ),
      AppSortOption(
        value: AlbumsSort.albumArtistYear,
        title: 'Album Artist / Year',
        subtitle: 'Grouped by artist, then release year',
        icon: Icons.calendar_view_month_rounded,
        sectionTitle: 'Artist',
      ),
      AppSortOption(
        value: AlbumsSort.yearDesc,
        title: 'Release Year',
        subtitle: 'Newest first',
        icon: Icons.event_rounded,
        sectionTitle: 'Release Year',
      ),
      AppSortOption(
        value: AlbumsSort.yearAsc,
        title: 'Release Year',
        subtitle: 'Oldest first',
        icon: Icons.history_rounded,
        sectionTitle: 'Release Year',
      ),
      AppSortOption(
        value: AlbumsSort.mostTracks,
        title: 'Track Count',
        subtitle: 'Most tracks first',
        icon: Icons.format_list_numbered_rounded,
        sectionTitle: 'Track Count',
      ),
      AppSortOption(
        value: AlbumsSort.leastTracks,
        title: 'Track Count',
        subtitle: 'Least tracks first',
        icon: Icons.format_list_numbered_rounded,
        sectionTitle: 'Track Count',
      ),
    ],
  );
}

/// Convenience bottom sheet for Album Artists sorting.
Future<void> showAlbumArtistsSortBottomSheet(
  BuildContext context, {
  required AlbumArtistsSort currentSort,
  required ValueChanged<AlbumArtistsSort> onSortSelected,
}) {
  return showAppSortBottomSheet<AlbumArtistsSort>(
    context: context,
    title: 'Sort Album Artists',
    subtitle: 'Order artists in your collection',
    currentSort: currentSort,
    onSortSelected: onSortSelected,
    options: const [
      AppSortOption(
        value: AlbumArtistsSort.nameAsc,
        title: 'Name',
        subtitle: 'A → Z',
        icon: Icons.sort_by_alpha_rounded,
        sectionTitle: 'Name',
      ),
      AppSortOption(
        value: AlbumArtistsSort.nameDesc,
        title: 'Name',
        subtitle: 'Z → A',
        icon: Icons.sort_by_alpha_rounded,
        sectionTitle: 'Name',
      ),
      AppSortOption(
        value: AlbumArtistsSort.mostAlbums,
        title: 'Album Count',
        subtitle: 'Most albums first',
        icon: Icons.album_rounded,
        sectionTitle: 'Discography',
      ),
      AppSortOption(
        value: AlbumArtistsSort.leastAlbums,
        title: 'Album Count',
        subtitle: 'Least albums first',
        icon: Icons.album_outlined,
        sectionTitle: 'Discography',
      ),
      AppSortOption(
        value: AlbumArtistsSort.mostTracks,
        title: 'Track Count',
        subtitle: 'Most tracks first',
        icon: Icons.music_note_rounded,
        sectionTitle: 'Discography',
      ),
      AppSortOption(
        value: AlbumArtistsSort.leastTracks,
        title: 'Track Count',
        subtitle: 'Least tracks first',
        icon: Icons.music_note_outlined,
        sectionTitle: 'Discography',
      ),
    ],
  );
}

