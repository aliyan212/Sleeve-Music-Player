import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Represents an actionable item in an [AppActionSheet].
class AppActionItem {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isDestructive;
  final Widget? trailing;

  const AppActionItem({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.isDestructive = false,
    this.trailing,
  });
}

/// Represents a grouped section of items with an optional title.
class AppActionSection {
  final String? title;
  final List<AppActionItem> items;

  const AppActionSection({
    this.title,
    required this.items,
  });
}

/// Displays a standardized modal bottom sheet conforming to the app's design system.
Future<T?> showAppActionSheet<T>({
  required BuildContext context,
  required Widget headerThumbnail,
  required String headerTitle,
  required String headerSubtitle,
  List<AppActionSection>? sections,
  List<AppActionItem>? items,
  Widget? customContent,
}) {
  HapticFeedback.mediumImpact();
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final allSections = <AppActionSection>[];
  if (sections != null && sections.isNotEmpty) {
    allSections.addAll(sections);
  } else if (items != null && items.isNotEmpty) {
    allSections.add(AppActionSection(items: items));
  }

  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: false, // We render our standardized 32x4 pill handle
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top Pill Drag Handle ──
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant.withValues(alpha: isDark ? 0.45 : 0.65),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Standardized Header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: headerThumbnail,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headerTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(sheetContext)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            headerSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(sheetContext)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
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
                color: cs.outlineVariant.withValues(alpha: isDark ? 0.30 : 0.45),
              ),

              // ── Action Items / Sections ──
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(top: 4, bottom: 12),
                  children: [
                    ?customContent,
                    for (int sIdx = 0; sIdx < allSections.length; sIdx++) ...[
                      if (allSections[sIdx].title != null &&
                          allSections[sIdx].title!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                          child: Text(
                            allSections[sIdx].title!.toUpperCase(),
                            style: Theme.of(sheetContext)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  fontSize: 11,
                                ),
                          ),
                        ),
                      for (final action in allSections[sIdx].items)
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 0,
                          ),
                          leading: Icon(
                            action.icon,
                            size: 22,
                            color: action.isDestructive
                                ? cs.error
                                : cs.onSurfaceVariant,
                          ),
                          title: Text(
                            action.title,
                            style: TextStyle(
                              color: action.isDestructive
                                  ? cs.error
                                  : cs.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 14.5,
                            ),
                          ),
                          subtitle: action.subtitle != null
                              ? Text(
                                  action.subtitle!,
                                  style: TextStyle(
                                    color: action.isDestructive
                                        ? cs.error.withValues(alpha: 0.8)
                                        : cs.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                )
                              : null,
                          trailing: action.trailing,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            HapticFeedback.selectionClick();
                            action.onTap();
                          },
                        ),
                      if (sIdx < allSections.length - 1 &&
                          allSections[sIdx].title != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 4,
                          ),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: cs.outlineVariant.withValues(
                              alpha: isDark ? 0.20 : 0.35,
                            ),
                          ),
                        ),
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
