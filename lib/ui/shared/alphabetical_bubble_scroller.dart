import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A fast-scroller with an interactive bubble indicator that dynamically adapts
/// to alphabetical, chronological (year), and numeric (track/album count) sorts.
///
/// Seamlessly works alongside Flutter's interactive [Scrollbar]. When dragging
/// the scrollbar or scrubbing along the right-edge rail, it reveals a floating
/// bubble indicating the current section, jumping directly to the corresponding
/// item with haptic feedback.
class AlphabeticalBubbleScroller extends StatefulWidget {
  final Widget child;
  final ScrollController scrollController;
  final int itemCount;
  final String Function(int index) sectionKeyOf;
  final double headerHeight;
  final double itemHeight;
  final bool isEnabled;
  final bool isNumericSort;
  final Object? sortKey;
  final double? topInset;
  final double? bottomInset;

  const AlphabeticalBubbleScroller({
    super.key,
    required this.child,
    required this.scrollController,
    required this.itemCount,
    required this.sectionKeyOf,
    this.headerHeight = 100.0,
    this.itemHeight = 84.0,
    this.isEnabled = true,
    this.isNumericSort = false,
    this.sortKey,
    this.topInset,
    this.bottomInset,
  });

  @override
  State<AlphabeticalBubbleScroller> createState() =>
      _AlphabeticalBubbleScrollerState();
}

