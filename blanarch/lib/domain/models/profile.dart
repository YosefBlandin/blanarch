import 'package:flutter/foundation.dart';

import 'vpn_status.dart';

enum AuthMode { password, sso }

enum SecondFactorPreference {
  /// Push approval when the gateway offers it, otherwise a code.
  auto,

  /// Always a typed or emailed code.
  code,
}

/// Where emailed codes are read from. The password is stored by the engine, never here.
@immutable
class EmailOtpSource {
  const EmailOtpSource({
    required this.account,
    required this.imapHost,
    this.imapPort = 993,
    this.mailbox = 'INBOX',
    this.from = '',
  });
  final String account;
  final String imapHost;
  final int imapPort;
  final String mailbox;
  final String from;

  /// A sensible IMAP server for common providers, else `mail.<domain>`.
  static String guessImapHost(String email) {
    final domain = email.split('@').last.trim().toLowerCase();
    if (domain.isEmpty || !email.contains('@')) return '';
    return switch (domain) {
      'gmail.com' || 'googlemail.com' => 'imap.gmail.com',
      'outlook.com' || 'hotmail.com' || 'live.com' || 'msn.com' => 'outlook.office365.com',
      'yahoo.com' || 'yahoo.es' => 'imap.mail.yahoo.com',
      'icloud.com' || 'me.com' => 'imap.mail.me.com',
      _ => 'mail.$domain',
    };
  }
}

/// A company VPN the user set up. No secrets live here.
@immutable
class Profile {
  const Profile({
    this.id = '',
    required this.name,
    required this.hosts,
    required this.port,
    this.realm = '',
    this.authMode = AuthMode.password,
    this.username = '',
    this.secondFactor = SecondFactorPreference.auto,
    this.emailOtp,
    this.hasPassword = false,
    this.hasEmailPassword = false,
    this.pinSha256,
  });

  /// Empty until the engine saves it.
  final String id;
  final String name;

  /// Gateway addresses tried in order; the first is the main one.
  final List<String> hosts;
  final int port;
  final String realm;
  final AuthMode authMode;
  final String username;
  final SecondFactorPreference secondFactor;
  final EmailOtpSource? emailOtp;
  final bool hasPassword;
  final bool hasEmailPassword;

  /// Certificate the user trusts for the main address (read-only, set by trusting it).
  final String? pinSha256;

  String get mainHost => hosts.first;
  String get address => port == 443 ? mainHost : '$mainHost:$port';

  /// Can connect without asking for anything first.
  bool get ready => authMode == AuthMode.sso || (username.isNotEmpty && hasPassword);

  Profile copyWith({
    String? name,
    List<String>? hosts,
    int? port,
    String? realm,
    AuthMode? authMode,
    String? username,
    SecondFactorPreference? secondFactor,
  }) => Profile(
    id: id,
    name: name ?? this.name,
    hosts: hosts ?? this.hosts,
    port: port ?? this.port,
    realm: realm ?? this.realm,
    authMode: authMode ?? this.authMode,
    username: username ?? this.username,
    secondFactor: secondFactor ?? this.secondFactor,
    emailOtp: emailOtp,
    hasPassword: hasPassword,
    hasEmailPassword: hasEmailPassword,
    pinSha256: pinSha256,
  );
}

/// What a gateway offers, learned before saving a profile.
@immutable
class ProbeResult {
  const ProbeResult({
    required this.host,
    required this.port,
    this.certSha256 = '',
    this.trustedBySystem = false,
    this.pinned = false,
    this.ssoOffered = false,
    this.error,
    this.errorDetail,
    this.sslVpnPortal = true,
    this.ikeAnswers = false,
    this.clientCertRequested = false,
  });
  final String host;
  final int port;
  final String certSha256;
  final bool trustedBySystem;
  final bool pinned;
  final bool ssoOffered;
  final VpnErrorCode? error;
  final String? errorDetail;

  /// The SSL-VPN login page is there; false looks like FortiOS 7.6.3+ without tunnel mode.
  final bool sslVpnPortal;

  /// The address answered an IPsec (IKEv2) probe.
  final bool ikeAnswers;

  /// The server asked for a client certificate, which the app doesn't have yet.
  final bool clientCertRequested;

  bool get ok => error == null;

  /// Why this server may not work yet, if anything (shown before sign-in, with a way to continue).
  VpnErrorCode? get blocker => !ok
      ? null
      : !sslVpnPortal
      ? VpnErrorCode.sslVpnOff
      : clientCertRequested
      ? VpnErrorCode.clientCertRequired
      : null;

  /// The user must look at the certificate before we can connect.
  bool get needsTrust => ok && !trustedBySystem && !pinned;

  /// The digest in groups of four, the way people compare it aloud.
  String get fingerprintGroups =>
      [for (var i = 0; i < certSha256.length; i += 4) certSha256.substring(i, (i + 4).clamp(0, certSha256.length))]
          .join(' ')
          .toUpperCase();
}

enum ThemePreference { system, light, dark }

@immutable
class AppPrefs {
  const AppPrefs({this.theme = ThemePreference.system, this.onboarded = false, this.activeProfileId});
  final ThemePreference theme;
  final bool onboarded;
  final String? activeProfileId;
}
