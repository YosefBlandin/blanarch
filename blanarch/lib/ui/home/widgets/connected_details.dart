import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/profile.dart';
import '../../../domain/models/vpn_status.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/theme.dart';

/// One line of connection details: a label, a value, and whether it is worth copying.
typedef DetailRow = ({String label, String value, bool copy});

/// Turns the engine's status into the facts IT asks about. Pure, so the card,
/// the sheet and "Copy all" say exactly the same thing.
class ConnectionFacts {
  ConnectionFacts(this.l10n, this.status, this.profile, this.now);
  final AppLocalizations l10n;
  final VpnStatus status;
  final Profile? profile;
  final DateTime now;

  String get tunnelIp => status.ip ?? l10n.notReported;

  String get _address {
    final host = status.host ?? profile?.mainHost ?? '';
    final port = status.port ?? profile?.port;
    return port == null ? host : '$host:$port';
  }

  bool get _onBackup {
    final hosts = profile?.hosts ?? const <String>[];
    return hosts.isNotEmpty && status.host != null && status.host != hosts.first;
  }

  /// Full wording, for the details sheet.
  String get gateway => _onBackup ? '$_address (${l10n.backupAddress})' : _address;

  /// Fits on one line of the card.
  String get gatewayShort => _onBackup ? '$_address · ${l10n.backupShort}' : _address;

  String get routing => status.routes.isEmpty ? l10n.routingAll : l10n.routingSplit(status.routes.length);

  String get dns => [
    if (status.dns.isNotEmpty) status.dns.join(', '),
    if (status.dnsSuffix != null && status.dnsSuffix!.isNotEmpty) status.dnsSuffix!,
  ].join(' · ').ifEmpty(l10n.notReported);

  String get traffic => '↓ ${bytes(status.bytesIn)}   ↑ ${bytes(status.bytesOut)}';

  String get latency => status.latency == null ? l10n.measuring : l10n.millis(status.latency!.inMilliseconds);

  String get signInMethod => switch (status.signIn) {
    SignInMethod.code => '${l10n.signInPassword} + ${l10n.signInCode}',
    SignInMethod.push => '${l10n.signInPassword} + ${l10n.signInPush}',
    SignInMethod.sso => l10n.signInSso,
    SignInMethod.password || null => l10n.signInPassword,
  };

  String get signedIn {
    final user = profile?.username ?? '';
    return user.isEmpty ? signInMethod : '$user · $signInMethod';
  }

