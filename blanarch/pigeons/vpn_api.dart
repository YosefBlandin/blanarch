// Contract between the Flutter UI and the Kotlin VPN engine.
// Regenerate with: dart run pigeon --input pigeons/vpn_api.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/data/services/pigeon/vpn_api.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/blanarch/app/bridge/VpnApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.blanarch.app.bridge'),
    dartPackageName: 'blanarch',
  ),
)
enum VpnPhaseMsg {
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

enum ErrorCodeMsg {
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

enum LogLevelMsg { info, ok, error }

enum ThemeModeMsg { system, light, dark }

enum AuthModeMsg { password, sso }

enum SecondFactorMsg { auto, code }

enum ConnectResultMsg { started, vpnDenied, unlockCancelled }

class EmailOtpMsg {
  EmailOtpMsg({
    required this.account,
    required this.imapHost,
    required this.imapPort,
    required this.mailbox,
    required this.from,
  });
  String account;
  String imapHost;
  int imapPort;
  String mailbox;
  String from;
}

class ProfileMsg {
  ProfileMsg({
    required this.id,
    required this.name,
    required this.hosts,
    required this.port,
    required this.realm,
    required this.authMode,
    required this.username,
    required this.secondFactor,
    this.emailOtp,
    required this.hasPassword,
    required this.hasEmailPassword,
    this.pinSha256,
  });

  /// Empty when creating a new profile.
  String id;
  String name;
  List<String> hosts;
  int port;
  String realm;
  AuthModeMsg authMode;
  String username;
  SecondFactorMsg secondFactor;
  EmailOtpMsg? emailOtp;
  bool hasPassword;
  bool hasEmailPassword;

  /// Certificate the user trusts for the main address, if any (read-only).
  String? pinSha256;
}

/// What a gateway offers, learned before saving a profile.
class ProbeResultMsg {
  ProbeResultMsg({
    required this.host,
    required this.port,
    required this.certSha256,
    required this.trustedBySystem,
    required this.pinned,
    required this.ssoOffered,
    this.error,
    this.errorDetail,
    this.sslVpnPortal,
    this.ikeAnswers,
    this.clientCertRequested,
  });
  String host;
  int port;
  String certSha256;
  bool trustedBySystem;

  /// The user already trusts this exact certificate for this host.
  bool pinned;
  bool ssoOffered;
  ErrorCodeMsg? error;
  String? errorDetail;

  /// The SSL-VPN login page is there; false looks like FortiOS 7.6.3+ without tunnel mode.
  bool? sslVpnPortal;

  /// The address answered an IKEv2 probe (fortigate-ipsec.md §2).
  bool? ikeAnswers;

  /// The server asked for a client certificate during TLS.
  bool? clientCertRequested;
}

class PrefsMsg {
  PrefsMsg({required this.themeMode, required this.onboarded, this.activeProfileId});
  ThemeModeMsg themeMode;
  bool onboarded;
  String? activeProfileId;
}

class VpnStatusMsg {
  VpnStatusMsg({
    required this.phase,
    this.profileId,
    this.host,
    required this.attempt,
    required this.maxAttempts,
    this.ip,
    this.otpMasked,
    this.connectedSinceMillis,
    required this.emailWatching,
    this.emailIssue,
    this.error,
    this.errorDetail,
    this.ssoUrl,
    this.deadlineMillis,
    this.startedMillis,
    this.retryReason,
    this.port,
    required this.bytesIn,
    required this.bytesOut,
    this.latencyMillis,
    required this.dns,
    this.dnsSuffix,
    required this.routes,
    this.mtu,
    this.tls,
    this.signIn,
    required this.reconnects,
    required this.triedHosts,
    this.certSha256,
  });
  VpnPhaseMsg phase;
  String? profileId;
  String? host;
  int attempt;
  int maxAttempts;
  String? ip;
  String? otpMasked;
  int? connectedSinceMillis;
  bool emailWatching;
  ErrorCodeMsg? emailIssue;
  ErrorCodeMsg? error;
  String? errorDetail;
  String? ssoUrl;

