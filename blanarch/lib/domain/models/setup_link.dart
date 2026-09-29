import 'package:flutter/foundation.dart';

import 'profile.dart';

/// A shareable description of a connection, as a link or QR code:
/// `blanarch://add?host=vpn.example.com&port=10443&alt=vpn2.example.com&name=Corp&realm=staff&auth=sso&pin=<sha256>`.
/// `alt` lists backup addresses (same port), comma separated.
/// It never contains passwords; the username is only included when asked for.
@immutable
class SetupLink {
  const SetupLink({
    required this.host,
    this.port = 443,
    this.name = '',
    this.realm = '',
    this.authMode,
    this.username = '',
    this.pinSha256 = '',
    this.backups = const [],
  });

  static const scheme = 'blanarch';

  final String host;
  final int port;
  final String name;
  final String realm;

  /// Null when the link doesn't say; the server check decides then.
  final AuthMode? authMode;
  final String username;

  /// SHA-256 of the gateway certificate, 64 lowercase hex characters, or empty.
  final String pinSha256;

  /// Backup gateway addresses, tried after [host] on the same port.
  final List<String> backups;

  String get address => port == 443 ? host : '$host:$port';

  /// Main address first, then the backups.
  List<String> get hosts => [host, ...backups];

  String addressOf(String h) => port == 443 ? h : '$h:$port';

  static final _hex64 = RegExp(r'^[0-9a-f]{64}$');

  /// Parses a setup link; null if it isn't one (or is malformed).
  static SetupLink? parse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.scheme != scheme || uri.host != 'add') return null;
    final q = uri.queryParameters;
    final host = (q['host'] ?? '').trim().toLowerCase();
    final port = int.tryParse(q['port'] ?? '') ?? 443;
    if (host.isEmpty || host.contains(RegExp(r'[\s/]')) || port < 1 || port > 65535) return null;
    final pin = (q['pin'] ?? '').trim().toLowerCase().replaceAll(RegExp('[: ]'), '');
    final backups = (q['alt'] ?? '')
        .split(',')
        .map((h) => h.trim().toLowerCase())
        .where((h) => h.isNotEmpty && h != host && !h.contains(RegExp(r'[\s/]')))
        .toSet()
        .toList();
    return SetupLink(
      host: host,
      port: port,
      name: (q['name'] ?? '').trim(),
      realm: (q['realm'] ?? '').trim(),
      authMode: switch (q['auth']) {
        'sso' => AuthMode.sso,
        'password' => AuthMode.password,
        _ => null,
      },
      username: (q['user'] ?? '').trim(),
      pinSha256: _hex64.hasMatch(pin) ? pin : '',
      backups: backups,
    );
  }

  factory SetupLink.fromProfile(Profile p, {bool includeUsername = false}) => SetupLink(
    host: p.mainHost,
    port: p.port,
    name: p.name,
    realm: p.realm,
    authMode: p.authMode,
    username: includeUsername ? p.username : '',
    pinSha256: p.pinSha256 ?? '',
    backups: p.hosts.skip(1).toList(),
  );

  String toUri() => Uri(
    scheme: scheme,
    host: 'add',
    queryParameters: {
      'host': host,
      if (port != 443) 'port': '$port',
      if (backups.isNotEmpty) 'alt': backups.join(','),
      if (name.isNotEmpty) 'name': name,
      if (realm.isNotEmpty) 'realm': realm,
      if (authMode != null) 'auth': authMode == AuthMode.sso ? 'sso' : 'password',
      if (username.isNotEmpty) 'user': username,
      if (pinSha256.isNotEmpty) 'pin': pinSha256,
    },
  ).toString();
}
