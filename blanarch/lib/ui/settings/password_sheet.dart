import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../domain/models/profile.dart';
import '../core/l10n/l10n.dart';
import '../core/l10n/vpn_texts.dart';
import '../core/theme/theme.dart';
import '../core/widgets/password_field.dart';
import 'settings_view_model.dart';

/// Sets or replaces the VPN password of [profile].
/// Completes with true when a new password was saved.
Future<bool> showPasswordSheet(BuildContext context, {required Profile profile}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ChangeNotifierProvider(
        create: (_) => PasswordFormViewModel(profiles: context.read(), profile: profile),
        child: Consumer<PasswordFormViewModel>(builder: (_, vm, _) => _PasswordSheet(vm: vm)),
      ),
    ) ??
    false;

/// Sets up reading sign-in codes from a mailbox for [profileId].
Future<void> showEmailOtpSheet(BuildContext context, {required String profileId}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => ChangeNotifierProvider(
    create: (_) => EmailOtpFormViewModel(profiles: context.read(), profileId: profileId),
    child: Consumer<EmailOtpFormViewModel>(builder: (_, vm, _) => _EmailOtpSheet(vm: vm)),
  ),
);

class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet({required this.vm});
  final PasswordFormViewModel vm;

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final _ctl = TextEditingController();

  PasswordFormViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    vm.save.addListener(_onSave);
  }

  @override
  void dispose() {
    vm.save.removeListener(_onSave);
    _ctl.dispose();
    super.dispose();
  }

  void _onSave() {
    if (vm.save.completed) {
      unawaited(HapticFeedback.lightImpact());
      Navigator.pop(context, true);
    }
  }

  void _submit() {
    if (_ctl.text.isNotEmpty) unawaited(vm.save.execute(_ctl.text));
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: vm.save,
      builder: (context, _) => _SheetBody(
        title: l10n.passwordLabel,
        subtitle: '${vm.profile.username}  ·  ${vm.profile.name}',
        children: [
          PasswordField(
            controller: _ctl,
            autofocus: true,
            label: l10n.passwordLabel,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _ctl.text.isEmpty || vm.save.running ? null : _submit,
            child: vm.save.running ? _spinner(b) : Text(l10n.save),
          ),
        ],
      ),
    );
  }
}

class _EmailOtpSheet extends StatefulWidget {
  const _EmailOtpSheet({required this.vm});
  final EmailOtpFormViewModel vm;

  @override
  State<_EmailOtpSheet> createState() => _EmailOtpSheetState();
}

class _EmailOtpSheetState extends State<_EmailOtpSheet> {
  late final _email = TextEditingController(text: vm.current?.account ?? '');
  late final _imap = TextEditingController(text: vm.current?.imapHost ?? '');
  late final _sender = TextEditingController(text: vm.current?.from ?? '');
  final _password = TextEditingController();
  bool _imapEdited = false;

  EmailOtpFormViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    _imapEdited = _imap.text.isNotEmpty;
    vm.save.addListener(_onSave);
  }

  @override
  void dispose() {
    vm.save.removeListener(_onSave);
    for (final c in [_email, _imap, _sender, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onSave() {
    if (vm.save.error) unawaited(HapticFeedback.heavyImpact());
    if (vm.save.completed) Navigator.pop(context);
  }

  void _submit() {
    if (!_email.text.contains('@') || _password.text.isEmpty) return;
    final host = _imap.text.trim().isEmpty ? EmailOtpSource.guessImapHost(_email.text) : _imap.text.trim();
    unawaited(
      vm.save.execute((
        source: EmailOtpSource(account: _email.text.trim(), imapHost: host, from: _sender.text.trim()),
        password: _password.text,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: vm.save,
      builder: (context, _) => _SheetBody(
        title: l10n.emailCodesLabel,
        subtitle: l10n.emailStepBody,
        children: [
          TextField(
            controller: _email,
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            onChanged: (v) {
              if (!_imapEdited) _imap.text = EmailOtpSource.guessImapHost(v);
              setState(() {});
            },
            decoration: InputDecoration(labelText: l10n.emailAddressLabel),
          ),
          const SizedBox(height: 14),
          PasswordField(
            controller: _password,
            label: l10n.emailPasswordLabel,
            error: vm.error == null ? null : l10n.error(vm.error!),
            onChanged: (_) {
              vm.clearError();
              setState(() {});
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _imap,
            autocorrect: false,
            keyboardType: TextInputType.url,
            onChanged: (_) => _imapEdited = true,
            decoration: InputDecoration(labelText: l10n.imapServerLabel),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _sender,
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: l10n.senderLabel, helperText: l10n.optional),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _email.text.contains('@') && _password.text.isNotEmpty && !vm.save.running ? _submit : null,
            child: vm.save.running ? _spinner(b) : Text(l10n.verifyAndContinue),
          ),
        ],
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.title, required this.subtitle, required this.children});
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(fontFamily: serif, fontSize: 32, color: b.ink),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 14, height: 1.4, color: b.muted)),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}

Widget _spinner(Brand b) =>
    SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: b.muted));
