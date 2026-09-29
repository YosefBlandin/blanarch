import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/profile.dart';
import '../../../domain/models/vpn_status.dart';
import '../../../utils/result.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/vpn_texts.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/fingerprint.dart';
import '../../core/widgets/surface.dart';
import '../home_view_model.dart';

/// Explains a failure: what happened, what to do, and the technical detail
/// folded away. Certificate problems get a trust choice; a rejected password
/// gets "Update password" first, because retrying the old one can lock the account.
Future<void> showErrorSheet(
  BuildContext context, {
  required HomeViewModel vm,
  required VoidCallback onEdit,
  required VoidCallback onUpdatePassword,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _ErrorSheet(vm: vm, onEdit: onEdit, onUpdatePassword: onUpdatePassword),
);

class _ErrorSheet extends StatefulWidget {
  const _ErrorSheet({required this.vm, required this.onEdit, required this.onUpdatePassword});
  final HomeViewModel vm;
  final VoidCallback onEdit;
  final VoidCallback onUpdatePassword;

  @override
  State<_ErrorSheet> createState() => _ErrorSheetState();
}

class _ErrorSheetState extends State<_ErrorSheet> {
  bool _showDetail = false;
  ProbeResult? _probe;

  HomeViewModel get vm => widget.vm;
  VpnErrorCode? get code => vm.status.error;
  bool get certProblem => code == VpnErrorCode.certUntrusted || code == VpnErrorCode.certMismatch;
  bool get passwordProblem => code == VpnErrorCode.authRejected || code == VpnErrorCode.noVpnPassword;

  @override
  void initState() {
    super.initState();
    if (certProblem) unawaited(_loadCertificate());
  }

  Future<void> _loadCertificate() async {
    await vm.probeSelected.execute();
    if (!mounted) return;
    if (vm.probeSelected.result case Ok(:final value)) setState(() => _probe = value);
  }

  Future<void> _trustAndRetry() async {
    final probe = _probe;
    if (probe == null) return;
    await vm.trust.execute(probe);
    if (!mounted) return;
    Navigator.pop(context);
    unawaited(vm.toggle.execute());
  }

  void _closeThen(VoidCallback action) {
    Navigator.pop(context);
    action();
  }

  void _retry() => _closeThen(() => unawaited(vm.toggle.execute()));

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final l10n = context.l10n;
    final c = code;
    if (c == null) return const SizedBox(height: 120);
    final detail = vm.status.errorDetail;
    final changed = c == VpnErrorCode.certMismatch;
    final trustReady = _probe?.ok ?? false;
    final (String primary, VoidCallback? onPrimary, String secondary, VoidCallback? onSecondary) = switch (c) {
      _ when changed => (
        l10n.certDontConnect,
        () => Navigator.pop(context),
        l10n.certTrust,
        trustReady ? () => unawaited(_trustAndRetry()) : null,
      ),
      _ when certProblem => (
        l10n.certTrustContinue,
        trustReady ? () => unawaited(_trustAndRetry()) : null,
        l10n.certDontConnect,
        () => Navigator.pop(context),
      ),
      _ when passwordProblem => (l10n.updatePassword, () => _closeThen(widget.onUpdatePassword), l10n.tryAgain, _retry),
      _ => (l10n.tryAgain, _retry, l10n.editConnection, () => _closeThen(widget.onEdit)),
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            changed ? l10n.certChangedTitle : l10n.error(c, attempts: vm.status.maxAttempts),
            style: TextStyle(fontFamily: serif, fontSize: 28, height: 1.15, color: changed ? b.bad : b.ink),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.whatYouCanDo,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: b.muted),
          ),
          const SizedBox(height: 4),
          Text(
            changed && _probe != null ? l10n.certChangedBody(_probe!.host) : l10n.fixFor(c),
            style: TextStyle(fontSize: 15, height: 1.5, color: b.ink),
          ),
          if (certProblem) ...[
            const SizedBox(height: 12),
            if (!trustReady)
              const Center(
                child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
              )
            else if (changed)
              FingerprintCard(groups: _probe!.fingerprintGroups, warning: true)
            else
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FingerprintReveal(groups: _probe!.fingerprintGroups),
              ),
          ],
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setState(() => _showDetail = !_showDetail),
                icon: Icon(_showDetail ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                label: Text(l10n.technicalDetails),
              ),
            ),
            if (_showDetail)
              Surface(
                padding: const EdgeInsets.fromLTRB(14, 6, 4, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: SelectableText(
                            '${c.name}: $detail',
                            style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4, color: b.muted),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.copy,
                      onPressed: () {
                        unawaited(Clipboard.setData(ClipboardData(text: '${c.name}: $detail')));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.copied)));
                      },
                      icon: Icon(Icons.copy_rounded, size: 18, color: b.muted),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: onPrimary, child: Text(primary)),
          const SizedBox(height: 6),
          Center(
            child: TextButton(onPressed: onSecondary, child: Text(secondary)),
          ),
        ],
      ),
    );
  }
}
