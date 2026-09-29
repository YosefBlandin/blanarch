import 'dart:async';
import 'dart:collection';

import '../../domain/models/vpn_status.dart';
import '../../utils/result.dart';
import '../services/vpn_platform.dart';

class VpnPermissionDenied implements Exception {
  const VpnPermissionDenied();
}

/// The app lock is on and the user closed the fingerprint/face/PIN prompt.
class UnlockCancelled implements Exception {
  const UnlockCancelled();
}

/// Source of truth for connection status, the activity log, and VPN actions.
class VpnRepository {
  VpnRepository(this._platform) {
    _subscriptions = [
      _platform.statusChanges.listen((s) {
        _status = s;
        _statusOut.add(s);
      }),
      _platform.logEntries.listen((e) {
        _log.add(e);
        while (_log.length > _logCapacity) {
          _log.removeFirst();
        }
        _logOut.add(log);
      }),
    ];
  }

  static const _logCapacity = 200;

  final VpnPlatform _platform;
  late final List<StreamSubscription<Object?>> _subscriptions;
  final _statusOut = StreamController<VpnStatus>.broadcast();
  final _logOut = StreamController<List<LogEntry>>.broadcast();
  final _log = Queue<LogEntry>();
  VpnStatus _status = const VpnStatus();

  VpnStatus get status => _status;
  Stream<VpnStatus> get statusChanges => _statusOut.stream;
  List<LogEntry> get log => List.unmodifiable(_log);
  Stream<List<LogEntry>> get logChanges => _logOut.stream;

  /// Loads the engine's current state (the service may already be running).
  Future<void> load() async {
    _status = await _platform.status();
    _log
      ..clear()
      ..addAll(await _platform.log());
    _statusOut.add(_status);
    _logOut.add(log);
  }

  Future<Result<void>> connect(String profileId) async {
    try {
      return switch (await _platform.connect(profileId)) {
        ConnectResult.started => const Result.ok(null),
        ConnectResult.vpnDenied => const Result.error(VpnPermissionDenied()),
        ConnectResult.unlockCancelled => const Result.error(UnlockCancelled()),
      };
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  Future<Result<void>> disconnect() => _guard(_platform.disconnect);
  Future<Result<void>> useCodeThisTime() => _guard(_platform.useCodeThisTime);
  Future<Result<void>> share(String subject, String text) => _guard(() => _platform.shareText(subject, text));
  Future<Result<void>> submitOtp(String code) => _guard(() => _platform.submitOtp(code));
  Future<Result<void>> openSso(String url) => _guard(() => _platform.openSso(url));

  Future<Result<bool>> requestPermissions() async {
    try {
      await _platform.requestNotifications();
      return Result.ok(await _platform.prepareVpn());
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  Future<Result<void>> _guard(Future<void> Function() action) async {
    try {
      await action();
      return const Result.ok(null);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  void dispose() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(_statusOut.close());
    unawaited(_logOut.close());
  }
}
