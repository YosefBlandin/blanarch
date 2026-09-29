import 'dart:async';

import 'package:blanarch/data/services/vpn_platform.dart';
import 'package:blanarch/domain/models/profile.dart';
import 'package:blanarch/domain/models/vpn_status.dart';

/// In-memory [VpnPlatform] for view-model and screen tests.
class FakeVpnPlatform implements VpnPlatform {
  FakeVpnPlatform({
    List<Profile>? profiles,
    this.currentStatus = const VpnStatus(),
    this.prefsValue = const AppPrefs(onboarded: true, activeProfileId: 'lima'),
    this.grantVpn = true,
    this.unlock = true,
    this.lockAvailable = true,
    this.emailRejection,
    this.probeResult,
  }) : _profileList = profiles ?? [lima, madrid];

  static const lima = Profile(
    id: 'lima',
    name: 'Lima',
    hosts: ['198.51.100.18'],
    port: 4443,
    username: 'ana',
    hasPassword: true,
  );
  static const madrid = Profile(
    id: 'madrid',
    name: 'Madrid',
    hosts: ['203.0.113.46', '203.0.113.42'],
    port: 10443,
    username: 'ana',
    hasPassword: true,
  );

  List<Profile> _profileList;
  VpnStatus currentStatus;
  AppPrefs prefsValue;
  bool grantVpn;

  /// What the user does at the fingerprint/face prompt.
  bool unlock;
  bool lockAvailable;
  bool lockEnabled = false;
  String? pendingLink;
  VpnErrorCode? emailRejection;
  ProbeResult? probeResult;

  /// Addresses that don't answer the server check.
  Set<String> unreachable = {};

  final calls = <String>[];
  final passwords = <String, String>{};
  final _status = StreamController<VpnStatus>.broadcast();
  // ignore: close_sinks (lives for one test)
  final _log = StreamController<LogEntry>.broadcast();
  final _profiles = StreamController<List<Profile>>.broadcast();
  // ignore: close_sinks (lives for one test)
  final _links = StreamController<String>.broadcast();

  void sendLink(String url) => _links.add(url);

  /// Entries returned by [log] and pushed by [emitLog].
  List<LogEntry> logList = [];

  void emitLog(LogEntry e) {
    logList = [...logList, e];
    _log.add(e);
  }

  void emit(VpnStatus s) {
    currentStatus = s;
    _status.add(s);
  }

  @override
  Stream<VpnStatus> get statusChanges => _status.stream;
  @override
  Stream<LogEntry> get logEntries => _log.stream;
  @override
  Stream<List<Profile>> get profileChanges => _profiles.stream;
  @override
  Stream<String> get setupLinks => _links.stream;

  @override
  Future<List<Profile>> profiles() async => _profileList;

  @override
  Future<Profile> saveProfile(Profile profile, {String? password}) async {
    final id = profile.id.isEmpty ? 'p${_profileList.length + 1}' : profile.id;
    if (password != null) passwords[id] = password;
    final saved = Profile(
      id: id,
      name: profile.name,
      hosts: profile.hosts,
      port: profile.port,
      realm: profile.realm,
      authMode: profile.authMode,
      username: profile.username,
      secondFactor: profile.secondFactor,
      emailOtp: profile.emailOtp,
      hasPassword: passwords.containsKey(id) || profile.hasPassword,
    );
    _profileList = [..._profileList.where((p) => p.id != id), saved];
    calls.add('save:$id');
    _profiles.add(_profileList);
    return saved;
  }

  @override
  Future<void> deleteProfile(String id) async {
    _profileList = _profileList.where((p) => p.id != id).toList();
    calls.add('delete:$id');
  }

  @override
  Future<ProbeResult> probe(String address) async {
    calls.add('probe:$address');
    if (unreachable.contains(address)) {
      return ProbeResult(host: address.split(':').first, port: 0, error: VpnErrorCode.gatewayUnreachable);
    }
    return probeResult ??
        ProbeResult(
          host: address.split(':').first,
          port: address.contains(':') ? int.parse(address.split(':').last) : 443,
          certSha256: '7d2e41c09b8a5f6e3d1c0b9a8f7e6d5c4b3a29181706f5e4d3c2b1a098f7e6d5',
          trustedBySystem: true,
        );
  }

  @override
  Future<void> trustCertificate(String host, String sha256) async => calls.add('trust:$host');

  @override
  Future<VpnErrorCode?> saveEmailOtp(String profileId, EmailOtpSource source, String password) async {
    calls.add('email:$profileId:${source.imapHost}');
    return emailRejection;
  }

  @override
  Future<void> removeEmailOtp(String profileId) async => calls.add('removeEmail:$profileId');

  @override
  Future<AppPrefs> prefs() async => prefsValue;
  @override
  Future<VpnStatus> status() async => currentStatus;
  @override
  Future<List<LogEntry>> log() async => logList;

  @override
  Future<ConnectResult> connect(String profileId) async {
    if (lockEnabled && !unlock) return ConnectResult.unlockCancelled;
    calls.add('connect:$profileId');
    return grantVpn ? ConnectResult.started : ConnectResult.vpnDenied;
  }

  @override
  Future<bool> appLockAvailable() async => lockAvailable;
  @override
  Future<bool> appLockEnabled() async => lockEnabled;
  @override
  Future<bool> setAppLock(bool enabled) async {
    if (!unlock) return false;
    lockEnabled = enabled;
    calls.add('lock:$enabled');
    return true;
  }

  @override
  Future<void> requestAddTile({bool always = false}) async => calls.add(always ? 'tile:always' : 'tile');
  @override
  Future<bool> canAddTile() async => true;
  @override
  Future<void> openVpnSettings() async => calls.add('vpnSettings');
  @override
  Future<String?> takeSetupLink() async {
    final link = pendingLink;
    pendingLink = null;
    return link;
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    emit(const VpnStatus());
  }

  @override
  Future<void> useCodeThisTime() async => calls.add('useCode');
  @override
  Future<void> shareText(String subject, String text) async => calls.add('share:$subject');

  @override
  Future<void> submitOtp(String code) async => calls.add('otp:$code');
  @override
  Future<void> openSso(String url) async => calls.add('sso:$url');
  @override
  Future<bool> prepareVpn() async {
    calls.add('prepareVpn');
    return grantVpn;
  }

  @override
  Future<bool> requestNotifications() async {
    calls.add('requestNotifications');
    return true;
  }

  @override
  Future<void> setTheme(ThemePreference theme) async => calls.add('theme:${theme.name}');
  @override
  Future<void> setOnboarded(bool onboarded) async => calls.add('onboarded:$onboarded');
  @override
  Future<void> setActiveProfile(String profileId) async => calls.add('active:$profileId');
}
