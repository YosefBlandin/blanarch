import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/vpn_repository.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/setup_link.dart';
import '../../domain/models/vpn_status.dart';
import '../../utils/command.dart';
import '../../utils/result.dart';

enum SetupStep { welcome, address, unsupported, certificate, signIn, emailCode, permissions }

/// The server couldn't be checked; [probe] carries the reason.
class ProbeFailed implements Exception {
  const ProbeFailed(this.probe);
  final ProbeResult probe;
}

typedef SignInForm = ({String name, String username, String password, String realm});
typedef EmailForm = ({String account, String imapHost, String from, String password});

/// Adds one connection. On first run it also welcomes the user and asks for
/// permissions; from Settings it only covers the connection itself.
class SetupViewModel extends ChangeNotifier {
  SetupViewModel({
    required this._profiles,
    required this._settings,
    required this._vpn,
    required this.firstRun,
    this._link,
  }) : _step = firstRun ? SetupStep.welcome : SetupStep.address {
    probe = Command1<ProbeResult, String>(_probe);
    trust = Command0<void>(_trust);
    saveSignIn = Command1<Profile, SignInForm>(_saveSignIn);
    verifyEmail = Command1<void, EmailForm>(_verifyEmail);
    finish = Command0<String>(_finish);
    for (final c in [probe, trust, saveSignIn, verifyEmail, finish]) {
      c.addListener(notifyListeners);
    }
  }

  final ProfileRepository _profiles;
  final SettingsRepository _settings;
  final VpnRepository _vpn;
  final bool firstRun;

  late final Command1<ProbeResult, String> probe;
  late final Command0<void> trust;
  late final Command1<Profile, SignInForm> saveSignIn;
  late final Command1<void, EmailForm> verifyEmail;

  /// Completes with the new profile's id.
  late final Command0<String> finish;

  SetupStep _step;
  SetupLink? _link;
  bool _pinMismatch = false;
  List<String> _tried = const [];
  String? _checking;
  ProbeResult? _server;
  AuthMode _authMode = AuthMode.password;
  Profile? _saved;

  SetupStep get step => _step;
  ProbeResult? get server => _server;
  AuthMode get authMode => _authMode;
  Profile? get saved => _saved;

  /// The setup link (from a QR code or a tapped link) that prefilled this flow.
  SetupLink? get link => _link;

  /// The address being checked right now, so the screen can say which.
  String? get checkingAddress => _checking;

  /// Addresses the last server check tried, in order.
  List<String> get triedAddresses => _tried;

  /// The server's certificate differs from the fingerprint in the setup link.
  bool get pinMismatch => _pinMismatch;
  bool get busy => probe.running || trust.running || saveSignIn.running || verifyEmail.running || finish.running;

  /// The steps this run will show, for the progress bar.
  List<SetupStep> get steps => [
    if (firstRun) SetupStep.welcome,
    SetupStep.address,
    if (_server?.blocker != null) SetupStep.unsupported,
    if ((_server?.needsTrust ?? false) || _pinMismatch) SetupStep.certificate,
    SetupStep.signIn,
    if (_authMode == AuthMode.password) SetupStep.emailCode,
    if (firstRun) SetupStep.permissions,
  ];

  int get stepIndex => steps.indexOf(_step).clamp(0, steps.length - 1);

  /// Progress as the user sees it: server, account, and on first run welcome and
  /// permissions. The certificate and email steps sit inside those, so the total
  /// never changes halfway through.
  ({int step, int total}) get progress {
    final slots = [
      if (firstRun) [SetupStep.welcome],
      [SetupStep.address, SetupStep.unsupported, SetupStep.certificate],
      [SetupStep.signIn, SetupStep.emailCode],
      if (firstRun) [SetupStep.permissions],
    ];
    return (step: slots.indexWhere((s) => s.contains(_step)) + 1, total: slots.length);
  }

  bool get isLastStep => _step == steps.last;

  /// Why the address check failed, if it did.
  ProbeResult? get probeFailure => switch (probe.result) {
    Error(error: ProbeFailed(:final probe)) => probe,
    _ => null,
  };

  /// Why the mailbox refused, if it did.
  VpnErrorCode? get emailError => switch (verifyEmail.result) {
    Error(error: EmailPasswordRejected(:final code)) => code,
    Error() => VpnErrorCode.emailUnreachable,
    _ => null,
  };

  void start() {
    final link = _link;
    if (link != null) {
      unawaited(applyLink(link));
    } else {
      _go(SetupStep.address);
    }
  }

  /// Prefills from a scanned or tapped setup link and checks the server right away.
  Future<void> applyLink(SetupLink link) async {
    _link = link;
    if (_step == SetupStep.welcome) _step = SetupStep.address;
    notifyListeners();
    await probe.execute(link.address);
  }

  void setAuthMode(AuthMode mode) {
    _authMode = mode;
    notifyListeners();
  }

