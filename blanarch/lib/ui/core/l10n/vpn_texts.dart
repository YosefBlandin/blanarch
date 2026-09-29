import '../../../domain/models/vpn_status.dart';
import 'l10n.dart';

/// Turns engine states and error codes into the user's language.
extension VpnTexts on AppLocalizations {
  String headline(VpnPhase phase) => switch (phase) {
    VpnPhase.idle => phaseIdle,
    VpnPhase.connected => phaseConnected,
    VpnPhase.error => phaseError,
    VpnPhase.disconnecting => phaseDisconnecting,
    VpnPhase.reconnecting => phaseReconnecting,
    VpnPhase.waitingNetwork => phaseWaitingNetwork,
    _ => phaseConnecting,
  };

  String stepLabel(VpnStatus s) => switch (s.phase) {
    VpnPhase.waitingPush => stepApproval,
    VpnPhase.waitingSso => stepSso,
    VpnPhase.waitingNetwork => stepWaitingNetwork,
    _ => switch (s.step) {
      ConnectStep.gateway => stepGateway,
      ConnectStep.signingIn => stepSigningIn,
      ConnectStep.emailCode => s.otpMasked != null ? stepVerifying(s.otpMasked!) : stepWaitingCode,
      ConnectStep.tunnel => stepTunnel,
      null => '',
    },
  };

  String error(VpnErrorCode code, {int attempts = 0}) => switch (code) {
    VpnErrorCode.noVpnPassword => errorNoVpnPassword,
    VpnErrorCode.authRejected => errorAuthRejected,
    VpnErrorCode.unsupportedChallenge => errorUnsupportedChallenge,
    VpnErrorCode.certMismatch => errorCertMismatch,
    VpnErrorCode.certUntrusted => errorCertUntrusted,
    VpnErrorCode.ssoTimeout => errorSsoTimeout,
    VpnErrorCode.ssoFailed => errorSsoFailed,
    VpnErrorCode.noProfile => errorNoProfile,
    VpnErrorCode.invalidAddress => errorInvalidAddress,
    VpnErrorCode.permissionRevoked => errorPermissionRevoked,
    VpnErrorCode.outOfAttempts => errorOutOfAttempts(attempts),
    VpnErrorCode.otpTimeout => errorOtpTimeout,
    VpnErrorCode.otpRejected => errorOtpRejected,
    VpnErrorCode.gatewayUnreachable => errorGatewayUnreachable,
    VpnErrorCode.tunnelRefused => errorTunnelRefused,
    VpnErrorCode.protocol => errorProtocol,
    VpnErrorCode.linkLost => errorLinkLost,
    VpnErrorCode.emailAuthFailed => errorEmailAuthFailed,
    VpnErrorCode.emailUnreachable => errorEmailUnreachable,
    VpnErrorCode.emailNotConfigured => errorEmailNotConfigured,
    VpnErrorCode.locked => errorLocked,
    VpnErrorCode.networkChanged => errorNetworkChanged,
    VpnErrorCode.noNetwork => errorNoNetwork,
    VpnErrorCode.sessionExpired => errorSessionExpired,
    VpnErrorCode.sslVpnOff => errorSslVpnOff,
    VpnErrorCode.clientCertRequired => errorClientCertRequired,
  };

  /// A log line of a main connection step, in the user's language.
  String activityLine(LogEntry e) {
    String arg(int i) => i < e.args.length ? e.args[i] : '';
    return switch (e.event) {
      LogEvent.starting => eventStarting(arg(0)),
      LogEvent.attempt => eventAttempt(arg(0), arg(1), arg(2)),
      LogEvent.failed => [
        VpnErrorCode.values.where((c) => c.name == _camel(arg(0))).map(error).firstOrNull ?? arg(0),
        if (arg(1).isNotEmpty) arg(1),
      ].join(' · '),
      LogEvent.signingIn => eventSigningIn(arg(0)),
      LogEvent.signedIn => eventSignedIn,
      LogEvent.waitingSso => eventWaitingSso,
      LogEvent.approvePush => eventApprovePush,
      LogEvent.codeReceived => eventCodeReceived(arg(0)),
      LogEvent.connected => eventConnected(arg(0)),
      LogEvent.connectionLost => eventConnectionLost,
      LogEvent.reconnecting => eventReconnecting,
      LogEvent.disconnected => eventDisconnected,
      LogEvent.networkLost => eventNetworkLost,
      LogEvent.networkBack => eventNetworkBack,
      LogEvent.networkChanged => eventNetworkChanged,
      LogEvent.sessionExpired => eventSessionExpired,
      LogEvent.dnsFallback => eventDnsFallback(arg(0)),
      null => e.message,
    };
  }

  /// One concrete next step for the user (NN/g: say how to fix it).
  String fixFor(VpnErrorCode code) => switch (code) {
    VpnErrorCode.authRejected || VpnErrorCode.noVpnPassword => fixAuthRejected,
    VpnErrorCode.gatewayUnreachable || VpnErrorCode.invalidAddress => fixGatewayUnreachable,
    VpnErrorCode.outOfAttempts => fixOutOfAttempts,
    VpnErrorCode.unsupportedChallenge => fixUnsupportedChallenge,
    VpnErrorCode.certUntrusted => fixCertUntrusted,
    VpnErrorCode.certMismatch => fixCertMismatch,
    VpnErrorCode.otpTimeout || VpnErrorCode.otpRejected => fixOtp,
    VpnErrorCode.tunnelRefused => fixTunnelRefused,
    VpnErrorCode.locked => fixLocked,
    VpnErrorCode.noNetwork => fixNoNetwork,
    VpnErrorCode.sslVpnOff => fixSslVpnOff,
    VpnErrorCode.clientCertRequired => fixClientCert,
    _ => fixGeneric,
  };
}

/// `GATEWAY_UNREACHABLE` (the engine's name) to `gatewayUnreachable`.
String _camel(String upper) {
  final parts = upper.toLowerCase().split('_');
  return parts.first + parts.skip(1).map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1)).join();
}
