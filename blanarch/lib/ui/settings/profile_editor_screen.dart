import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/profile.dart';
import '../core/l10n/l10n.dart';
import '../core/theme/theme.dart';
import '../core/widgets/segmented.dart';
import '../core/widgets/surface.dart';
import 'password_sheet.dart';
import 'settings_view_model.dart';
import 'share_setup_sheet.dart';

/// Edits one connection. Text fields save when they lose focus.
class ProfileEditorScreen extends StatelessWidget {
  const ProfileEditorScreen({super.key, required this.profileId});
  final String profileId;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => ProfileEditorViewModel(profiles: c.read(), profileId: profileId),
    child: Consumer<ProfileEditorViewModel>(builder: (_, vm, _) => _Editor(vm: vm)),
  );
}

class _Editor extends StatefulWidget {
  const _Editor({required this.vm});
  final ProfileEditorViewModel vm;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final Profile _initial = widget.vm.profile!;
  late final _name = TextEditingController(text: _initial.name);
  late final _address = TextEditingController(text: _initial.address);
  late final _backups = TextEditingController(text: _initial.hosts.skip(1).join('\n'));
  late final _username = TextEditingController(text: _initial.username);
  late final _realm = TextEditingController(text: _initial.realm);

  ProfileEditorViewModel get vm => widget.vm;

  @override
  void dispose() {
    for (final c in [_name, _address, _backups, _username, _realm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _saveText() {
    final parsed = _parseAddress(_address.text);
    unawaited(
      vm.update(
        (p) => p.copyWith(
          name: _name.text.trim().isEmpty ? p.name : _name.text.trim(),
          hosts: [
            parsed?.$1 ?? p.mainHost,
            ..._backups.text.split(RegExp(r'[\s,]+')).map((h) => h.trim()).where((h) => h.isNotEmpty),
          ],
          port: parsed?.$2 ?? p.port,
          username: _username.text.trim(),
          realm: _realm.text.trim(),
        ),
      ),
    );
  }

  /// `host[:port]`; the engine re-validates when it connects.
  (String, int)? _parseAddress(String input) {
    final s = input.trim().replaceFirst(RegExp('^https?://'), '').split('/').first;
    if (s.isEmpty) return null;
    final i = s.lastIndexOf(':');
    if (i > 0 && !s.contains(']')) {
      final port = int.tryParse(s.substring(i + 1));
      return port == null ? null : (s.substring(0, i).toLowerCase(), port);
    }
    return (s.toLowerCase(), 443);
  }

  Future<void> _confirmDelete(AppLocalizations l10n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(l10n.deleteConfirm(vm.profile?.name ?? '')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(l10n.cancel)),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: context.brand.bad),
            onPressed: () => Navigator.pop(d, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await vm.delete.execute();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final l10n = context.l10n;
    final p = vm.profile;
    if (p == null) return const Scaffold();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          p.name,
          style: TextStyle(fontFamily: serif, fontSize: 30, color: b.ink),
        ),
      ),
      body: ListView(
        padding: pagePadding(context),
        children: [
          _Field(controller: _name, label: l10n.nameLabel, onDone: _saveText),
          _Field(controller: _address, label: l10n.addressLabel, onDone: _saveText, url: true),
          if (p.authMode == AuthMode.password)
            _Field(controller: _username, label: l10n.usernameLabel, onDone: _saveText),
          const SizedBox(height: 8),
          _Label(l10n.signInTitle),
          Segmented<AuthMode>(
            items: [(AuthMode.password, l10n.methodPassword), (AuthMode.sso, l10n.methodSso)],
            value: p.authMode,
            height: 64,
            onChanged: (m) => unawaited(vm.update((p) => p.copyWith(authMode: m))),
          ),
          const SizedBox(height: 20),
          if (p.authMode == AuthMode.password) ...[
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _Row(
                    icon: Icons.key_rounded,
                    title: l10n.passwordLabel,
                    value: p.hasPassword ? l10n.saved : l10n.notSet,
                    ok: p.hasPassword,
                    onTap: () => unawaited(showPasswordSheet(context, profile: p)),
                  ),
                  const Divider(indent: 56),
                  _Row(
                    icon: Icons.mark_email_read_rounded,
                    title: l10n.emailCodesLabel,
                    value: p.emailOtp?.account ?? l10n.off,
                    ok: p.hasEmailPassword,
                    onTap: () => unawaited(showEmailOtpSheet(context, profileId: p.id)),
                    trailing: p.emailOtp == null
                        ? null
                        : IconButton(
                            tooltip: l10n.remove,
                            onPressed: () => unawaited(vm.removeEmailOtp.execute()),
                            icon: Icon(Icons.close_rounded, color: b.muted, size: 20),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _Label(l10n.secondFactorLabel),
            Segmented<SecondFactorPreference>(
              items: [
                (SecondFactorPreference.auto, l10n.secondFactorAuto),
                (SecondFactorPreference.code, l10n.secondFactorCode),
              ],
              value: p.secondFactor,
              onChanged: (v) => unawaited(vm.update((p) => p.copyWith(secondFactor: v))),
            ),
            const SizedBox(height: 20),
          ],
          ExpansionTile(
            title: Text(
              l10n.advanced,
              style: TextStyle(color: b.ink, fontWeight: FontWeight.w600),
            ),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            shape: const Border(),
            children: [
              _Field(controller: _backups, label: l10n.backupAddressesLabel, onDone: _saveText, url: true, lines: 3),
              _Field(controller: _realm, label: l10n.realmLabel, helper: l10n.realmHint, onDone: _saveText),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () => unawaited(showShareSetupSheet(context, p)),
            icon: const Icon(Icons.qr_code_2_rounded),
            label: Text(l10n.shareSetup),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: b.bad),
              onPressed: () => unawaited(_confirmDelete(l10n)),
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(l10n.deleteConnection),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.onDone,
    this.url = false,
    this.lines = 1,
    this.helper,
  });
  final TextEditingController controller;
  final String label;
  final String? helper;
  final VoidCallback onDone;
  final bool url;
  final int lines;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Focus(
      onFocusChange: (focused) {
        if (!focused) onDone();
      },
      child: TextField(
        controller: controller,
        autocorrect: false,
        minLines: lines,
        maxLines: lines,
        keyboardType: url ? (lines > 1 ? TextInputType.multiline : TextInputType.url) : TextInputType.text,
        onSubmitted: (_) => onDone(),
        style: TextStyle(fontSize: 16, color: context.brand.ink),
        decoration: InputDecoration(labelText: label, helperText: helper),
      ),
    ),
  );
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
    this.ok = false,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String value;
  final bool ok;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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
                    const SizedBox(height: 2),
                    Text(value, style: TextStyle(fontSize: 13.5, color: ok ? b.ok : b.muted)),
                  ],
                ),
              ),
              trailing ?? Icon(Icons.chevron_right_rounded, color: b.muted),
            ],
          ),
        ),
      ),
    );
  }
}
