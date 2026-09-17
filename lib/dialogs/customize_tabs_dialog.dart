import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/models/app_tab.dart';
import '../services/app_state_controller.dart';

Future<void> showCustomizeTabsDialog(BuildContext context) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => const _CustomizeTabsSheet(),
  );
}

class _CustomizeTabsSheet extends StatefulWidget {
  const _CustomizeTabsSheet();

  @override
  State<_CustomizeTabsSheet> createState() => _CustomizeTabsSheetState();
}

class _CustomizeTabsSheetState extends State<_CustomizeTabsSheet> {
  late List<AppTab> _currentTabs;

  @override
  void initState() {
    super.initState();
    _currentTabs = List.of(AppStateController.instance.activeTabs);
  }

  void _toggleTab(AppTab tab) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_currentTabs.contains(tab)) {
        if (_currentTabs.length > 3) {
          _currentTabs.remove(tab);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('At least 3 tabs must be selected.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (_currentTabs.length < 5) {
          _currentTabs.add(tab);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Maximum 5 tabs can be displayed in the dock.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  void _resetToDefault() {
    HapticFeedback.mediumImpact();
    setState(() {
      _currentTabs = List.of(AppTab.defaultTabs);
    });
  }

  void _save() {
    HapticFeedback.mediumImpact();
    AppStateController.instance.updateActiveTabs(_currentTabs);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Customize Bottom Bar',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choose 3 to 5 tabs. Reorder active tabs below.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _resetToDefault,
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Active tabs count indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tab_rounded,
                    size: 18,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Active Tabs: ${_currentTabs.length} / 5',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _currentTabs.length < 3
                        ? 'Select at least 3'
                        : (_currentTabs.length == 5 ? 'Maximum reached' : 'Allowed: 3 to 5'),
                    style: TextStyle(
                      fontSize: 12,
                      color: _currentTabs.length < 3 ? cs.error : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Reorderable active tabs
            Text(
              'Active Tabs (Drag to reorder):',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorder: (oldIndex, newIndex) {
                HapticFeedback.selectionClick();
                setState(() {
                  if (oldIndex < newIndex) {
                    newIndex -= 1;
                  }
                  final item = _currentTabs.removeAt(oldIndex);
                  _currentTabs.insert(newIndex, item);
                });
              },
              children: [
                for (int i = 0; i < _currentTabs.length; i++)
                  ListTile(
                    key: ValueKey('active_tab_${_currentTabs[i].name}'),
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(_currentTabs[i].icon, color: cs.primary),
                    title: Text(
                      _currentTabs[i].label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                          color: _currentTabs.length > 3 ? cs.error : cs.outline,
                          tooltip: 'Remove',
                          onPressed: _currentTabs.length > 3
                              ? () => _toggleTab(_currentTabs[i])
                              : null,
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: Icon(
                            Icons.drag_handle_rounded,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),

            // Available other tabs
            Text(
              'Available Tabs:',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppTab.values.map((tab) {
                final isSelected = _currentTabs.contains(tab);
                return FilterChip(
                  label: Text(tab.label),
                  avatar: Icon(isSelected ? tab.selectedIcon : tab.icon, size: 18),
                  selected: isSelected,
                  onSelected: (_) => _toggleTab(tab),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),
            FilledButton(
              onPressed: _currentTabs.length >= 3 && _currentTabs.length <= 5
                  ? _save
                  : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Apply',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