  String get uptime {
    final since = status.connectedSince;
    if (since == null) return '';
    final d = now.difference(since);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  /// Certificate line under the card: pinned by the user, or trusted by the system.
  String get certificateNote => status.certSha256 != null ? l10n.certPinnedMatches : l10n.certSystemTrusted;

  /// The six facts on the connected screen.
  List<DetailRow> get summary => [
    (label: l10n.factTunnelIp, value: tunnelIp, copy: true),
    (label: l10n.factGateway, value: gatewayShort, copy: true),
    (label: l10n.factRouting, value: routing, copy: false),
    (label: l10n.factDns, value: dns, copy: true),
    (label: l10n.factTraffic, value: traffic, copy: false),
    (label: l10n.factSignedIn, value: signedIn, copy: false),
  ];

  /// Everything, grouped, for the details sheet and for sharing.
  List<(String, List<DetailRow>)> get sections {
    final pin = status.certSha256;
    final since = status.connectedSince;
    return [
      (
        l10n.sectionNetwork,
        [
          (label: l10n.factTunnelIp, value: tunnelIp, copy: true),
          (label: l10n.dnsServers, value: status.dns.join(', ').ifEmpty(l10n.notReported), copy: true),
          if (status.dnsSuffix != null && status.dnsSuffix!.isNotEmpty)
            (label: l10n.searchDomain, value: status.dnsSuffix!, copy: true),
          (
            label: l10n.routesLabel,
            value: status.routes.isEmpty ? l10n.routingAll : status.routes.join(', '),
            copy: status.routes.isNotEmpty,
          ),
          if (status.mtu != null) (label: l10n.mtuLabel, value: '${status.mtu}', copy: false),
        ],
      ),
      (
        l10n.sectionServer,
        [
          (label: l10n.factGateway, value: gateway, copy: true),
          (
            label: l10n.certificateLabel,
            value: pin == null ? l10n.certSystemTrusted : '${_groups(pin)} · ${l10n.pinned}',
            copy: pin != null,
          ),
          (label: l10n.encryptionLabel, value: status.tls ?? l10n.notReported, copy: false),
          (label: l10n.latencyLabel, value: latency, copy: false),
        ],
      ),
      (
        l10n.sectionSession,
        [
          if ((profile?.username ?? '').isNotEmpty) (label: l10n.userLabel, value: profile!.username, copy: true),
          (label: l10n.signInLabel, value: signInMethod, copy: false),
          if (since != null) (label: l10n.connectedSinceLabel, value: '${_time(since)} · $uptime', copy: false),
          (label: l10n.reconnectsLabel, value: '${status.reconnects}', copy: false),
          if (status.triedHosts.isNotEmpty)
            (label: l10n.addressesTried, value: status.triedHosts.join(' → '), copy: false),
          (label: l10n.factTraffic, value: traffic, copy: false),
        ],
      ),
    ];
  }

  /// Plain text of every section, for Copy all and Share.
  String get asText {
    final pin = status.certSha256;
    return [
      for (final (title, rows) in sections) ...[
        title.toUpperCase(),
        for (final r in rows)
          // The fingerprint goes out whole; on screen it is shortened.
          '${r.label}: ${r.label == l10n.certificateLabel && pin != null ? '$pin (${l10n.pinned})' : r.value}',
        '',
      ],
    ].join('\n').trim();
  }

  static String bytes(int n) {
    if (n < 1024) return '$n B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var v = n / 1024;
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${units[i]}';
  }

  /// 64 hex characters in groups of four; shortened on screen, whole when copied.
  static String _groups(String hex) {
    final groups = [for (var i = 0; i < hex.length; i += 4) hex.substring(i, (i + 4).clamp(0, hex.length))];
    return groups.length <= 8
        ? groups.join(' ')
        : '${groups.take(4).join(' ')} … ${groups.skip(groups.length - 2).join(' ')}';
  }

  static String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

/// The six facts, always in view while connected.
class ConnectedFactsCard extends StatelessWidget {
  const ConnectedFactsCard({super.key, required this.facts});
  final ConnectionFacts facts;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final rows = facts.summary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      decoration: BoxDecoration(color: b.surface, borderRadius: BorderRadius.circular(22)),
      child: Column(
        children: [
          for (final (i, r) in rows.indexed)
            Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: i < rows.length - 1 ? Border(bottom: BorderSide(color: b.surfaceAlt)) : null,
              ),
              child: MergeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.label, style: TextStyle(fontSize: 14, color: b.muted)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        r.value,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: b.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Everything about the connection, each value copyable, with Copy all and Share.
Future<void> showConnectionDetails(
  BuildContext context, {
  required ConnectionFacts Function() facts,
  required Future<void> Function(String subject, String text) share,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _DetailsSheet(facts: facts, share: share),
);

class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet({required this.facts, required this.share});
  final ConnectionFacts Function() facts;
  final Future<void> Function(String subject, String text) share;

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Traffic, latency and uptime keep moving while the sheet is open.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _copy(String text) {
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.copied)));
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final l10n = context.l10n;
    final facts = widget.facts();
    final pin = facts.status.certSha256;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              children: [
                Text(
                  l10n.detailsTitle,
                  style: TextStyle(fontFamily: serif, fontSize: 30, color: b.ink),
                ),
                for (final (title, rows) in facts.sections) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 18, 0, 6),
                    child: Semantics(
                      header: true,
                      child: Text(
                        title.toUpperCase(),
                        style: TextStyle(fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w600, color: b.muted),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
                    decoration: BoxDecoration(color: b.surface, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        for (final (i, r) in rows.indexed)
                          Container(
                            constraints: const BoxConstraints(minHeight: 52),
                            decoration: BoxDecoration(
                              border: i < rows.length - 1 ? Border(bottom: BorderSide(color: b.surfaceAlt)) : null,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: MergeSemantics(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(r.label, style: TextStyle(fontSize: 12.5, color: b.muted)),
                                          const SizedBox(height: 1),
                                          SelectableText(
                                            r.value,
                                            style: TextStyle(
                                              fontSize: 14,
                                              height: 1.4,
                                              fontWeight: FontWeight.w500,
                                              color: b.ink,
                                              fontFeatures: const [FontFeature.tabularFigures()],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                if (r.copy)
                                  IconButton(
                                    tooltip: l10n.copyValue(r.label),
                                    // The fingerprint is copied whole, not as shortened on screen.
                                    onPressed: () =>
                                        _copy(r.label == l10n.certificateLabel && pin != null ? pin : r.value),
                                    icon: Icon(Icons.copy_rounded, size: 18, color: b.outline),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + MediaQuery.paddingOf(context).bottom),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      side: BorderSide(color: b.outline),
                      foregroundColor: b.ink,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => _copy(facts.asText),
                    child: Text(l10n.copyAll),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => unawaited(widget.share(l10n.detailsShareSubject, facts.asText)),
                    child: Text(l10n.shareWithIt),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
