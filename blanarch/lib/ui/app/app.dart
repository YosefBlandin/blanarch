import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import '../core/theme/theme.dart';
import '../home/home_screen.dart';
import '../home/home_view_model.dart';
import '../setup/setup_screen.dart';
import '../setup/setup_view_model.dart';
import '../splash/splash_screen.dart';
import 'app_view_model.dart';

class BlanarchApp extends StatelessWidget {
  const BlanarchApp({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AppViewModel>();
    return MaterialApp(
      onGenerateTitle: (_) => 'Blanarch',
      debugShowCheckedModeBanner: false,
      themeMode: vm.themeMode,
      theme: buildTheme(Brand.light, Brightness.light),
      darkTheme: buildTheme(Brand.dark, Brightness.dark),
      themeAnimationDuration: const Duration(milliseconds: 350),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Shell(),
    );
  }
}

/// Splash, then the first-run wizard or home, cross-fading between them.
class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AppViewModel>();
    return AnimatedSwitcher(
      duration: motion(context, const Duration(milliseconds: 450)),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.985, end: 1.0).animate(a), child: child),
      ),
      child: switch (vm.stage) {
        AppStage.splash => SplashScreen(key: const ValueKey('splash'), onDone: vm.splashFinished),
        AppStage.onboarding => ChangeNotifierProvider(
          key: const ValueKey('onboarding'),
          create: (c) => SetupViewModel(
            profiles: c.read(),
            settings: c.read(),
            vpn: c.read(),
            firstRun: true,
            link: vm.pendingLink,
          ),
          child: Builder(
            builder: (c) => SetupScreen(viewModel: c.read(), onDone: (_) => vm.onboardingFinished()),
          ),
        ),
        AppStage.home => ChangeNotifierProvider(
          key: const ValueKey('home'),
          create: (c) => HomeViewModel(
            vpn: c.read(),
            profiles: c.read(),
            settings: c.read(),
            connectOnStart: vm.takeConnectOnArrival(),
          ),
          child: Builder(builder: (c) => HomeScreen(viewModel: c.read())),
        ),
      },
    );
  }
}
