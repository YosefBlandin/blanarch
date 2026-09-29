import 'package:flutter/material.dart';

import '../theme/theme.dart';

class Wordmark extends StatelessWidget {
  final double size;
  const Wordmark({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Semantics(
      label: 'Blanarch',
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Blan'),
              TextSpan(
                text: 'arch',
                style: TextStyle(fontStyle: FontStyle.italic, color: b.accent),
              ),
            ],
          ),
          style: TextStyle(fontFamily: serif, fontSize: size, color: b.ink, height: 1.1),
        ),
      ),
    );
  }
}
