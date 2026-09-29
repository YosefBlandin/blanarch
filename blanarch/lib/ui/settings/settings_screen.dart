import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/profile.dart';
import '../app/app_view_model.dart';
import '../core/l10n/l10n.dart';
import '../core/theme/theme.dart';
import '../core/widgets/segmented.dart';
import '../core/widgets/surface.dart';
import '../core/widgets/wordmark.dart';
import '../setup/setup_route.dart';
import 'activity_log_screen.dart';
import 'profile_editor_screen.dart';
import 'settings_view_model.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => SettingsViewModel(profiles: c.read(), settings: c.read()),
    child: Consumer<SettingsViewModel>(builder: (context, vm, _) => _SettingsView(vm: vm)),
  );
}

class _SettingsView extends StatelessWidget {
  const _SettingsView({required this.vm});
  final SettingsViewModel vm;

  void _edit(BuildContext context, Profile p) =>
      unawaited(Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ProfileEditorScreen(profileId: p.id))));

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final l10n = context.l10n;
    final app = context.watch<AppViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.settingsTitle,
          style: TextStyle(fontFamily: serif, fontSize: 30, color: b.ink),
        ),
        leading: IconButton(
          tooltip: l10n.back,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: pagePadding(context),
        children: [
          _Label(l10n.appearance),
          Segmented<ThemePreference>(
            items: [
              (ThemePreference.system, l10n.themeAuto),
              (ThemePreference.light, l10n.themeLight),
              (ThemePreference.dark, l10n.themeDark),
            ],
            value: app.theme,
            onChanged: (t) => unawaited(app.setTheme.execute(t)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(l10n.themeAutoHint, style: TextStyle(fontSize: 13, color: b.muted)),
          ),
          const SizedBox(height: 28),
          _Label(l10n.connections),
          Surface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final p in vm.profiles) ...[
                  _Row(
                    icon: p.authMode == AuthMode.sso ? Icons.badge_rounded : Icons.vpn_lock_rounded,
                    title: p.name,
                    subtitle: p.address,
                    ltrSubtitle: true,
                    value: '',
                    onTap: () => _edit(context, p),
                  ),
                  const Divider(indent: 56),
                ],
                _Row(
                  icon: Icons.add_rounded,
                  title: l10n.addConnection,
                  value: '',
                  onTap: () => unawaited(openAddConnection(context)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _Label(l10n.security),
          Surface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.fromLTRB(18, 6, 12, 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  secondary: Icon(Icons.fingerprint_rounded, color: b.accent),
                  title: Text(
                    l10n.appLock,
                    style: TextStyle(fontSize: 16, color: b.ink, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    vm.appLockAvailable ? l10n.appLockHint : l10n.appLockUnavailable,
                    style: TextStyle(fontSize: 13, height: 1.35, color: b.muted),
                  ),
                  value: vm.appLockEnabled,
                  onChanged: vm.appLockAvailable && !vm.setAppLock.running
                      ? (v) => unawaited(vm.setAppLock.execute(v))
                      : null,
                ),
                const Divider(indent: 56),
                _Row(
                  icon: Icons.shield_rounded,
                  title: l10n.alwaysOn,
                  value: '',
                  subtitle: l10n.alwaysOnHint,
                  external: true,
                  onTap: vm.openVpnSettings,
                ),
              ],
            ),
          ),
          if (vm.canAddTile) ...[
            const SizedBox(height: 28),
            _Label(l10n.shortcuts),
            Surface(
              padding: EdgeInsets.zero,
              child: _Row(
                icon: Icons.toggle_on_rounded,
                title: l10n.quickTile,
                subtitle: l10n.quickTileHint,
                value: '',
                onTap: vm.addQuickSettingsTile,
              ),
            ),
          ],
          const SizedBox(height: 28),
          _Label(l10n.diagnostics),
          Surface(
            padding: EdgeInsets.zero,
            child: _Row(
              icon: Icons.receipt_long_rounded,
              title: l10n.activityLog,
              value: '',
              onTap: () => unawaited(
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ActivityLogScreen())),
              ),
            ),
          ),
          const SizedBox(height: 40),
          const Center(child: Wordmark(size: 22)),
          const SizedBox(height: 6),
          Center(
            child: Text(l10n.versionLine(appVersion), style: TextStyle(fontSize: 12.5, color: b.muted)),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w600, color: context.brand.muted),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.subtitle,
    this.ltrSubtitle = false,
    this.external = false,
  });
  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;
  final VoidCallback onTap;

  /// The subtitle is an address: keep it left to right and on one line.
  final bool ltrSubtitle;

  /// The row leaves the app (opens Android settings).
  final bool external;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: b.accent, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 16, color: b.ink, fontWeight: FontWeight.w500),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        textDirection: ltrSubtitle ? TextDirection.ltr : null,
                        maxLines: ltrSubtitle ? 1 : null,
                        overflow: ltrSubtitle ? TextOverflow.ellipsis : null,
                        style: TextStyle(fontSize: 13, height: 1.35, color: b.muted),
                      ),
                    ],
                  ],
                ),
              ),
              if (value.isNotEmpty) ...[
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: b.muted),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Icon(
                external ? Icons.open_in_new_rounded : Icons.chevron_right_rounded,
                color: b.muted,
                size: external ? 20 : 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
