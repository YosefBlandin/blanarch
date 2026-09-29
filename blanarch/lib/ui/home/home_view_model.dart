import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/vpn_repository.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/vpn_status.dart';
import '../../utils/command.dart';
import '../../utils/result.dart';

/// What happened when the user tapped the big button.
enum ToggleOutcome { started, stopped, needsSetup, needsPassword, permissionDenied, unlockCancelled }

class HomeViewModel extends ChangeNotifier {
  /// [connectOnStart] starts the first connection as soon as the profiles are loaded
  /// (right after first-run setup, so the wizard ends with the VPN coming up).
  HomeViewModel({
    required VpnRepository vpn,
    required this._profiles,
    required this._settings,
    this._connectOnStart = false,
    this._clock = DateTime.now,
  }) : _vpn = vpn,
       _status = vpn.status,
       _log = vpn.log {
    _subscriptions = [
      _vpn.statusChanges.listen(_onStatus),
      _vpn.logChanges.listen(_onLog),
      _profiles.changes.listen((_) => _fixSelection()),
    ];
    load = Command0<void>(_load)..execute();
    toggle = Command0<ToggleOutcome>(_toggle);
    submitOtp = Command1<void, String>((code) => _vpn.submitOtp(code.trim()));
    openSso = Command0<void>(_openSso);
    useCodeInstead = Command0<void>(_useCodeInstead);
    probeSelected = Command0<ProbeResult>(_probeSelected);
    trust = Command1<void, ProbeResult>(_trust);
  }

  final VpnRepository _vpn;
  final ProfileRepository _profiles;
  final SettingsRepository _settings;
  bool _connectOnStart;
  late final List<StreamSubscription<Object?>> _subscriptions;

  late final Command0<void> load;
  late final Command0<ToggleOutcome> toggle;
  late final Command1<void, String> submitOtp;
  late final Command0<void> openSso;
  late final Command0<void> useCodeInstead;

  /// Re-checks the selected server's certificate (after a certificate error).
  late final Command0<ProbeResult> probeSelected;
  late final Command1<void, ProbeResult> trust;

  VpnStatus _status;
  final DateTime Function() _clock;
  ({VpnErrorCode reason, DateTime at})? _lastRejoin;

  /// Why and when the tunnel last came back after a drop, for a short note on the connected screen.
  ({VpnErrorCode reason, DateTime at})? get lastRejoin => _lastRejoin;
  List<LogEntry> _log;
  String? _selectedId;
  String? _openedSsoUrl;

  VpnStatus get status => _status;
  List<Profile> get profiles => _profiles.profiles;
  Profile? get selected => _profiles.byId(_selectedId) ?? profiles.firstOrNull;
  String? get selectedId => selected?.id;
  bool get canChangeSite => !_status.active;

  /// The main steps of the current attempt run, newest first, for the live feed
  /// under the progress card. Only translatable events: raw engine lines stay in
  /// the Activity log.
  List<LogEntry> recentActivity({int max = 5}) {
    final since = _status.startedAt?.subtract(const Duration(seconds: 1));
    return [
      for (final e in _log.reversed)
        if (e.event != null && (since == null || !e.time.isBefore(since))) e,
    ].take(max).toList();
  }

  void _onLog(List<LogEntry> entries) {
    _log = entries;
    if (_status.busy) notifyListeners();
  }

  void _onStatus(VpnStatus s) {
    final rejoining = const {VpnPhase.reconnecting, VpnPhase.waitingNetwork}.contains(_status.phase);
    if (s.phase == VpnPhase.connected && rejoining) {
      _lastRejoin = (reason: _status.retryReason ?? VpnErrorCode.linkLost, at: _clock());
    }
    if (!s.active) _lastRejoin = null;
    _status = s;
    if (s.active && s.profileId != null) _selectedId = s.profileId;
    if (s.phase != VpnPhase.waitingSso) _openedSsoUrl = null;
    notifyListeners();
  }

  void _fixSelection() {
    if (_profiles.byId(_selectedId) == null) _selectedId = profiles.firstOrNull?.id;
    notifyListeners();
  }

  Future<Result<void>> _load() async {
    await _profiles.load();
    final prefs = await _settings.load();
    _selectedId = _status.active ? _status.profileId : prefs.activeProfileId;
    _fixSelection();
    if (_connectOnStart && !_status.active && selected != null) {
      _connectOnStart = false;
      unawaited(toggle.execute());
    }
    return const Result.ok(null);
  }

  void select(String id) {
    if (!canChangeSite || id == _selectedId) return;
    _selectedId = id;
    notifyListeners();
    unawaited(_settings.setActiveProfile(id));
  }

  Future<Result<ToggleOutcome>> _toggle() async {
    if (_status.phase == VpnPhase.disconnecting) return const Result.ok(ToggleOutcome.stopped);
    if (_status.active) {
      return switch (await _vpn.disconnect()) {
        Ok() => const Result.ok(ToggleOutcome.stopped),
        Error(:final error) => Result.error(error),
      };
    }
    final profile = selected;
    if (profile == null) return const Result.ok(ToggleOutcome.needsSetup);
    if (!profile.ready) return const Result.ok(ToggleOutcome.needsPassword);
    return switch (await _vpn.connect(profile.id)) {
      Ok() => const Result.ok(ToggleOutcome.started),
      Error(error: VpnPermissionDenied()) => const Result.ok(ToggleOutcome.permissionDenied),
      Error(error: UnlockCancelled()) => const Result.ok(ToggleOutcome.unlockCancelled),
      Error(:final error) => Result.error(error),
    };
  }

  /// After the first successful connection, Android 13+ offers to add the tile (asked only once).
  void offerQuickSettingsTile() => unawaited(_settings.offerQuickSettingsTile());

  /// Opens the sign-in page once per request; the button can open it again.
  Future<void> openSsoOnce() async {
    final url = _status.ssoUrl;
    if (_status.phase != VpnPhase.waitingSso || url == null || url == _openedSsoUrl) return;
    _openedSsoUrl = url;
    await openSso.execute();
  }

  Future<Result<void>> _openSso() async {
    final url = _status.ssoUrl;
    if (url == null) return const Result.ok(null);
    return _vpn.openSso(url);
  }

  /// Hands the connection details to another app (email, chat) for IT.
  Future<void> shareDetails(String subject, String text) async => _vpn.share(subject, text);

  /// Restarts this sign-in with a code. The saved connection keeps its push setting.
  Future<Result<void>> _useCodeInstead() => _vpn.useCodeThisTime();

  Future<Result<ProbeResult>> _probeSelected() async {
    final profile = selected;
    if (profile == null) return Result.error(Exception('no profile'));
    return Result.ok(await _profiles.probe(profile.address));
  }

  Future<Result<void>> _trust(ProbeResult probe) async {
    await _profiles.trust(probe);
    return const Result.ok(null);
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    for (final c in [load, toggle, submitOtp, openSso, useCodeInstead, probeSelected, trust]) {
      c.dispose();
    }
    super.dispose();
  }
}
