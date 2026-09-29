import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';

/// A pill with one choice selected. Grows with the text size; labels that
/// wrap stay centered inside their segment.
class Segmented<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T>? onChanged;

  /// Minimum height; the pill grows when labels wrap or the text is larger.
  final double height;

  /// Called when a segment is tapped while disabled, to say why.
  final VoidCallback? onDisabledTap;

  /// Read by screen readers while disabled.
  final String? disabledHint;

  const Segmented({
    super.key,
    required this.items,
    required this.value,
    this.onChanged,
    this.height = 56,
    this.onDisabledTap,
    this.disabledHint,
  });

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final idx = math.max(0, items.indexWhere((e) => e.$1 == value));
    final enabled = onChanged != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.5,
      // No LayoutBuilder: setup pages measure their content (intrinsic height),
      // which LayoutBuilder can't answer.
      child: Container(
        constraints: BoxConstraints(minHeight: height),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: b.surfaceAlt, borderRadius: BorderRadius.circular(height / 2)),
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment(items.length == 1 ? 0 : -1 + 2 * idx / (items.length - 1), 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / items.length,
                  heightFactor: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: b.surface,
                      borderRadius: BorderRadius.circular(height / 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (v, label) in items)
                    Expanded(
                      child: Semantics(
                        button: true,
                        enabled: enabled,
                        selected: v == value,
                        inMutuallyExclusiveGroup: true,
                        hint: enabled ? null : disabledHint,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: !enabled
                              ? onDisabledTap
                              : v != value
                              ? () {
                                  unawaited(HapticFeedback.selectionClick());
                                  onChanged!(v);
                                }
                              : null,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: height - 8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 15,
                                    height: 1.25,
                                    fontWeight: v == value ? FontWeight.w600 : FontWeight.w500,
                                    color: v == value ? b.ink : b.muted,
                                  ),
                                  child: Text(label),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
