import 'package:flutter/material.dart';

/// Reusable polished empty-state component following the app's design language.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.padding = const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
  });

  /// Factory constructor to render as a Sliver suitable for CustomScrollView.
  static Widget sliver({
    Key? key,
    required IconData icon,
    required String title,
    String? message,
    String? actionLabel,
    IconData? actionIcon,
    VoidCallback? onAction,
    EdgeInsetsGeometry padding =
        const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
  }) {
    return SliverFillRemaining(
      key: key,
      hasScrollBody: false,
      child: AppEmptyState(
        icon: icon,
        title: title,
        message: message,
        actionLabel: actionLabel,
        actionIcon: actionIcon,
        onAction: onAction,
        padding: padding,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.surfaceContainerHighest.withValues(alpha: 0.8),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.25),
                ),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 38,
                  color: cs.primary.withValues(alpha: 0.85),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: cs.onSurface,
                  ),
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              FilledButton.tonalIcon(
                onPressed: onAction,
                icon: Icon(
                  actionIcon ?? Icons.arrow_forward_rounded,
                  size: 18,
                ),
                label: Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

