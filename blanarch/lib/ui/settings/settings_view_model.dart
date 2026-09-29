import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/vpn_repository.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/vpn_status.dart';
import '../../utils/command.dart';
import '../../utils/result.dart';

const appVersion = '0.3';

/// Settings: connections, the app lock and a shortcut to Android's VPN settings.
class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({required this._profiles, required this._settings}) {
    _subscription = _profiles.changes.listen((_) => notifyListeners());
    setAppLock = Command1<bool, bool>(_setAppLock);
    unawaited(_loadLock());
  }

  final ProfileRepository _profiles;
  final SettingsRepository _settings;
  late final StreamSubscription<List<Profile>> _subscription;
  late final Command1<bool, bool> setAppLock;
  bool _lockAvailable = false;
  bool _lockEnabled = false;
  bool _canAddTile = false;

  List<Profile> get profiles => _profiles.profiles;
  bool get appLockAvailable => _lockAvailable;
  bool get appLockEnabled => _lockEnabled;

  Future<void> _loadLock() async {
    _lockAvailable = await _settings.appLockAvailable();
    _lockEnabled = await _settings.appLockEnabled();
    _canAddTile = await _settings.canAddTile();
    notifyListeners();
  }

  Future<Result<bool>> _setAppLock(bool enabled) async {
    final changed = await _settings.setAppLock(enabled);
    if (changed) _lockEnabled = enabled;
    notifyListeners();
    return Result.ok(changed);
  }

  void openVpnSettings() => unawaited(_settings.openVpnSettings());
  void addQuickSettingsTile() => unawaited(_settings.addQuickSettingsTile());
  bool get canAddTile => _canAddTile;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    setAppLock.dispose();
    super.dispose();
  }
}

/// Edits one connection. Every change is saved right away.
class ProfileEditorViewModel extends ChangeNotifier {
  ProfileEditorViewModel({required this._profiles, required this.profileId}) {
    _subscription = _profiles.changes.listen((_) => notifyListeners());
    save = Command1<Profile, Profile>(_profiles.save);
    delete = Command0<void>(() => _profiles.delete(profileId));
    removeEmailOtp = Command0<void>(() async {
      await _profiles.removeEmailOtp(profileId);
      return const Result.ok(null);
    });
  }

  final ProfileRepository _profiles;
  final String profileId;
  late final StreamSubscription<List<Profile>> _subscription;

  late final Command1<Profile, Profile> save;
  late final Command0<void> delete;
  late final Command0<void> removeEmailOtp;

  Profile? get profile => _profiles.byId(profileId);

  Future<void> update(Profile Function(Profile) change) async {
    final p = profile;
    if (p != null) await save.execute(change(p));
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    for (final c in [save, delete, removeEmailOtp]) {
      c.dispose();
    }
    super.dispose();
  }
}

/// Sets or replaces a connection's VPN password.
class PasswordFormViewModel extends ChangeNotifier {
  PasswordFormViewModel({required this._profiles, required this.profile}) {
    save = Command1<Profile, String>((password) => _profiles.save(profile, password: password));
  }

  final ProfileRepository _profiles;
  final Profile profile;
  late final Command1<Profile, String> save;

  @override
  void dispose() {
    save.dispose();
    super.dispose();
  }
}

/// Sets up reading codes from a mailbox; checks the login before saving.
class EmailOtpFormViewModel extends ChangeNotifier {
  EmailOtpFormViewModel({required this._profiles, required this.profileId}) {
    save = Command1<void, ({EmailOtpSource source, String password})>(
      (form) => _profiles.saveEmailOtp(profileId, form.source, form.password),
    );
  }

  final ProfileRepository _profiles;
  final String profileId;
  late final Command1<void, ({EmailOtpSource source, String password})> save;

  EmailOtpSource? get current => _profiles.byId(profileId)?.emailOtp;

  VpnErrorCode? get error => switch (save.result) {
    Error(error: EmailPasswordRejected(:final code)) => code,
    Error() => VpnErrorCode.emailUnreachable,
    _ => null,
  };

  void clearError() {
    if (save.result is Error) save.clearResult();
  }

  @override
  void dispose() {
    save.dispose();
    super.dispose();
  }
}

class ActivityLogViewModel extends ChangeNotifier {
  ActivityLogViewModel({required VpnRepository vpn}) : _vpn = vpn, _entries = vpn.log {
    _subscription = vpn.logChanges.listen((entries) {
      _entries = entries;
      notifyListeners();
    });
  }

  final VpnRepository _vpn;
  late final StreamSubscription<List<LogEntry>> _subscription;
  List<LogEntry> _entries;

  /// Hands the log to another app (email, chat) to send to IT.
  Future<void> share(String subject) => _vpn.share(subject, asText);

  /// Newest first.
  List<LogEntry> get entries => _entries.reversed.toList();

  /// Plain text for copying into a support message. The engine never logs secrets.
  String get asText => [
    for (final e in _entries)
      '${e.time.toIso8601String().substring(11, 19)}  ${e.level.name.toUpperCase()}  ${e.message}',
  ].join('\n');

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