  /// Back one step; returns false when there is nothing before (the view closes).
  bool back() {
    if (busy || stepIndex == 0) return false;
    _go(steps[stepIndex - 1]);
    return true;
  }

  /// "Continue anyway" on the may-not-work page: go on to the certificate or sign-in step.
  void continueAnyway() => _go(_afterServerCheck());

  SetupStep _afterServerCheck() =>
      (_server?.needsTrust ?? false) || _pinMismatch ? SetupStep.certificate : SetupStep.signIn;

  /// "Don't connect" on the certificate step: start over with a different address.
  void rejectCertificate() {
    _server = null;
    _pinMismatch = false;
    _go(SetupStep.address);
  }

  Future<void> skipEmail() async {
    if (isLastStep) {
      await finish.execute();
    } else {
      _next();
    }
  }

  void clearErrors() {
    if (probe.result is Error) probe.clearResult();
    if (verifyEmail.result is Error) verifyEmail.clearResult();
  }

  void _go(SetupStep step) {
    _step = step;
    notifyListeners();
  }

  void _next() {
    final i = steps.indexOf(_step);
    if (i >= 0 && i < steps.length - 1) _go(steps[i + 1]);
  }

  /// Checks the server. With a setup link it tries the main address, then each backup,
  /// until one answers; the link's fingerprint is then trusted for all of them.
  Future<Result<ProbeResult>> _probe(String address) async {
    final link = _link;
    final fromLink = link != null && address.trim().toLowerCase() == link.address;
    final candidates = fromLink ? [for (final h in link.hosts) link.addressOf(h)] : [address];
    _tried = [];
    ProbeResult? r;
    for (final candidate in candidates) {
      _checking = candidate;
      notifyListeners();
      r = await _profiles.probe(candidate);
      _tried = [..._tried, candidate];
      if (r.ok || r.error != VpnErrorCode.gatewayUnreachable) break;
    }
    _checking = null;
    if (!r!.ok) return Result.error(ProbeFailed(r));
    _server = r;
    _authMode = link?.authMode ?? (r.ssoOffered ? AuthMode.sso : AuthMode.password);
    final expected = fromLink && link.hosts.contains(r.host) ? link.pinSha256 : '';
    _pinMismatch = expected.isNotEmpty && expected != r.certSha256;
    if (expected.isNotEmpty && !_pinMismatch && !r.pinned && !r.trustedBySystem) {
      // The link carried this exact fingerprint (from IT or a colleague): trust it for every
      // address in the link without asking, so failover to a backup works later.
      for (final h in link!.hosts) {
        await _profiles.trust(ProbeResult(host: h, port: r.port, certSha256: expected));
      }
      _server = ProbeResult(
        host: r.host,
        port: r.port,
        certSha256: r.certSha256,
        pinned: true,
        ssoOffered: r.ssoOffered,
      );
    }
    // Say plainly when this server may not work yet (spec §3.7) before asking for anything.
    _go(_server!.blocker != null ? SetupStep.unsupported : _afterServerCheck());
    return Result.ok(_server!);
  }

  Future<Result<void>> _trust() async {
    await _profiles.trust(_server!);
    _go(SetupStep.signIn);
    return const Result.ok(null);
  }

  Future<Result<Profile>> _saveSignIn(SignInForm form) async {
    final server = _server!;
    final draft = Profile(
      id: _saved?.id ?? '',
      name: [form.name.trim(), _link?.name ?? '', server.host].firstWhere((n) => n.isNotEmpty),
      // Keep the link's order (main first) so failover works; otherwise just the checked address.
      hosts: _link != null && _link!.hosts.contains(server.host) ? _link!.hosts : [server.host],
      port: server.port,
      realm: form.realm.trim().isNotEmpty ? form.realm.trim() : _link?.realm ?? '',
      authMode: _authMode,
      username: _authMode == AuthMode.password ? form.username.trim() : '',
    );
    final r = await _profiles.save(draft, password: _authMode == AuthMode.password ? form.password : null);
    if (r case Ok(:final value)) {
      _saved = value;
      if (isLastStep) {
        await finish.execute();
      } else {
        _next();
      }
    }
    return r;
  }

  Future<Result<void>> _verifyEmail(EmailForm form) async {
    final source = EmailOtpSource(account: form.account.trim(), imapHost: form.imapHost.trim(), from: form.from.trim());
    final r = await _profiles.saveEmailOtp(_saved!.id, source, form.password);
    if (r is Ok) {
      if (isLastStep) {
        await finish.execute();
      } else {
        _next();
      }
    }
    return r;
  }

  Future<Result<String>> _finish() async {
    final id = _saved!.id;
    if (firstRun) {
      await _vpn.requestPermissions();
      await _settings.setOnboarded(true);
    }
    await _settings.setActiveProfile(id);
    return Result.ok(id);
  }

  @override
  void dispose() {
    for (final c in [probe, trust, saveSignIn, verifyEmail, finish]) {
      c.dispose();
    }
    super.dispose();
  }
}