class _AlphabeticalBubbleScrollerState extends State<AlphabeticalBubbleScroller>
    with SingleTickerProviderStateMixin {
  bool _isDraggingRail = false;
  double _touchY = 0.0;
  String _activeSection = '';
  Timer? _hideTimer;

  Map<String, int>? _cachedSectionMap;
  List<String>? _cachedAlphabet;

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant AlphabeticalBubbleScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount ||
        oldWidget.itemHeight != widget.itemHeight ||
        oldWidget.headerHeight != widget.headerHeight ||
        oldWidget.isNumericSort != widget.isNumericSort ||
        oldWidget.sortKey != widget.sortKey) {
      _cachedSectionMap = null;
      _cachedAlphabet = null;
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  String _normalizeSection(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '#';

    if (widget.isNumericSort) {
      if (trimmed == '#') return '#';
      final parsed = int.tryParse(trimmed);
      if (parsed != null) {
        if (parsed >= 0) return trimmed;
        return '#';
      }
      if (RegExp(r'^\d+[a-zA-Z]+$').hasMatch(trimmed)) {
        return trimmed;
      }
      return '#';
    }

    // Alphabetical / text sort
    final first = trimmed[0].toUpperCase();
    if (first.codeUnitAt(0) >= 65 && first.codeUnitAt(0) <= 90) {
      return first;
    }
    return '#';
  }

  Map<String, int> _getSectionMap() {
    if (_cachedSectionMap != null) return _cachedSectionMap!;
    final map = <String, int>{};
    for (int i = 0; i < widget.itemCount; i++) {
      final section = _normalizeSection(widget.sectionKeyOf(i));
      map.putIfAbsent(section, () => i);
    }
    _cachedSectionMap = map;
    _cachedAlphabet = map.keys.toList(growable: false);
    return map;
  }

  List<String> _getAlphabet() {
    _getSectionMap();
    return _cachedAlphabet ?? const ['#'];
  }

  void _onRailDragStart(
    DragStartDetails details,
    double effectiveTopInset,
    double railHeight,
  ) {
    _hideTimer?.cancel();
    _touchY = details.localPosition.dy;
    _isDraggingRail = true;
    _fadeController.forward();
    _updateSectionFromTouch(effectiveTopInset, railHeight);
  }

  void _onRailDragUpdate(
    DragUpdateDetails details,
    double effectiveTopInset,
    double railHeight,
  ) {
    _touchY = details.localPosition.dy;
    _updateSectionFromTouch(effectiveTopInset, railHeight);
  }

  void _onRailDragEnd() {
    _isDraggingRail = false;
    _scheduleHide();
  }

  void _onRailDragCancel() {
    _isDraggingRail = false;
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && !_isDraggingRail) {
        _fadeController.reverse();
      }
    });
  }

  void _updateSectionFromTouch(double effectiveTopInset, double railHeight) {
    if (widget.itemCount == 0 || railHeight <= 0) return;

    final alphabet = _getAlphabet();
    if (alphabet.isEmpty) return;

    final relativeY = (_touchY - effectiveTopInset).clamp(0.0, railHeight);
    final progress = (relativeY / railHeight).clamp(0.0, 1.0);

    final index = (progress * alphabet.length).floor().clamp(
      0,
      alphabet.length - 1,
    );
    final targetLetter = alphabet[index];

    if (targetLetter != _activeSection) {
      HapticFeedback.selectionClick();
      setState(() {
        _activeSection = targetLetter;
      });

      _jumpToSection(targetLetter);
    }
  }

  void _jumpToSection(String letter) {
    if (!widget.scrollController.hasClients || widget.itemCount == 0) return;

    final sectionMap = _getSectionMap();
    int? targetIndex = sectionMap[letter];

    // If letter has no direct items, find closest available letter
    if (targetIndex == null) {
      final availableKeys = sectionMap.keys.toList(growable: false);
      if (availableKeys.isEmpty) return;
      String closest = availableKeys.first;
      int minDistance = 99999;

      for (final key in availableKeys) {
        final dist = (key.compareTo(letter)).abs();
        if (dist < minDistance) {
          minDistance = dist;
          closest = key;
        }
      }
      targetIndex = sectionMap[closest];
    }

    if (targetIndex != null) {
      final position = widget.scrollController.position;
      // When jumping to index 0, scroll to 0.0 to fully expand the app bar.
      final targetOffset = targetIndex == 0
          ? 0.0
          : (widget.headerHeight + targetIndex * widget.itemHeight).clamp(
              0.0,
              position.maxScrollExtent,
            );

      widget.scrollController.jumpTo(targetOffset);
    }
  }

  void _updateActiveSectionFromOffset(double offset) {
    if (widget.itemCount == 0) return;
    final int index;
    if (offset <= 0 || offset < widget.headerHeight) {
      index = 0;
    } else {
      index = ((offset - widget.headerHeight) / widget.itemHeight).floor().clamp(
        0,
        widget.itemCount - 1,
      );
    }
    final rawKey = widget.sectionKeyOf(index);
    final section = _normalizeSection(rawKey);
    if (section != _activeSection) {
      setState(() {
        _activeSection = section;
      });
    }
  }

  String _formatRailLabel(String symbol) {
    if (symbol.length <= 2) return symbol;
    // For 4-digit years (e.g. 1984, 2024), display 2-digit abbreviation on rail ('84, '24)
    if (symbol.length == 4 && int.tryParse(symbol) != null) {
      return symbol.substring(2);
    }
    return symbol.substring(0, 2);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!widget.isEnabled || widget.itemCount < 10) {
      return widget.child;
    }

    final alphabet = _getAlphabet();
    if (alphabet.isEmpty) {
      return widget.child;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final topPadding = MediaQuery.paddingOf(context).top;
        final bottomPadding = MediaQuery.paddingOf(context).bottom;

        // Position rail safely below the top app bar actions/menu and above bottom nav/mini player
        final effectiveTopInset =
            widget.topInset ?? (topPadding + kToolbarHeight + 12.0);
        final effectiveBottomInset =
            widget.bottomInset ?? (bottomPadding + 96.0);
        final railHeight = (constraints.maxHeight -
                effectiveTopInset -
                effectiveBottomInset)
            .clamp(50.0, constraints.maxHeight);

        // Calculate thumb / bubble vertical position based on touch or active section
        final double bubbleY;
        if (_isDraggingRail) {
          bubbleY = _touchY.clamp(
            effectiveTopInset + 28.0,
            constraints.maxHeight - effectiveBottomInset - 28.0,
          );
        } else {
          final activeIndex = alphabet.indexOf(_activeSection);
          if (activeIndex >= 0 && alphabet.isNotEmpty) {
            bubbleY = effectiveTopInset +
                (activeIndex + 0.5) * (railHeight / alphabet.length);
          } else {
            final maxScroll = widget.scrollController.hasClients
                ? widget.scrollController.position.maxScrollExtent
                : 0.0;
            final currentOffset = widget.scrollController.hasClients
                ? widget.scrollController.offset
                : 0.0;
            final progress = maxScroll > 0
                ? (currentOffset / maxScroll).clamp(0.0, 1.0)
                : 0.0;
            bubbleY = effectiveTopInset + progress * railHeight;
          }
        }

        // Determine which sections get text labels vs dots when there are many sections (> 26)
        const maxDisplayItems = 26;
        final Set<int> displayIndices;
        if (alphabet.length <= maxDisplayItems) {
          displayIndices = {for (int i = 0; i < alphabet.length; i++) i};
        } else {
          final step = (alphabet.length - 1) / (maxDisplayItems - 1);
          final indices = <int>{};
          for (int i = 0; i < maxDisplayItems; i++) {
            indices.add((i * step).round().clamp(0, alphabet.length - 1));
          }
          displayIndices = indices;
        }

        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.axis == Axis.vertical) {
                  if (notification is ScrollStartNotification ||
                      notification is ScrollUpdateNotification) {
                    _updateActiveSectionFromOffset(notification.metrics.pixels);
                  }
                }
                return false;
              },
              child: widget.child,
            ),

            // Interactive Rail on the right edge (width 32px touch target)
            Positioned(
              right: 0,
              top: effectiveTopInset,
              bottom: effectiveBottomInset,
              child: SizedBox(
                width: 32,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragDown: (d) => _onRailDragStart(
                    DragStartDetails(
                      localPosition:
                          d.localPosition + Offset(0, effectiveTopInset),
                    ),
                    effectiveTopInset,
                    railHeight,
                  ),
                  onVerticalDragStart: (d) => _onRailDragStart(
                    DragStartDetails(
                      localPosition:
                          d.localPosition + Offset(0, effectiveTopInset),
                    ),
                    effectiveTopInset,
                    railHeight,
                  ),
                  onVerticalDragUpdate: (d) => _onRailDragUpdate(
                    DragUpdateDetails(
                      globalPosition: d.globalPosition,
                      localPosition:
                          d.localPosition + Offset(0, effectiveTopInset),
                    ),
                    effectiveTopInset,
                    railHeight,
                  ),
                  onVerticalDragEnd: (_) => _onRailDragEnd(),
                  onVerticalDragCancel: _onRailDragCancel,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Container(
                        width: 24,
                        margin: const EdgeInsets.only(right: 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surface.withValues(
                            alpha: isDark ? 0.85 : 0.92,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.35),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: List.generate(alphabet.length, (i) {
                            final symbol = alphabet[i];
                            final isSelected = symbol == _activeSection;
                            final isLandmark = displayIndices.contains(i);
                            final label = isLandmark
                                ? _formatRailLabel(symbol)
                                : '•';

                            return Expanded(
                              child: Center(
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: !isLandmark
                                        ? 6.0
                                        : alphabet.length > 20
                                            ? 8.0
                                            : 9.0,
                                    fontWeight: isSelected
                                        ? FontWeight.w900
                                        : FontWeight.w600,
                                    color: isSelected
                                        ? cs.primary
                                        : cs.onSurfaceVariant.withValues(
                                            alpha: isLandmark ? 0.75 : 0.40,
                                          ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Floating Section Bubble Indicator - ONLY when dragging rail
            if (_isDraggingRail && _activeSection.isNotEmpty)
              Positioned(
                right: 40,
                top: (bubbleY - 28).clamp(
                  effectiveTopInset,
                  constraints.maxHeight - effectiveBottomInset - 56.0,
                ),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: IgnorePointer(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.40),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.20),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _activeSection,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: _activeSection.length > 3
                                ? 16
                                : _activeSection.length > 2
                                    ? 20
                                    : 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing:
                                _activeSection.length > 2 ? -0.5 : 0.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
