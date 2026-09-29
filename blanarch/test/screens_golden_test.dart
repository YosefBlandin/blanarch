import 'dart:io';

import 'package:blanarch/config/dependencies.dart';
import 'package:blanarch/data/repositories/profile_repository.dart';
import 'package:blanarch/data/repositories/vpn_repository.dart';
import 'package:blanarch/domain/models/profile.dart';
import 'package:blanarch/domain/models/setup_link.dart';
import 'package:blanarch/domain/models/vpn_status.dart';
import 'package:blanarch/ui/core/l10n/l10n.dart';
import 'package:blanarch/ui/core/theme/theme.dart';
import 'package:blanarch/ui/home/home_screen.dart';
import 'package:blanarch/ui/home/home_view_model.dart';
import 'package:blanarch/ui/settings/profile_editor_screen.dart';
import 'package:blanarch/ui/settings/settings_screen.dart';
import 'package:blanarch/ui/settings/share_setup_sheet.dart';
import 'package:blanarch/ui/setup/setup_screen.dart';
import 'package:blanarch/ui/setup/setup_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fake_vpn_platform.dart';

/// Visual regression guard. Regenerate only for intended UI changes:
///   flutter test --update-goldens test/screens_golden_test.dart
Future<void> _loadFonts() async {
  Future<ByteData> asset(String p) => rootBundle.load(p);
  await (FontLoader('Inter')
        ..addFont(asset('assets/fonts/Inter-Regular.ttf'))
        ..addFont(asset('assets/fonts/Inter-Medium.ttf'))
        ..addFont(asset('assets/fonts/Inter-SemiBold.ttf')))
      .load();
  await (FontLoader('InstrumentSerif')
        ..addFont(asset('assets/fonts/InstrumentSerif-Regular.ttf'))
        ..addFont(asset('assets/fonts/InstrumentSerif-Italic.ttf')))
      .load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter';
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync();
  await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.buffer)))).load();
}

