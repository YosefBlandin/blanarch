import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../theme/theme.dart';
import 'surface.dart';

/// A certificate fingerprint in groups of four, kept left to right in every
/// language, with a copy button so it can be compared with what IT sent.
class FingerprintCard extends StatelessWidget {
  const FingerprintCard({super.key, required this.groups, this.warning = false});
  final String groups;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final l10n = context.l10n;
    return Surface(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                warning ? Icons.gpp_bad_rounded : Icons.fingerprint_rounded,
                size: 20,
                color: warning ? b.bad : b.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.certFingerprint,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: b.muted),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  unawaited(Clipboard.setData(ClipboardData(text: groups.replaceAll(' ', ''))));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.copied)));
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: Text(l10n.copy),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(
              // Commas make TalkBack pause between groups instead of reading 64 characters in one go.
              semanticsLabel: groups.split(' ').join(', '),
              groups,
              style: TextStyle(
                fontSize: 15.5,
                height: 1.7,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: b.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The fingerprint behind a "Show fingerprint" button, for people who want to
/// compare it. Most never get one from IT, so it stays out of the way.
class FingerprintReveal extends StatefulWidget {
  const FingerprintReveal({super.key, required this.groups});
  final String groups;

  @override
  State<FingerprintReveal> createState() => _FingerprintRevealState();
}

class _FingerprintRevealState extends State<FingerprintReveal> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _open = !_open),
          icon: Icon(_open ? Icons.expand_less_rounded : Icons.fingerprint_rounded),
          label: Text(_open ? l10n.hideFingerprint : l10n.showFingerprint),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open ? FingerprintCard(groups: widget.groups) : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
