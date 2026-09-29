import 'dart:async';

import '../../domain/models/profile.dart';
import '../../domain/models/vpn_status.dart';
import 'pigeon/vpn_api.g.dart';

/// Everything the app needs from the native VPN engine. Repositories depend on
/// this interface; tests pass a fake.
abstract interface class VpnPlatform {
  Stream<VpnStatus> get statusChanges;
  Stream<LogEntry> get logEntries;
  Stream<List<Profile>> get profileChanges;

  /// Setup links that arrive while the app is running.
  Stream<String> get setupLinks;

  Future<List<Profile>> profiles();

  /// Creates (empty id) or updates; a non-null [password] replaces the saved one.
  Future<Profile> saveProfile(Profile profile, {String? password});
  Future<void> deleteProfile(String id);
  Future<ProbeResult> probe(String address);
  Future<void> trustCertificate(String host, String sha256);

  /// Null when the mailbox accepted the password (source and password are then saved).
  Future<VpnErrorCode?> saveEmailOtp(String profileId, EmailOtpSource source, String password);
  Future<void> removeEmailOtp(String profileId);

  Future<AppPrefs> prefs();
  Future<VpnStatus> status();
  Future<List<LogEntry>> log();

  Future<ConnectResult> connect(String profileId);
  Future<void> disconnect();

  /// Restarts the current sign-in with a code instead of a push, for this attempt only.
  Future<void> useCodeThisTime();

  /// Opens the system share sheet.
  Future<void> shareText(String subject, String text);
  Future<void> submitOtp(String code);
  Future<void> openSso(String url);
  Future<bool> prepareVpn();
  Future<bool> requestNotifications();

  Future<void> setTheme(ThemePreference theme);
  Future<void> setOnboarded(bool onboarded);
  Future<void> setActiveProfile(String profileId);

  Future<bool> appLockAvailable();
  Future<bool> appLockEnabled();

  /// False when the user cancelled the unlock.
  Future<bool> setAppLock(bool enabled);

  /// Offers the Quick Settings tile; unless [always], only once.
  Future<void> requestAddTile({bool always = false});
  Future<bool> canAddTile();
  Future<void> openVpnSettings();

  /// The link the app was opened with, once.
  Future<String?> takeSetupLink();
}

enum ConnectResult { started, vpnDenied, unlockCancelled }

/// [VpnPlatform] over the Pigeon-generated bridge.
class PigeonVpnPlatform implements VpnPlatform, VpnEventsApi {
  PigeonVpnPlatform({VpnHostApi? api}) : _api = api ?? VpnHostApi() {
    VpnEventsApi.setUp(this);
  }

  final VpnHostApi _api;
  final _status = StreamController<VpnStatus>.broadcast();
  final _log = StreamController<LogEntry>.broadcast();
  final _profiles = StreamController<List<Profile>>.broadcast();
  final _links = StreamController<String>.broadcast();

  @override
  Stream<VpnStatus> get statusChanges => _status.stream;
  @override
  Stream<LogEntry> get logEntries => _log.stream;
  @override
  Stream<List<Profile>> get profileChanges => _profiles.stream;
  @override
  Stream<String> get setupLinks => _links.stream;

  @override
  void onStatus(VpnStatusMsg status) => _status.add(status.toDomain());
  @override
  void onLog(LogEntryMsg entry) => _log.add(entry.toDomain());
  @override
  void onSetupLink(String url) => _links.add(url);
  @override
  void onProfilesChanged(List<ProfileMsg> profiles) => _profiles.add([for (final p in profiles) p.toDomain()]);

  @override
  Future<List<Profile>> profiles() async => [for (final p in await _api.profiles()) p.toDomain()];

  @override
  Future<Profile> saveProfile(Profile profile, {String? password}) async =>
      (await _api.saveProfile(profile.toMsg(), password)).toDomain();

  @override
  Future<void> deleteProfile(String id) => _api.deleteProfile(id);

  @override
  Future<ProbeResult> probe(String address) async {
    final r = await _api.probe(address);
    return ProbeResult(
      host: r.host,
      port: r.port,
      certSha256: r.certSha256,
      trustedBySystem: r.trustedBySystem,
      pinned: r.pinned,
      ssoOffered: r.ssoOffered,
      error: r.error?.toDomain(),
      errorDetail: r.errorDetail,
      sslVpnPortal: r.sslVpnPortal ?? true,
      ikeAnswers: r.ikeAnswers ?? false,
      clientCertRequested: r.clientCertRequested ?? false,
    );
  }

  @override
  Future<void> trustCertificate(String host, String sha256) => _api.trustCertificate(host, sha256);

  @override
  Future<VpnErrorCode?> saveEmailOtp(String profileId, EmailOtpSource source, String password) async =>
      (await _api.saveEmailOtp(profileId, source.toMsg(), password))?.toDomain();

  @override
  Future<void> removeEmailOtp(String profileId) => _api.removeEmailOtp(profileId);

  @override
  Future<AppPrefs> prefs() async {
    final p = await _api.prefs();
    return AppPrefs(
      theme: ThemePreference.values.byName(p.themeMode.name),
      onboarded: p.onboarded,
      activeProfileId: p.activeProfileId,
    );
  }

