import 'package:flutter/foundation.dart';

enum VpnPhase {
  idle,
  connecting,
  authenticating,
  waitingOtp,
  waitingPush,
  waitingSso,
  negotiating,
  connected,
  reconnecting,
  waitingNetwork,
  disconnecting,
  error,
}

/// Why something failed. Mirrors ErrorCode in the Kotlin engine.
enum VpnErrorCode {
  noVpnPassword,
  authRejected,
  unsupportedChallenge,
  certMismatch,
  certUntrusted,
  ssoTimeout,
  ssoFailed,
  noProfile,
  permissionRevoked,
  outOfAttempts,
  otpTimeout,
  otpRejected,
  gatewayUnreachable,
  tunnelRefused,
  protocol,
  linkLost,
  emailAuthFailed,
  emailUnreachable,
  emailNotConfigured,
  invalidAddress,
  locked,
  networkChanged,
  noNetwork,
  sessionExpired,
  sslVpnOff,
  clientCertRequired,
}

/// How the user got in, for the details screen.
enum SignInMethod { password, code, push, sso }

/// The four visible steps of a connection attempt.
enum ConnectStep { gateway, signingIn, emailCode, tunnel }

@immutable
class VpnStatus {
  const VpnStatus({
    this.phase = VpnPhase.idle,
    this.profileId,
    this.host,
    this.attempt = 0,
    this.maxAttempts = 0,
    this.ip,
    this.otpMasked,
    this.connectedSince,
    this.emailWatching = false,
    this.emailIssue,
    this.error,
    this.errorDetail,
    this.ssoUrl,
    this.deadline,
    this.startedAt,
    this.retryReason,
    this.port,
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.latency,
    this.dns = const [],
    this.dnsSuffix,
    this.routes = const [],
    this.mtu,
    this.tls,
    this.signIn,
    this.reconnects = 0,
    this.triedHosts = const [],
    this.certSha256,
  });

  final VpnPhase phase;
  final String? profileId;
  final String? host;
  final int attempt;
  final int maxAttempts;
  final String? ip;
  final String? otpMasked;
  final DateTime? connectedSince;
  final bool emailWatching;
  final VpnErrorCode? emailIssue;
  final VpnErrorCode? error;
  final String? errorDetail;

  /// While waiting for single sign-on: the page to open in the browser.
  final String? ssoUrl;

  /// While waiting for a code or single sign-on: when the app stops waiting.
  final DateTime? deadline;

  /// When this connection run started; null when idle or connected.
  final DateTime? startedAt;

  /// Why the previous attempt failed, while the next one runs.
  final VpnErrorCode? retryReason;

  // While connected, for the details screen. Nothing secret.
  final int? port;
  final int bytesIn;
  final int bytesOut;

  /// Round trip of the latest keepalive; null until the first reply.
  final Duration? latency;
  final List<String> dns;
  final String? dnsSuffix;

  /// "network/prefix"; empty while connected means all traffic.
  final List<String> routes;
  final int? mtu;
  final String? tls;
  final SignInMethod? signIn;
  final int reconnects;

  /// Addresses tried in this run, in order.
  final List<String> triedHosts;

  /// Pinned certificate of the current host, if any.
  final String? certSha256;

  bool get active => phase != VpnPhase.idle && phase != VpnPhase.error;
  bool get busy => active && phase != VpnPhase.connected;

  ConnectStep? get step => switch (phase) {
    VpnPhase.connecting => ConnectStep.gateway,
    VpnPhase.authenticating => otpMasked == null ? ConnectStep.signingIn : ConnectStep.emailCode,
    VpnPhase.waitingOtp || VpnPhase.waitingPush || VpnPhase.waitingSso => ConnectStep.emailCode,
    VpnPhase.negotiating || VpnPhase.reconnecting => ConnectStep.tunnel,
    VpnPhase.waitingNetwork => ConnectStep.gateway,
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is VpnStatus &&
      other.phase == phase &&
      other.profileId == profileId &&
      other.host == host &&
      other.attempt == attempt &&
      other.maxAttempts == maxAttempts &&
      other.ip == ip &&
      other.otpMasked == otpMasked &&
      other.connectedSince == connectedSince &&
      other.emailWatching == emailWatching &&
      other.emailIssue == emailIssue &&
      other.error == error &&
      other.errorDetail == errorDetail &&
      other.ssoUrl == ssoUrl &&
      other.deadline == deadline &&
      other.startedAt == startedAt &&
      other.retryReason == retryReason &&
      other.port == port &&
      other.bytesIn == bytesIn &&
      other.bytesOut == bytesOut &&
      other.latency == latency &&
      listEquals(other.dns, dns) &&
      other.dnsSuffix == dnsSuffix &&
      listEquals(other.routes, routes) &&
      other.mtu == mtu &&
      other.tls == tls &&
      other.signIn == signIn &&
      other.reconnects == reconnects &&
      listEquals(other.triedHosts, triedHosts) &&
      other.certSha256 == certSha256;

  @override
  int get hashCode => Object.hashAll([
    phase,
    profileId,
    host,
    attempt,
    maxAttempts,
    ip,
    otpMasked,
    connectedSince,
    emailWatching,
    emailIssue,
    error,
    errorDetail,
    ssoUrl,
    deadline,
    startedAt,
    retryReason,
    port,
    bytesIn,
    bytesOut,
    latency,
    Object.hashAll(dns),
    dnsSuffix,
    Object.hashAll(routes),
    mtu,
    tls,
    signIn,
    reconnects,
    Object.hashAll(triedHosts),
    certSha256,
  ]);
}

enum LogLevel { info, ok, error }

/// Main connection steps, so the app can show log lines in the user's language.
enum LogEvent {
  starting,
  attempt,
  failed,
  signingIn,
  signedIn,
  waitingSso,
  approvePush,
  codeReceived,
  connected,
  connectionLost,
  reconnecting,
  disconnected,
  networkLost,
  networkBack,
  networkChanged,
  sessionExpired,
  dnsFallback,
}

@immutable
class LogEntry {
  const LogEntry({required this.time, required this.level, required this.message, this.event, this.args = const []});
  final DateTime time;
  final LogLevel level;

  /// English, for sharing with IT.
  final String message;

  /// Set for the main steps; [args] fill the translated text.
  final LogEvent? event;
  final List<String> args;
}
