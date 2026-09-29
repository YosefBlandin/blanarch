import 'package:blanarch/data/repositories/profile_repository.dart';
import 'package:blanarch/data/repositories/vpn_repository.dart';
import 'package:blanarch/domain/models/profile.dart';
import 'package:blanarch/domain/models/setup_link.dart';
import 'package:blanarch/domain/models/vpn_status.dart';
import 'package:blanarch/ui/app/app_view_model.dart';
import 'package:blanarch/ui/home/home_view_model.dart';
import 'package:blanarch/ui/settings/settings_view_model.dart';
import 'package:blanarch/ui/setup/setup_view_model.dart';
import 'package:blanarch/utils/command.dart';
import 'package:blanarch/utils/result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_vpn_platform.dart';

void main() {
  late FakeVpnPlatform platform;
  late VpnRepository vpn;
  late ProfileRepository profiles;
  late SettingsRepository settings;

  void wire(FakeVpnPlatform p) {
    platform = p;
    vpn = VpnRepository(platform);
    profiles = ProfileRepository(platform);
    settings = SettingsRepository(platform);
  }

  setUp(() => wire(FakeVpnPlatform()));
  tearDown(() {
    vpn.dispose();
    profiles.dispose();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);
  ToggleOutcome outcome(HomeViewModel vm) => (vm.toggle.result! as Ok<ToggleOutcome>).value;

  group('Command', () {
    test('tracks running and result, and ignores re-entry', () async {
      var runs = 0;
      final c = Command0<int>(() async {
        runs++;
        await Future<void>.delayed(Duration.zero);
        return const Result.ok(7);
      });
      final first = c.execute();
      expect(c.running, isTrue);
      await c.execute();
      await first;
      expect(runs, 1);
      expect((c.result! as Ok<int>).value, 7);
    });
  });

  group('Profile helpers', () {
    test('address hides the default port', () {
      expect(FakeVpnPlatform.lima.address, '198.51.100.18:4443');
      expect(FakeVpnPlatform.lima.copyWith(port: 443).address, '198.51.100.18');
    });

    test('IMAP server guesses', () {
      expect(EmailOtpSource.guessImapHost('ana@gmail.com'), 'imap.gmail.com');
      expect(EmailOtpSource.guessImapHost('ana@hotmail.com'), 'outlook.office365.com');
      expect(EmailOtpSource.guessImapHost('ana@example.co.uk'), 'mail.example.co.uk');
      expect(EmailOtpSource.guessImapHost('not-an-email'), '');
    });

    test('fingerprint is shown in groups of four', () {
      const p = ProbeResult(host: 'h', port: 1, certSha256: '7d2e41c09b8a5f6e');
      expect(p.fingerprintGroups, '7D2E 41C0 9B8A 5F6E');
    });
  });

  group('SetupLink', () {
    const pin = '7d2e41c09b8a5f6e3d1c0b9a8f7e6d5c4b3a29181706f5e4d3c2b1a098f7e6d5';

    test('round-trips a profile without passwords, username only on request', () {
      final p = FakeVpnPlatform.madrid.copyWith(realm: 'staff');
      final shared = SetupLink.fromProfile(
        Profile(
          id: p.id,
          name: p.name,
          hosts: p.hosts,
          port: p.port,
          realm: p.realm,
          username: 'ana',
          hasPassword: true,
          pinSha256: pin,
        ),
      );
      final back = SetupLink.parse(shared.toUri())!;
      expect(back.host, '203.0.113.46');
      expect(back.port, 10443);
      expect(back.name, 'Madrid');
      expect(back.realm, 'staff');
      expect(back.pinSha256, pin);
      expect(back.backups, ['203.0.113.42']);
      expect(back.username, '');
      expect(
        Uri.parse(shared.toUri()).queryParameters.keys,
        unorderedEquals(['host', 'port', 'alt', 'name', 'realm', 'auth', 'pin']),
      );
    });

    test('rejects other links and ignores a malformed pin', () {
      expect(SetupLink.parse('https://vpn.example.com'), isNull);
      expect(SetupLink.parse('blanarch://add?port=443'), isNull);
      expect(SetupLink.parse('blanarch://add?host=a%20b'), isNull);
      expect(SetupLink.parse('blanarch://add?host=vpn.example.com&pin=nothex')!.pinSha256, '');
      expect(SetupLink.parse('blanarch://add?host=VPN.example.com&auth=sso')!.authMode, AuthMode.sso);
    });
  });

  group('SetupViewModel', () {
    SetupViewModel setup({bool firstRun = false}) =>
        SetupViewModel(profiles: profiles, settings: settings, vpn: vpn, firstRun: firstRun);

    test('trusted server with password: address, sign-in, email, done', () async {
      final vm = setup();
      expect(vm.step, SetupStep.address);
      await vm.probe.execute('vpn.example.com:10443');
      expect(vm.step, SetupStep.signIn);
      expect(vm.steps, [SetupStep.address, SetupStep.signIn, SetupStep.emailCode]);

      await vm.saveSignIn.execute((name: '', username: 'ana', password: 'pw', realm: ''));
      expect(vm.saved!.name, 'vpn.example.com');
      expect(vm.saved!.port, 10443);
      expect(platform.passwords[vm.saved!.id], 'pw');
      expect(vm.step, SetupStep.emailCode);

      await vm.skipEmail();
      expect((vm.finish.result! as Ok<String>).value, vm.saved!.id);
      expect(platform.calls, contains('active:${vm.saved!.id}'));
    });

    test('a server without SSL-VPN gets a plain explanation first, and can still be continued', () async {
      platform.probeResult = const ProbeResult(
        host: 'vpn.example.com',
        port: 443,
        certSha256: 'aa',
        trustedBySystem: true,
        sslVpnPortal: false,
        ikeAnswers: true,
      );
      final vm = setup();
      await vm.probe.execute('vpn.example.com');
      expect(vm.step, SetupStep.unsupported);
      expect(vm.server!.blocker, VpnErrorCode.sslVpnOff);
      expect(vm.progress, (step: 1, total: 2)); // still the server slot
      vm.continueAnyway();
      expect(vm.step, SetupStep.signIn);
    });

    test('a client certificate request warns; "Try another address" goes back', () async {
      platform.probeResult = const ProbeResult(
        host: 'vpn.example.com',
        port: 443,
        certSha256: 'aa',
        trustedBySystem: true,
        clientCertRequested: true,
      );
      final vm = setup();
      await vm.probe.execute('vpn.example.com');
      expect(vm.server!.blocker, VpnErrorCode.clientCertRequired);
      vm.rejectCertificate();
      expect(vm.step, SetupStep.address);
    });

    test('untrusted certificate adds a step; "Don\'t connect" goes back to the address', () async {
      platform.probeResult = const ProbeResult(host: 'vpn.example.com', port: 443, certSha256: 'aa');
      final vm = setup();
      await vm.probe.execute('vpn.example.com');
      expect(vm.step, SetupStep.certificate);
      vm.rejectCertificate();
      expect(vm.step, SetupStep.address);
      expect(platform.calls.where((c) => c.startsWith('trust')), isEmpty);

      await vm.probe.execute('vpn.example.com');
      await vm.trust.execute();
      expect(platform.calls, contains('trust:vpn.example.com'));
      expect(vm.step, SetupStep.signIn);
    });

    test('a server offering SSO defaults to it and skips passwords and email', () async {
      platform.probeResult = const ProbeResult(
        host: 'sso.example.com',
        port: 443,
        trustedBySystem: true,
        ssoOffered: true,
      );
      final vm = setup();
      await vm.probe.execute('sso.example.com');
      expect(vm.authMode, AuthMode.sso);
      expect(vm.steps, isNot(contains(SetupStep.emailCode)));
      await vm.saveSignIn.execute((name: 'Corp', username: '', password: '', realm: ''));
      expect(vm.saved!.authMode, AuthMode.sso);
      expect(platform.passwords, isEmpty);
      expect(vm.finish.completed, isTrue);
    });

    test('unreachable server keeps the user on the address step with the reason', () async {
      platform.probeResult = const ProbeResult(host: 'x', port: 443, error: VpnErrorCode.gatewayUnreachable);
      final vm = setup();
      await vm.probe.execute('x');
      expect(vm.step, SetupStep.address);
      expect(vm.probeFailure?.error, VpnErrorCode.gatewayUnreachable);
    });

    test('a rejected mailbox password stays on the step', () async {
      platform.emailRejection = VpnErrorCode.emailAuthFailed;
      final vm = setup();
      await vm.probe.execute('vpn.example.com');
      await vm.saveSignIn.execute((name: '', username: 'ana', password: 'pw', realm: ''));
      await vm.verifyEmail.execute((account: 'ana@example.com', imapHost: 'mail.example.com', from: '', password: 'x'));
      expect(vm.step, SetupStep.emailCode);
      expect(vm.emailError, VpnErrorCode.emailAuthFailed);
    });

    test('a link with the matching fingerprint trusts the server without asking', () async {
      const pin = '7d2e41c09b8a5f6e3d1c0b9a8f7e6d5c4b3a29181706f5e4d3c2b1a098f7e6d5';
      platform.probeResult = const ProbeResult(host: 'vpn.example.com', port: 10443, certSha256: pin);
      final vm = setup();
      await vm.applyLink(SetupLink.parse('blanarch://add?host=vpn.example.com&port=10443&name=Corp&pin=$pin')!);
      expect(platform.calls, contains('trust:vpn.example.com'));
      expect(vm.step, SetupStep.signIn);
      await vm.saveSignIn.execute((name: '', username: 'ana', password: 'pw', realm: ''));
      expect(vm.saved!.name, 'Corp');
    });

    test('a link falls back to its backup addresses and trusts its fingerprint for all of them', () async {
      const pin = '7d2e41c09b8a5f6e3d1c0b9a8f7e6d5c4b3a29181706f5e4d3c2b1a098f7e6d5';
      platform
        ..unreachable = {'203.0.113.46:10443'}
        ..probeResult = const ProbeResult(host: '203.0.113.42', port: 10443, certSha256: pin);
      final link = SetupLink.parse(
        'blanarch://add?host=203.0.113.46&port=10443&alt=203.0.113.42,203.0.113.45&name=Madrid&pin=$pin',
      )!;
      expect(link.backups, ['203.0.113.42', '203.0.113.45']);
      final vm = setup();
      await vm.applyLink(link);
      expect(vm.triedAddresses, ['203.0.113.46:10443', '203.0.113.42:10443']);
      expect(vm.step, SetupStep.signIn);
      expect(platform.calls.where((c) => c.startsWith('trust:')), [
        'trust:203.0.113.46',
        'trust:203.0.113.42',
        'trust:203.0.113.45',
      ]);
      await vm.saveSignIn.execute((name: '', username: 'ana', password: 'pw', realm: ''));
      expect(vm.saved!.hosts, ['203.0.113.46', '203.0.113.42', '203.0.113.45']);
    });

    test('when no address answers, the error lists what was tried', () async {
      platform.unreachable = {'a.example.com', 'b.example.com'};
      final vm = setup();
      await vm.applyLink(SetupLink.parse('blanarch://add?host=a.example.com&alt=b.example.com')!);
      expect(vm.step, SetupStep.address);
      expect(vm.probeFailure?.error, VpnErrorCode.gatewayUnreachable);
      expect(vm.triedAddresses, ['a.example.com', 'b.example.com']);
    });

    test('a link whose fingerprint differs forces the warning step and trusts nothing', () async {
      platform.probeResult = const ProbeResult(
        host: 'vpn.example.com',
        port: 443,
        certSha256: 'aa',
        trustedBySystem: true,
      );
      final vm = setup();
      await vm.applyLink(SetupLink.parse('blanarch://add?host=vpn.example.com&pin=${'b' * 64}')!);
      expect(vm.step, SetupStep.certificate);
      expect(vm.pinMismatch, isTrue);
      expect(platform.calls.where((c) => c.startsWith('trust')), isEmpty);
    });

    test('first run asks for permissions and marks setup done', () async {
      final vm = setup(firstRun: true);
      expect(vm.step, SetupStep.welcome);
      vm.start();
      await vm.probe.execute('vpn.example.com');
      await vm.saveSignIn.execute((name: '', username: 'ana', password: 'pw', realm: ''));
      await vm.skipEmail();
      expect(vm.step, SetupStep.permissions);
      await vm.finish.execute();
      expect(platform.calls, containsAll(['requestNotifications', 'prepareVpn', 'onboarded:true']));
    });
  });

  group('HomeViewModel', () {
    HomeViewModel home() => HomeViewModel(vpn: vpn, profiles: profiles, settings: settings);

    test('connects the saved active profile', () async {
      platform.prefsValue = const AppPrefs(onboarded: true, activeProfileId: 'madrid');
      final vm = home();
      await settle();
      expect(vm.selectedId, 'madrid');
      await vm.toggle.execute();
      expect(platform.calls, contains('connect:madrid'));
      expect(outcome(vm), ToggleOutcome.started);
    });

    test('no profiles asks for setup; a profile without password asks for it', () async {
      wire(FakeVpnPlatform(profiles: []));
      final empty = home();
      await settle();
      await empty.toggle.execute();
      expect(outcome(empty), ToggleOutcome.needsSetup);

      wire(FakeVpnPlatform(profiles: [FakeVpnPlatform.lima.copyWith(), _noPassword]));
      final vm = home();
      await settle();
      vm.select('np');
      await vm.toggle.execute();
      expect(outcome(vm), ToggleOutcome.needsPassword);
    });

    test('closing the unlock prompt is reported, and nothing connects', () async {
      platform
        ..lockEnabled = true
        ..unlock = false;
      final vm = home();
      await settle();
      await vm.toggle.execute();
      expect(outcome(vm), ToggleOutcome.unlockCancelled);
      expect(platform.calls.where((c) => c.startsWith('connect')), isEmpty);
    });

    test('the tile is offered through the engine', () async {
      home().offerQuickSettingsTile();
      await settle();
      expect(platform.calls, contains('tile'));
    });

    test('a declined VPN permission is reported', () async {
      platform.grantVpn = false;
      final vm = home();
      await settle();
      await vm.toggle.execute();
      expect(outcome(vm), ToggleOutcome.permissionDenied);
    });

    test('while active the site is locked and tapping disconnects', () async {
      final vm = home();
      await settle();
      platform.emit(const VpnStatus(phase: VpnPhase.connected, profileId: 'lima'));
      await settle();
      expect(vm.canChangeSite, isFalse);
      vm.select('madrid');
      expect(vm.selectedId, 'lima');
      await vm.toggle.execute();
      expect(platform.calls, contains('disconnect'));
    });

    test('the live feed shows this run\'s translatable steps, newest first', () async {
      final start = DateTime(2026, 9, 27, 17, 42);
      platform.logList = [
        LogEntry(
          time: start.subtract(const Duration(minutes: 5)),
          level: LogLevel.ok,
          message: '',
          event: LogEvent.connected,
        ),
        LogEntry(time: start, level: LogLevel.info, message: '', event: LogEvent.starting, args: const ['Madrid']),
        LogEntry(time: start.add(const Duration(seconds: 1)), level: LogLevel.info, message: 'PPP up'),
        LogEntry(
          time: start.add(const Duration(seconds: 2)),
          level: LogLevel.info,
          message: '',
          event: LogEvent.attempt,
        ),
      ];
      await vpn.load();
      final vm = home();
      await settle();
      platform.emit(VpnStatus(phase: VpnPhase.connecting, profileId: 'madrid', startedAt: start));
      await settle();
      expect(vm.recentActivity().map((e) => e.event), [LogEvent.attempt, LogEvent.starting]);
    });

    test('coming back from a network change is remembered for the connected screen', () async {
      final vm = home();
      await settle();
      platform.emit(const VpnStatus(phase: VpnPhase.connected, profileId: 'lima'));
      await settle();
      expect(vm.lastRejoin, isNull);
      platform.emit(
        const VpnStatus(phase: VpnPhase.reconnecting, profileId: 'lima', retryReason: VpnErrorCode.networkChanged),
      );
      await settle();
      platform.emit(const VpnStatus(phase: VpnPhase.connected, profileId: 'lima'));
      await settle();
      expect(vm.lastRejoin?.reason, VpnErrorCode.networkChanged);
      platform.emit(const VpnStatus());
      await settle();
      expect(vm.lastRejoin, isNull);
    });

    test('the SSO page opens once per request', () async {
      final vm = home();
      await settle();
      platform.emit(const VpnStatus(phase: VpnPhase.waitingSso, profileId: 'lima', ssoUrl: 'https://h/sso'));
      await settle();
      await vm.openSsoOnce();
      await vm.openSsoOnce();
      expect(platform.calls.where((c) => c.startsWith('sso:')), ['sso:https://h/sso']);
    });

    test('"Use a code instead" restarts this sign-in only and keeps the saved setting', () async {
      final vm = home();
      await settle();
      platform.emit(const VpnStatus(phase: VpnPhase.waitingPush, profileId: 'lima'));
      await settle();
      await vm.useCodeInstead.execute();
      expect(platform.calls, contains('useCode'));
      expect(platform.calls.where((c) => c.startsWith('save:')), isEmpty);
      expect(profiles.byId('lima')!.secondFactor, SecondFactorPreference.auto);
    });
  });

  group('SettingsViewModel', () {
    test('turning the lock on needs a successful unlock', () async {
      final vm = SettingsViewModel(profiles: profiles, settings: settings);
      await settle();
      expect(vm.appLockAvailable, isTrue);
      platform.unlock = false;
      await vm.setAppLock.execute(true);
      expect(vm.appLockEnabled, isFalse);
      platform.unlock = true;
      await vm.setAppLock.execute(true);
      expect(vm.appLockEnabled, isTrue);
      expect(platform.calls, contains('lock:true'));
    });
  });

  group('AppViewModel', () {
    test('first run goes to setup after the splash, not before', () async {
      wire(FakeVpnPlatform(profiles: [], prefsValue: const AppPrefs()));
      final vm = AppViewModel(settings: settings, profiles: profiles, vpn: vpn);
      await vm.load();
      expect(vm.stage, AppStage.splash);
      vm.splashFinished();
      expect(vm.stage, AppStage.onboarding);
    });

    test('a setup link the app was opened with, or that arrives later, is waiting for the setup flow', () async {
      platform.pendingLink = 'blanarch://add?host=vpn.example.com';
      final vm = AppViewModel(settings: settings, profiles: profiles, vpn: vpn);
      await vm.load();
      expect(vm.takePendingLink()!.host, 'vpn.example.com');
      expect(vm.pendingLink, isNull);
      platform.sendLink('blanarch://add?host=other.example.com&port=8443');
      await settle();
      expect(vm.pendingLink!.address, 'other.example.com:8443');
    });

    test('with a profile the app goes home, and the theme choice is saved', () async {
      final vm = AppViewModel(settings: settings, profiles: profiles, vpn: vpn)..splashFinished();
      await vm.load();
      expect(vm.stage, AppStage.home);
      await vm.setTheme.execute(ThemePreference.dark);
      expect(platform.calls, contains('theme:dark'));
    });
  });
}

const _noPassword = Profile(id: 'np', name: 'New', hosts: ['vpn.example.com'], port: 443, username: 'ana');
