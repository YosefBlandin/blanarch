import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/vpn_repository.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/setup_link.dart';
import '../../utils/command.dart';
import '../../utils/result.dart';

enum AppStage { splash, onboarding, home }

/// App-wide state: theme choice and which top-level stage is showing.
class AppViewModel extends ChangeNotifier {
  AppViewModel({required this._settings, required this._profiles, required this._vpn}) {
    setTheme = Command1<void, ThemePreference>(_setTheme);
  }

  final SettingsRepository _settings;
  final ProfileRepository _profiles;
  final VpnRepository _vpn;

  late final Command1<void, ThemePreference> setTheme;

  ThemePreference _theme = ThemePreference.system;
  SetupLink? _pendingLink;
  StreamSubscription<SetupLink>? _links;
  AppStage _stage = AppStage.splash;
  AppStage? _afterSplash;
  bool _splashDone = false;
  bool _connectOnArrival = false;

  ThemePreference get theme => _theme;
  AppStage get stage => _stage;

  /// A setup link waiting to be used (the app was opened with it, or it arrived later).
  SetupLink? get pendingLink => _pendingLink;

  /// Hands the pending link to whoever opens the setup flow.
  SetupLink? takePendingLink() {
    final link = _pendingLink;
    _pendingLink = null;
    return link;
  }

  ThemeMode get themeMode => switch (_theme) {
    ThemePreference.system => ThemeMode.system,
    ThemePreference.light => ThemeMode.light,
    ThemePreference.dark => ThemeMode.dark,
  };

  /// Loads preferences while the splash plays; the wizard shows until setup is done.
  Future<void> load() async {
    final prefs = await _settings.load();
    await _profiles.load();
    await _vpn.load();
    _pendingLink = await _settings.takeSetupLink();
    _links = _settings.setupLinks.listen((link) {
      _pendingLink = link;
      notifyListeners();
    });
    _theme = prefs.theme;
    final ready = prefs.onboarded && _profiles.profiles.isNotEmpty;
    _afterSplash = ready ? AppStage.home : AppStage.onboarding;
    notifyListeners();
    _advance();
  }

  void splashFinished() {
    _splashDone = true;
    _advance();
  }

  /// True once, right after first-run setup: home starts the first connection.
  bool takeConnectOnArrival() {
    final connect = _connectOnArrival;
    _connectOnArrival = false;
    return connect;
  }

  void onboardingFinished() {
    _pendingLink = null;
    _connectOnArrival = true;
    _stage = AppStage.home;
    notifyListeners();
  }

  void _advance() {
    if (!_splashDone || _afterSplash == null) return;
    _stage = _afterSplash!;
    notifyListeners();
  }

  Future<Result<void>> _setTheme(ThemePreference theme) async {
    _theme = theme;
    notifyListeners();
    await _settings.setTheme(theme);
    return const Result.ok(null);
  }

  @override
  void dispose() {
    unawaited(_links?.cancel());
    setTheme.dispose();
    super.dispose();
  }
}
