import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/theme.dart';

/// Thin segments showing progress: [step] of [total] filled.
/// Screen readers hear "Step x of y".
class StepBar extends StatelessWidget {
  const StepBar({super.key, required this.step, required this.color, this.total = 4});
  final int step;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Semantics(
      label: context.l10n.stepOf(step, total),
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 1; i <= total; i++) ...[
              if (i > 1) const SizedBox(width: 6),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 3,
                  decoration: BoxDecoration(
                    color: i <= step ? color : b.border,
                    borderRadius: BorderRadius.circular(2),
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