  @override
  Future<VpnStatus> status() async => (await _api.status()).toDomain();
  @override
  Future<List<LogEntry>> log() async => [for (final e in await _api.log()) e.toDomain()];

  @override
  Future<ConnectResult> connect(String profileId) async =>
      ConnectResult.values.byName((await _api.connect(profileId)).name);
  @override
  Future<void> disconnect() => _api.disconnect();
  @override
  Future<void> useCodeThisTime() => _api.useCodeThisTime();
  @override
  Future<void> shareText(String subject, String text) => _api.shareText(subject, text);
  @override
  Future<void> submitOtp(String code) => _api.submitOtp(code);
  @override
  Future<void> openSso(String url) => _api.openSso(url);
  @override
  Future<bool> prepareVpn() => _api.prepareVpn();
  @override
  Future<bool> requestNotifications() => _api.requestNotifications();

  @override
  Future<void> setTheme(ThemePreference theme) => _api.setThemeMode(ThemeModeMsg.values.byName(theme.name));
  @override
  Future<void> setOnboarded(bool onboarded) => _api.setOnboarded(onboarded);
  @override
  Future<void> setActiveProfile(String profileId) => _api.setActiveProfile(profileId);
  @override
  Future<bool> appLockAvailable() => _api.appLockAvailable();
  @override
  Future<bool> appLockEnabled() => _api.appLockEnabled();
  @override
  Future<bool> setAppLock(bool enabled) => _api.setAppLock(enabled);
  @override
  Future<void> requestAddTile({bool always = false}) => _api.requestAddTile(always);
  @override
  Future<bool> canAddTile() => _api.canAddTile();
  @override
  Future<void> openVpnSettings() => _api.openVpnSettings();
  @override
  Future<String?> takeSetupLink() => _api.takeSetupLink();
}

extension on ErrorCodeMsg {
  VpnErrorCode toDomain() => VpnErrorCode.values.byName(name);
}

extension on ProfileMsg {
  Profile toDomain() => Profile(
    id: id,
    name: name,
    hosts: hosts,
    port: port,
    realm: realm,
    authMode: AuthMode.values.byName(authMode.name),
    username: username,
    secondFactor: SecondFactorPreference.values.byName(secondFactor.name),
    emailOtp: emailOtp == null
        ? null
        : EmailOtpSource(
            account: emailOtp!.account,
            imapHost: emailOtp!.imapHost,
            imapPort: emailOtp!.imapPort,
            mailbox: emailOtp!.mailbox,
            from: emailOtp!.from,
          ),
    hasPassword: hasPassword,
    hasEmailPassword: hasEmailPassword,
    pinSha256: pinSha256,
  );
}

extension on Profile {
  ProfileMsg toMsg() => ProfileMsg(
    id: id,
    name: name,
    hosts: hosts,
    port: port,
    realm: realm,
    authMode: AuthModeMsg.values.byName(authMode.name),
    username: username,
    secondFactor: SecondFactorMsg.values.byName(secondFactor.name),
    emailOtp: emailOtp?.toMsg(),
    hasPassword: hasPassword,
    hasEmailPassword: hasEmailPassword,
  );
}

extension on EmailOtpSource {
  EmailOtpMsg toMsg() =>
      EmailOtpMsg(account: account, imapHost: imapHost, imapPort: imapPort, mailbox: mailbox, from: from);
}

extension on VpnStatusMsg {
  VpnStatus toDomain() => VpnStatus(
    phase: VpnPhase.values.byName(phase.name),
    profileId: profileId,
    host: host,
    attempt: attempt,
    maxAttempts: maxAttempts,
    ip: ip,
    otpMasked: otpMasked,
    connectedSince: connectedSinceMillis == null ? null : DateTime.fromMillisecondsSinceEpoch(connectedSinceMillis!),
    emailWatching: emailWatching,
    emailIssue: emailIssue?.toDomain(),
    error: error?.toDomain(),
    errorDetail: errorDetail,
    ssoUrl: ssoUrl,
    deadline: deadlineMillis == null ? null : DateTime.fromMillisecondsSinceEpoch(deadlineMillis!),
    startedAt: startedMillis == null ? null : DateTime.fromMillisecondsSinceEpoch(startedMillis!),
    retryReason: retryReason?.toDomain(),
    port: port,
    bytesIn: bytesIn,
    bytesOut: bytesOut,
    latency: latencyMillis == null ? null : Duration(milliseconds: latencyMillis!),
    dns: dns,
    dnsSuffix: dnsSuffix,
    routes: routes,
    mtu: mtu,
    tls: tls,
    signIn: SignInMethod.values.where((m) => m.name.toUpperCase() == signIn).firstOrNull,
    reconnects: reconnects,
    triedHosts: triedHosts,
    certSha256: certSha256,
  );
}

extension on LogEntryMsg {
  LogEntry toDomain() => LogEntry(
    time: DateTime.fromMillisecondsSinceEpoch(timeMillis),
    level: LogLevel.values.byName(level.name),
    message: message,
    event: event == null ? null : LogEvent.values.byName(event!.name),
    args: args,
  );
}
