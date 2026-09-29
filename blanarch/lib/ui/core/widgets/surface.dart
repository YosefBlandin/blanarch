import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Flat ivory card with a hairline border. It is a Material, so rows inside
/// show their tap ripple.
class Surface extends StatelessWidget {
  const Surface({super.key, required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: b.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: b.border),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
