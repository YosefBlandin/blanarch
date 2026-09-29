import 'dart:async';

import '../../domain/models/profile.dart';
import '../../domain/models/setup_link.dart';
import '../../domain/models/vpn_status.dart';
import '../../utils/result.dart';
import '../services/vpn_platform.dart';

/// The mail server refused the email password; [code] says why.
class EmailPasswordRejected implements Exception {
  const EmailPasswordRejected(this.code);
  final VpnErrorCode code;
}

/// Source of truth for the user's VPN profiles.
class ProfileRepository {
  ProfileRepository(this._platform) {
    _subscription = _platform.profileChanges.listen(_set);
  }

  final VpnPlatform _platform;
  late final StreamSubscription<List<Profile>> _subscription;
  final _out = StreamController<List<Profile>>.broadcast();
  List<Profile> _profiles = const [];

  List<Profile> get profiles => _profiles;
  Stream<List<Profile>> get changes => _out.stream;
  Profile? byId(String? id) => _profiles.where((p) => p.id == id).firstOrNull;

  void _set(List<Profile> list) {
    _profiles = List.unmodifiable(list);
    _out.add(_profiles);
  }

  Future<void> load() async => _set(await _platform.profiles());

  Future<Result<Profile>> save(Profile profile, {String? password}) async {
    try {
      final saved = await _platform.saveProfile(profile, password: password);
      await load();
      return Result.ok(saved);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  Future<Result<void>> delete(String id) async {
    try {
      await _platform.deleteProfile(id);
      await load();
      return const Result.ok(null);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  Future<ProbeResult> probe(String address) async {
    try {
      return await _platform.probe(address);
    } on Exception catch (e) {
      return ProbeResult(host: address, port: 0, error: VpnErrorCode.gatewayUnreachable, errorDetail: '$e');
    }
  }

  Future<void> trust(ProbeResult probe) => _platform.trustCertificate(probe.host, probe.certSha256);

  /// Verifies against the mail server, then saves the source and password.
  Future<Result<void>> saveEmailOtp(String profileId, EmailOtpSource source, String password) async {
    try {
      final rejected = await _platform.saveEmailOtp(profileId, source, password);
      await load();
      return rejected == null ? const Result.ok(null) : Result.error(EmailPasswordRejected(rejected));
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  Future<void> removeEmailOtp(String profileId) async {
    await _platform.removeEmailOtp(profileId);
    await load();
  }

  void dispose() {
    unawaited(_subscription.cancel());
    unawaited(_out.close());
  }
}

class SettingsRepository {
  SettingsRepository(this._platform);
  final VpnPlatform _platform;

  Future<AppPrefs> load() async {
    try {
      return await _platform.prefs();
    } on Exception {
      return const AppPrefs();
    }
  }

  Future<void> setTheme(ThemePreference theme) => _platform.setTheme(theme);
  Future<void> setOnboarded(bool onboarded) => _platform.setOnboarded(onboarded);
  Future<void> setActiveProfile(String profileId) => _platform.setActiveProfile(profileId);

  Future<bool> appLockAvailable() => _platform.appLockAvailable();
  Future<bool> appLockEnabled() => _platform.appLockEnabled();

  /// False when the user cancelled the unlock.
  Future<bool> setAppLock(bool enabled) => _platform.setAppLock(enabled);

  /// Offers the Quick Settings tile once (Android 13+); the engine remembers it asked.
  Future<void> offerQuickSettingsTile() => _platform.requestAddTile();

  /// From Settings: offers the tile whenever the user asks.
  Future<void> addQuickSettingsTile() => _platform.requestAddTile(always: true);
  Future<bool> canAddTile() => _platform.canAddTile();
  Future<void> openVpnSettings() => _platform.openVpnSettings();

  /// Setup links: the one the app was opened with, then any that arrive later.
  Future<SetupLink?> takeSetupLink() async {
    final url = await _platform.takeSetupLink();
    return url == null ? null : SetupLink.parse(url);
  }

  Stream<SetupLink> get setupLinks => _platform.setupLinks.map(SetupLink.parse).where((l) => l != null).cast();
}