  /// While waiting for a code or single sign-on: when the app stops waiting.
  int? deadlineMillis;

  /// When this connection run started; null when idle or connected.
  int? startedMillis;

  /// Why the previous attempt failed, while the next one runs.
  ErrorCodeMsg? retryReason;

  // While connected, for the details screen. Nothing secret.
  int? port;
  int bytesIn;
  int bytesOut;
  int? latencyMillis;
  List<String> dns;
  String? dnsSuffix;

  /// "network/prefix"; empty while connected means all traffic.
  List<String> routes;
  int? mtu;
  String? tls;

  /// PASSWORD, CODE, PUSH or SSO.
  String? signIn;
  int reconnects;
  List<String> triedHosts;

  /// Pinned certificate of the current host, if any.
  String? certSha256;
}

/// Main connection steps, for showing log lines in the user's language.
enum LogEventMsg {
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

class LogEntryMsg {
  LogEntryMsg({required this.timeMillis, required this.level, required this.message, this.event, required this.args});
  int timeMillis;
  LogLevelMsg level;

  /// English, for sharing with IT.
  String message;
  LogEventMsg? event;
  List<String> args;
}

/// Calls from Dart into the Kotlin engine.
@HostApi()
abstract class VpnHostApi {
  List<ProfileMsg> profiles();

  /// Creates (empty id) or updates a profile. A non-null [vpnPassword] replaces the saved one.
  /// With the app lock on, the user is asked to unlock first.
  @async
  ProfileMsg saveProfile(ProfileMsg profile, String? vpnPassword);
  void deleteProfile(String id);

  /// Connects to the address the user typed and reports certificate and sign-in options.
  @async
  ProbeResultMsg probe(String address);

  /// Remembers the user's decision to trust this certificate for this host.
  void trustCertificate(String host, String sha256);

  /// Checks the mailbox login, then saves the source and password on the profile.
  /// Returns null on success, otherwise why it failed.
  @async
  ErrorCodeMsg? saveEmailOtp(String profileId, EmailOtpMsg source, String password);
  void removeEmailOtp(String profileId);

  PrefsMsg prefs();
  VpnStatusMsg status();
  List<LogEntryMsg> log();

  /// Asks to unlock (if the app lock is on) and for the VPN permission, then starts connecting.
  @async
  ConnectResultMsg connect(String profileId);
  void disconnect();

  /// Restarts the current sign-in answering with a code instead of a push, for this attempt only.
  void useCodeThisTime();
  void submitOtp(String code);

  /// Opens the single sign-on page in a browser tab.
  void openSso(String url);

  /// Opens Android's share sheet with [text] (the activity log, for IT).
  void shareText(String subject, String text);

  @async
  bool prepareVpn();
  @async
  bool requestNotifications();

  void setThemeMode(ThemeModeMsg mode);
  void setOnboarded(bool onboarded);
  void setActiveProfile(String profileId);

  /// The phone has a screen lock or biometrics, so the app lock can be used.
  bool appLockAvailable();
  bool appLockEnabled();

  /// Asks the user to unlock, then re-encrypts saved passwords. False if they cancelled.
  @async
  bool setAppLock(bool enabled);

  /// Offers to add the Quick Settings tile (Android 13+). No-op elsewhere.
  /// Unless [always], it asks only once (after the first connection).
  void requestAddTile(bool always);

  /// Android can offer the tile from inside the app (13 and later).
  bool canAddTile();

  /// Opens Android's VPN settings (always-on VPN and blocking connections without VPN).
  void openVpnSettings();

  /// A setup link the app was opened with, if not handled yet.
  String? takeSetupLink();
}

/// Pushes from the Kotlin engine to Dart.
@FlutterApi()
abstract class VpnEventsApi {
  void onStatus(VpnStatusMsg status);
  void onLog(LogEntryMsg entry);
  void onProfilesChanged(List<ProfileMsg> profiles);

  /// The app was opened with a setup link while running.
  void onSetupLink(String url);
}