void main() {
  setUpAll(_loadFonts);

  final now = DateTime(2026, 9, 24, 17, 30);
  final since = now.subtract(const Duration(seconds: 754));

  Future<void> shot(
    WidgetTester t,
    String name,
    Widget Function(BuildContext) screen, {
    FakeVpnPlatform? platform,
    bool dark = false,
    Locale locale = const Locale('en'),
    Future<void> Function(BuildContext)? prepare,
    Future<void> Function(WidgetTester)? interact,
  }) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    final p = platform ?? FakeVpnPlatform();
    await t.pumpWidget(
      MultiProvider(
        providers: providers(p),
        child: Builder(
          builder: (context) => FutureBuilder(
            future: () async {
              await context.read<VpnRepository>().load();
              await context.read<ProfileRepository>().load();
              await prepare?.call(context);
            }(),
            builder: (context, snap) => snap.connectionState != ConnectionState.done
                ? const SizedBox()
                : MaterialApp(
                    debugShowCheckedModeBanner: false,
                    locale: locale,
                    localizationsDelegates: AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    theme: buildTheme(dark ? Brand.dark : Brand.light, dark ? Brightness.dark : Brightness.light),
                    // Freeze ambient animations so screenshots are stable.
                    builder: (context, child) =>
                        MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
                    home: Builder(builder: screen),
                  ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 130));
    }
    if (interact != null) {
      await interact(t);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 130));
      }
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
    await t.pumpWidget(const SizedBox());
  }

  Widget home(BuildContext c) => ChangeNotifierProvider(
    create: (c) => HomeViewModel(vpn: c.read(), profiles: c.read(), settings: c.read()),
    child: Builder(
      builder: (c) => HomeScreen(viewModel: c.read(), clock: () => now),
    ),
  );

  FakeVpnPlatform withStatus(VpnStatus s, {List<Profile>? profiles}) =>
      FakeVpnPlatform(currentStatus: s, profiles: profiles);

  // Setup is rendered at a chosen step by driving its view-model first.
  SetupViewModel? setupVm;
  Widget setup(BuildContext c) => ChangeNotifierProvider.value(
    value: setupVm!,
    child: SetupScreen(viewModel: setupVm!, onDone: (_) {}),
  );
  Future<void> Function(BuildContext) setupAt(Future<void> Function(SetupViewModel) drive, {bool firstRun = false}) =>
      (c) async {
        setupVm = SetupViewModel(profiles: c.read(), settings: c.read(), vpn: c.read(), firstRun: firstRun);
        await drive(setupVm!);
      };

  group('home', () {
    testWidgets('idle', (t) => shot(t, 'home_idle_light', home));
    testWidgets('empty', (t) => shot(t, 'home_empty_light', home, platform: FakeVpnPlatform(profiles: [])));
    testWidgets(
      'waiting for code',
      (t) => shot(
        t,
        'home_otp_light',
        home,
        platform: withStatus(
          VpnStatus(
            phase: VpnPhase.waitingOtp,
            profileId: 'lima',
            host: '198.51.100.18',
            emailWatching: true,
            deadline: now.add(const Duration(seconds: 58)),
          ),
        ),
      ),
    );
    FakeVpnPlatform retrying() {
      final p = withStatus(
        VpnStatus(
          phase: VpnPhase.connecting,
          profileId: 'madrid',
          host: '203.0.113.45',
          attempt: 3,
          maxAttempts: 10,
          startedAt: now.subtract(const Duration(seconds: 41)),
          retryReason: VpnErrorCode.gatewayUnreachable,
        ),
      );
      DateTime at(int s) => now.subtract(Duration(seconds: s));
      p.logList = [
        LogEntry(time: at(41), level: LogLevel.info, message: '', event: LogEvent.starting, args: const ['Madrid']),
        LogEntry(
          time: at(40),
          level: LogLevel.info,
          message: '',
          event: LogEvent.attempt,
          args: const ['1', '10', '203.0.113.46:10443'],
        ),
        LogEntry(
          time: at(30),
          level: LogLevel.error,
          message: '',
          event: LogEvent.failed,
          args: const ['GATEWAY_UNREACHABLE', '203.0.113.46'],
        ),
        LogEntry(
          time: at(27),
          level: LogLevel.info,
          message: '',
          event: LogEvent.attempt,
          args: const ['2', '10', '203.0.113.42:10443'],
        ),
        LogEntry(
          time: at(17),
          level: LogLevel.error,
          message: '',
          event: LogEvent.failed,
          args: const ['GATEWAY_UNREACHABLE', '203.0.113.42'],
        ),
        LogEntry(time: at(14), level: LogLevel.info, message: 'Tunnel connection open'),
        LogEntry(
          time: at(3),
          level: LogLevel.info,
          message: '',
          event: LogEvent.attempt,
          args: const ['3', '10', '203.0.113.45:10443'],
        ),
      ];
      return p;
    }

    testWidgets(
      'connecting, retrying a backup address',
      (t) => shot(t, 'home_connecting_retry_light', home, platform: retrying()),
    );
    testWidgets(
      'connecting, retrying, spanish',
      (t) => shot(t, 'home_connecting_es', home, platform: retrying(), locale: const Locale('es')),
    );
    testWidgets(
      'typing the code by choice',
      (t) => shot(
        t,
        'home_otp_manual_light',
        home,
        platform: withStatus(
          VpnStatus(
            phase: VpnPhase.waitingOtp,
            profileId: 'lima',
            host: '198.51.100.18',
            emailIssue: VpnErrorCode.emailNotConfigured,
            deadline: now.add(const Duration(seconds: 12)),
          ),
        ),
      ),
    );
    testWidgets(
      'waiting for push',
      (t) => shot(
        t,
        'home_push_light',
        home,
        platform: withStatus(const VpnStatus(phase: VpnPhase.waitingPush, profileId: 'lima')),
      ),
    );
    testWidgets(
      'waiting for sso, spanish',
      (t) => shot(
        t,
        'home_sso_es',
        home,
        locale: const Locale('es'),
        platform: withStatus(const VpnStatus(phase: VpnPhase.waitingSso, profileId: 'lima', ssoUrl: 'https://x')),
      ),
    );
    VpnStatus connectedMadrid() => VpnStatus(
      phase: VpnPhase.connected,
      profileId: 'madrid',
      host: '203.0.113.42',
      port: 10443,
      ip: '10.212.134.7',
      connectedSince: since,
      bytesIn: 13002342,
      bytesOut: 1153433,
      latency: const Duration(milliseconds: 38),
      dns: const ['10.0.0.53', '10.0.0.54'],
      dnsSuffix: 'corp.example',
      routes: const ['10.0.0.0/8', '172.16.20.0/24', '192.168.50.0/24'],
      mtu: 1354,
      tls: 'TLSv1.3 · TLS_AES_256_GCM_SHA384',
      signIn: SignInMethod.code,
      triedHosts: const ['203.0.113.46', '203.0.113.42'],
      certSha256: '7d2e41c09b8a5f6e3d1c0b9a8f7e6d5c4b3a29181706f5e4d3c2b1a098f7e6d5',
    );
    testWidgets(
      'waiting for a network',
      (t) => shot(
        t,
        'home_waiting_network_light',
        home,
        platform: withStatus(
          VpnStatus(
            phase: VpnPhase.waitingNetwork,
            profileId: 'madrid',
            host: '203.0.113.42',
            attempt: 1,
            maxAttempts: 10,
            startedAt: now.subtract(const Duration(seconds: 9)),
            retryReason: VpnErrorCode.noNetwork,
          ),
        ),
      ),
    );
    testWidgets('connected again after a network change', (t) {
      final p = withStatus(
        const VpnStatus(phase: VpnPhase.reconnecting, profileId: 'madrid', retryReason: VpnErrorCode.networkChanged),
      );
      return shot(t, 'home_reconnected_light', home, platform: p, interact: (t) async => p.emit(connectedMadrid()));
    });
    testWidgets(
      'connected light',
      (t) => shot(t, 'home_connected_light', home, platform: withStatus(connectedMadrid())),
    );
    testWidgets(
      'connection details sheet',
      (t) => shot(
        t,
        'home_connection_details_light',
        home,
        platform: withStatus(connectedMadrid()),
        interact: (t) => t.tap(find.text('All details')),
      ),
    );
    testWidgets(
      'connected dark, single profile',
      (t) => shot(
        t,
        'home_connected_dark',
        home,
        dark: true,
        platform: withStatus(
          VpnStatus(
            phase: VpnPhase.connected,
            profileId: 'madrid',
            host: '203.0.113.42',
            ip: '10.212.134.7',
            connectedSince: since,
          ),
          profiles: [FakeVpnPlatform.madrid],
        ),
      ),
    );
    testWidgets(
      'error with details sheet',
      (t) => shot(
        t,
        'home_error_sheet_dark',
        home,
        dark: true,
        platform: withStatus(
          const VpnStatus(
            phase: VpnPhase.error,
            profileId: 'lima',
            error: VpnErrorCode.authRejected,
            errorDetail: 'ret=0',
          ),
        ),
        interact: (t) => t.tap(find.byIcon(Icons.info_outline_rounded)),
      ),
    );
  });

  group('setup', () {
    testWidgets(
      'welcome',
      (t) => shot(t, 'setup_welcome_light', setup, prepare: setupAt((_) async {}, firstRun: true)),
    );
    testWidgets('address', (t) => shot(t, 'setup_address_light', setup, prepare: setupAt((_) async {})));
    testWidgets(
      'server without SSL-VPN that answers IPsec',
      (t) => shot(
        t,
        'setup_unsupported_light',
        setup,
        platform: FakeVpnPlatform(
          probeResult: const ProbeResult(
            host: 'vpn.example.com',
            port: 443,
            certSha256: '7d2e41c09b8a5f6e3d1c0b9a8f7e6d5c4b3a29181706f5e4d3c2b1a098f7e6d5',
            trustedBySystem: true,
            sslVpnPortal: false,
            ikeAnswers: true,
          ),
        ),
        prepare: setupAt((vm) => vm.probe.execute('vpn.example.com')),
      ),
    );
    testWidgets(
      'client certificate requested, spanish dark',
      (t) => shot(
        t,
        'setup_client_cert_es_dark',
        setup,
        dark: true,
        locale: const Locale('es'),
        platform: FakeVpnPlatform(
          probeResult: const ProbeResult(
            host: 'vpn.example.com',
            port: 443,
            certSha256: 'aa',
            trustedBySystem: true,
            clientCertRequested: true,
          ),
        ),
        prepare: setupAt((vm) => vm.probe.execute('vpn.example.com')),
      ),
    );
    testWidgets(
      'certificate, spanish dark',
      (t) => shot(
        t,
        'setup_certificate_es_dark',
        setup,
        dark: true,
        locale: const Locale('es'),
        platform: FakeVpnPlatform(
          probeResult: const ProbeResult(
            host: 'vpn.example.com',
            port: 10443,
            certSha256: '7d2e41c09b8a5f6e3d1c0b9a8f7e6d5c4b3a29181706f5e4d3c2b1a098f7e6d5',
          ),
        ),
        prepare: setupAt((vm) => vm.probe.execute('vpn.example.com:10443')),
      ),
    );
    testWidgets(
      'sign-in with sso offered',
      (t) => shot(
        t,
        'setup_signin_light',
        setup,
        platform: FakeVpnPlatform(
          probeResult: const ProbeResult(host: 'vpn.example.com', port: 443, trustedBySystem: true, ssoOffered: true),
        ),
        prepare: setupAt((vm) async {
          await vm.probe.execute('vpn.example.com');
          vm.setAuthMode(AuthMode.password);
        }),
      ),
    );
  });

  group('links', () {
    testWidgets(
      'setup link with a different fingerprint',
      (t) => shot(
        t,
        'setup_link_mismatch_light',
        setup,
        platform: FakeVpnPlatform(
          probeResult: const ProbeResult(
            host: 'vpn.example.com',
            port: 10443,
            certSha256: '7d2e41c09b8a5f6e3d1c0b9a8f7e6d5c4b3a29181706f5e4d3c2b1a098f7e6d5',
            trustedBySystem: true,
          ),
        ),
        prepare: setupAt(
          (vm) => vm.applyLink(SetupLink.parse('blanarch://add?host=vpn.example.com&port=10443&pin=${'c' * 64}')!),
        ),
      ),
    );
    testWidgets(
      'share setup sheet',
      (t) => shot(
        t,
        'share_setup_light',
        (c) => Scaffold(
          body: Builder(
            builder: (c) => Center(
              child: TextButton(
                onPressed: () => showShareSetupSheet(
                  c,
                  const Profile(
                    id: 'madrid',
                    name: 'Madrid',
                    hosts: ['203.0.113.46'],
                    port: 10443,
                    username: 'ana',
                    pinSha256: '7d2e41c09b8a5f6e3d1c0b9a8f7e6d5c4b3a29181706f5e4d3c2b1a098f7e6d5',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        interact: (t) => t.tap(find.text('open')),
      ),
    );
  });

  group('settings', () {
    testWidgets('list', (t) => shot(t, 'settings_light', (_) => const SettingsScreen()));
    testWidgets('editor', (t) => shot(t, 'editor_light', (_) => const ProfileEditorScreen(profileId: 'madrid')));
  });
}
