import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../domain/models/profile.dart';
import '../../domain/models/setup_link.dart';
import '../core/l10n/l10n.dart';
import '../core/theme/theme.dart';

/// A QR code and link a colleague can use to add the same connection.
/// Passwords are never included; the username only if the user turns it on.
Future<void> showShareSetupSheet(BuildContext context, Profile profile) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _ShareSetupSheet(profile: profile),
);

class _ShareSetupSheet extends StatefulWidget {
  const _ShareSetupSheet({required this.profile});
  final Profile profile;

  @override
  State<_ShareSetupSheet> createState() => _ShareSetupSheetState();
}

class _ShareSetupSheetState extends State<_ShareSetupSheet> {
  bool _includeUsername = false;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final l10n = context.l10n;
    final link = SetupLink.fromProfile(widget.profile, includeUsername: _includeUsername).toUri();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.shareSetup,
            style: TextStyle(fontFamily: serif, fontSize: 32, color: b.ink),
          ),
          const SizedBox(height: 4),
          Text(l10n.shareSetupBody, style: TextStyle(fontSize: 14, height: 1.4, color: b.muted)),
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                // QR codes need dark-on-light to scan reliably, in both themes.
                color: Brand.light.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: b.border),
              ),
              child: QrImageView(
                data: link,
                size: 232,
                backgroundColor: Brand.light.surface,
                eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: Brand.light.ink),
                dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Brand.light.ink),
                semanticsLabel: l10n.shareSetup,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (widget.profile.username.isNotEmpty)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.includeUsername, style: TextStyle(color: b.ink)),
              value: _includeUsername,
              onChanged: (v) => setState(() => _includeUsername = v),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () {
              unawaited(Clipboard.setData(ClipboardData(text: link)));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.copied)));
            },
            icon: const Icon(Icons.link_rounded),
            label: Text(l10n.copyLink),
          ),
        ],
      ),
    );
  }
}
