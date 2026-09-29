import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/profile.dart';
import '../../domain/models/setup_link.dart';
import '../../domain/models/vpn_status.dart';
import '../../utils/result.dart';
import '../core/l10n/l10n.dart';
import '../core/l10n/vpn_texts.dart';
import '../core/theme/theme.dart';
import '../core/widgets/fingerprint.dart';
import '../core/widgets/password_field.dart';
import '../core/widgets/segmented.dart';
import '../core/widgets/step_bar.dart';
import 'scan_screen.dart';
import 'setup_view_model.dart';

/// Adds a connection one decision at a time; the main action stays in the thumb zone.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.viewModel, required this.onDone, this.onCancel});
  final SetupViewModel viewModel;

  /// Called with the new profile id.
  final ValueChanged<String> onDone;

  /// Called when the user backs out of the first step (not on first run).
  final VoidCallback? onCancel;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _address = TextEditingController();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _realm = TextEditingController();
  final _email = TextEditingController();
  final _imapHost = TextEditingController();
  final _sender = TextEditingController();
  final _emailPassword = TextEditingController();
  bool _showAdvanced = false;
  bool _imapEdited = false;
  SetupLink? _prefilled;

  SetupViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.addListener(_prefillFromLink);
    vm.finish.addListener(_onFinish);
    vm.verifyEmail.addListener(_onVerify);
    _prefillFromLink();
    // Opened from a link outside first run: check the server straight away.
    if (vm.link != null && !vm.firstRun) unawaited(vm.applyLink(vm.link!));
  }

  /// Copies a setup link's values into the fields once per link.
  void _prefillFromLink() {
    final link = vm.link;
    if (link == null || identical(link, _prefilled)) return;
    _prefilled = link;
    _address.text = link.address;
    if (link.name.isNotEmpty) _name.text = link.name;
    if (link.realm.isNotEmpty) _realm.text = link.realm;
    if (link.username.isNotEmpty) _username.text = link.username;
  }

  Future<void> _scan() async {
    final value = await ScanScreen.open(context);
    if (value == null || !mounted) return;
    final link = SetupLink.parse(value);
    if (link != null) {
      await vm.applyLink(link);
    } else if (!value.contains('://')) {
      _address.text = value.trim();
      setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.notASetupCode)));
    }
  }

  @override
  void dispose() {
    vm.removeListener(_prefillFromLink);
    vm.finish.removeListener(_onFinish);
    vm.verifyEmail.removeListener(_onVerify);
    for (final c in [_address, _name, _username, _password, _realm, _email, _imapHost, _sender, _emailPassword]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onFinish() {
    if (vm.finish.result case Ok(:final value)) widget.onDone(value);
  }

  void _onVerify() {
    if (vm.verifyEmail.error) unawaited(HapticFeedback.heavyImpact());
  }

  void _back() {
    FocusScope.of(context).unfocus();
    if (!vm.back()) widget.onCancel?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final b = context.brand;
        final l10n = context.l10n;
        final canGoBack = vm.stepIndex > 0 || widget.onCancel != null;
        final progress = vm.progress;
        return PopScope(
          // On the first page Back leaves the flow (or the app, on first run); after
          // that it steps back. Ignored while a check runs, so it can't abort halfway.
          canPop: vm.stepIndex == 0 && !vm.busy,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !vm.busy) _back();
          },
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayFor(context),
            child: Scaffold(
              resizeToAvoidBottomInset: true,
              body: SafeArea(
                child: Column(
                  children: [
                    SizedBox(
                      height: 56,
                      child: Row(
                        children: [
                          Visibility(
                            visible: canGoBack,
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            child: IconButton(
                              tooltip: l10n.back,
                              onPressed: canGoBack && !vm.busy ? _back : null,
                              icon: Icon(Icons.arrow_back_rounded, color: b.ink),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: StepBar(step: progress.step, total: progress.total, color: b.accent),
                            ),
                          ),
                          const SizedBox(width: 56),
                        ],
                      ),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: motion(context, const Duration(milliseconds: 320)),
                        switchInCurve: Curves.easeOutCubic,
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(a),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(key: ValueKey(vm.step), child: _page(b, l10n)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _page(Brand b, AppLocalizations l10n) => switch (vm.step) {
    SetupStep.welcome => _welcome(b, l10n),
    SetupStep.address => _addressStep(b, l10n),
    SetupStep.unsupported => _unsupportedStep(b, l10n),
    SetupStep.certificate => _certificateStep(b, l10n),
    SetupStep.signIn => _signInStep(b, l10n),
    SetupStep.emailCode => _emailStep(b, l10n),
    SetupStep.permissions => _permissionsStep(b, l10n),
  };

  Widget _frame({required String title, required String body, required Widget content, required List<Widget> actions}) {
    final b = context.brand;
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxContentWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: TextStyle(fontFamily: serif, fontSize: 38, height: 1.08, color: b.ink),
                    ),
                    const SizedBox(height: 12),
                    Text(body, style: TextStyle(fontSize: 15.5, height: 1.5, color: b.muted)),
                    const SizedBox(height: 28),
                    content,
                    const Spacer(),
                    const SizedBox(height: 20),
                    ...actions,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _spinner(Brand b) =>
      SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: b.muted));

  Widget _welcome(Brand b, AppLocalizations l10n) => _frame(
    title: l10n.welcomeTitle,
    body: l10n.welcomeBody,
    content: Column(
      children: [
        _Feature(icon: Icons.key_rounded, title: l10n.featureSignInTitle, body: l10n.featureSignInBody),
        _Feature(icon: Icons.verified_user_rounded, title: l10n.featureCodeTitle, body: l10n.featureCodeBody),
        _Feature(icon: Icons.alt_route_rounded, title: l10n.featureRetryTitle, body: l10n.featureRetryBody),
      ],
    ),
    actions: [FilledButton(onPressed: vm.start, child: Text(l10n.setUp))],
  );

  void _checkAddress() {
    if (_address.text.trim().isEmpty || vm.busy) return;
    FocusScope.of(context).unfocus();
    unawaited(vm.probe.execute(_address.text));
  }

  Widget _addressStep(Brand b, AppLocalizations l10n) {
    final failure = vm.probeFailure;
    return _frame(
      title: l10n.addressTitle,
      body: l10n.addressBody,
      content: TextField(
        controller: _address,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.go,
        onChanged: (_) {
          vm.clearErrors();
          setState(() {});
        },
        onSubmitted: (_) => _checkAddress(),
        style: TextStyle(fontSize: 17, color: b.ink),
        decoration: InputDecoration(
          labelText: l10n.addressLabel,
          hintText: 'vpn.company.com',
          prefixIcon: Icon(Icons.dns_rounded, color: b.muted),
          errorMaxLines: 3,
          errorText: failure == null
              ? null
              : '${l10n.error(failure.error!)}${failure.ikeAnswers ? '. ${l10n.ipsecAnswers}' : ''}'
                    ' · ${vm.triedAddresses.join(', ')}',
          helperText: vm.probe.running
              ? (vm.checkingAddress == null ? l10n.checkingServer : l10n.checkingHost(vm.checkingAddress!))
              : null,
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _address.text.trim().isEmpty || vm.busy ? null : _checkAddress,
          child: vm.probe.running ? _spinner(b) : Text(l10n.continueAction),
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton.icon(
            onPressed: vm.busy ? null : () => unawaited(_scan()),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: Text(l10n.scanQr),
          ),
        ),
      ],
    );
  }

  /// The server was reached, but something says it may not work: explain, suggest what to ask IT.
  Widget _unsupportedStep(Brand b, AppLocalizations l10n) {
    final server = vm.server!;
    final reason = server.blocker!;
    final sslOff = reason == VpnErrorCode.sslVpnOff;
    return _frame(
      title: l10n.unsupportedTitle,
      body: '${l10n.error(reason)}. ${l10n.fixFor(reason)}',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sslOff && server.ikeAnswers)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_rounded, size: 18, color: b.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(l10n.ipsecAnswers, style: TextStyle(fontSize: 14.5, height: 1.45, color: b.ink)),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(color: b.surface, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.tellIt,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: b.muted),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  sslOff ? l10n.tellItSslOff(server.host) : l10n.tellItClientCert(server.host),
                  style: TextStyle(fontSize: 15, height: 1.45, color: b.ink),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(onPressed: vm.busy ? null : vm.rejectCertificate, child: Text(l10n.tryAnotherAddress)),
        const SizedBox(height: 6),
        Center(
          child: TextButton(onPressed: vm.busy ? null : vm.continueAnyway, child: Text(l10n.continueAnyway)),
        ),
      ],
    );
  }

  Widget _certificateStep(Brand b, AppLocalizations l10n) {
    final server = vm.server!;
    final mismatch = vm.pinMismatch;
    void trust() => unawaited(vm.trust.execute());
    if (mismatch) {
      // A fingerprint that doesn't match the setup link is the real danger: the
      // safe choice is the prominent one (Felt et al., opinionated SSL warnings).
      return _frame(
        title: l10n.linkMismatchTitle,
        body: l10n.linkMismatchBody(server.host),
        content: FingerprintCard(groups: server.fingerprintGroups, warning: true),
        actions: [
          FilledButton(onPressed: vm.busy ? null : vm.rejectCertificate, child: Text(l10n.certDontConnect)),
          const SizedBox(height: 6),
          Center(
            child: TextButton(onPressed: vm.busy ? null : trust, child: Text(l10n.certTrust)),
          ),
        ],
      );
    }
    // First sight of a server with a private certificate: normal for company VPNs.
    // The user confirms once, the certificate is pinned, and any later change is
    // blocked with a loud warning. The fingerprint is there for those who want it.
    return _frame(
      title: l10n.certTitle,
      body: l10n.certBody(server.host),
      content: FingerprintReveal(groups: server.fingerprintGroups),
      actions: [
        FilledButton(
          onPressed: vm.busy ? null : trust,
          child: vm.trust.running ? _spinner(b) : Text(l10n.certTrustContinue),
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(onPressed: vm.busy ? null : vm.rejectCertificate, child: Text(l10n.certDontConnect)),
        ),
      ],
    );
  }

  void _saveSignIn() {
    if (vm.busy) return;
    if (vm.authMode == AuthMode.password && (_username.text.trim().isEmpty || _password.text.isEmpty)) return;
    FocusScope.of(context).unfocus();
    unawaited(
      vm.saveSignIn.execute((name: _name.text, username: _username.text, password: _password.text, realm: _realm.text)),
    );
  }

  Widget _signInStep(Brand b, AppLocalizations l10n) {
    final server = vm.server!;
    final password = vm.authMode == AuthMode.password;
    final canSave = !password || (_username.text.trim().isNotEmpty && _password.text.isNotEmpty);
    return _frame(
      title: l10n.signInTitle,
      body: l10n.signInBody,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (server.ssoOffered) ...[
            Segmented<AuthMode>(
              items: [(AuthMode.password, l10n.methodPassword), (AuthMode.sso, l10n.methodSso)],
              value: vm.authMode,
              onChanged: vm.setAuthMode,
              height: 64,
            ),
            const SizedBox(height: 18),
          ],
          if (password) ...[
            TextField(
              controller: _username,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              style: TextStyle(fontSize: 17, color: b.ink),
              decoration: InputDecoration(labelText: l10n.usernameLabel),
            ),
            const SizedBox(height: 14),
            PasswordField(
              controller: _password,
              label: l10n.passwordLabel,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _saveSignIn(),
            ),
          ] else
            Text(l10n.ssoExplain, style: TextStyle(fontSize: 15, height: 1.5, color: b.ink)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
            icon: Icon(_showAdvanced ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            label: Text(l10n.advanced),
          ),
          if (_showAdvanced) ...[
            TextField(
              controller: _name,
              style: TextStyle(fontSize: 16, color: b.ink),
              decoration: InputDecoration(labelText: l10n.nameLabel, hintText: server.host),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _realm,
              autocorrect: false,
              style: TextStyle(fontSize: 16, color: b.ink),
              decoration: InputDecoration(labelText: l10n.realmLabel, helperText: l10n.realmHint),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: canSave && !vm.busy ? _saveSignIn : null,
          child: vm.saveSignIn.running || vm.finish.running ? _spinner(b) : Text(l10n.continueAction),
        ),
      ],
    );
  }

  void _verifyEmail() {
    if (vm.busy || _email.text.trim().isEmpty || _emailPassword.text.isEmpty) return;
    FocusScope.of(context).unfocus();
    final host = _imapHost.text.trim().isEmpty ? EmailOtpSource.guessImapHost(_email.text) : _imapHost.text;
    unawaited(
      vm.verifyEmail.execute((account: _email.text, imapHost: host, from: _sender.text, password: _emailPassword.text)),
    );
  }

  Widget _emailStep(Brand b, AppLocalizations l10n) {
    final error = vm.emailError;
    final ready = _email.text.contains('@') && _emailPassword.text.isNotEmpty;
    return _frame(
      title: l10n.emailStepTitle,
      body: l10n.emailStepBody,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _email,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            onChanged: (v) {
              if (!_imapEdited) _imapHost.text = EmailOtpSource.guessImapHost(v);
              setState(() {});
            },
            style: TextStyle(fontSize: 17, color: b.ink),
            decoration: InputDecoration(labelText: l10n.emailAddressLabel),
          ),
          const SizedBox(height: 14),
          PasswordField(
            controller: _emailPassword,
            label: l10n.emailPasswordLabel,
            error: error == null ? null : l10n.error(error),
            onChanged: (_) {
              vm.clearErrors();
              setState(() {});
            },
            onSubmitted: (_) => _verifyEmail(),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
            icon: Icon(_showAdvanced ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            label: Text(l10n.advanced),
          ),
          if (_showAdvanced) ...[
            TextField(
              controller: _imapHost,
              autocorrect: false,
              keyboardType: TextInputType.url,
              onChanged: (_) => _imapEdited = true,
              style: TextStyle(fontSize: 16, color: b.ink),
              decoration: InputDecoration(labelText: l10n.imapServerLabel),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _sender,
              autocorrect: false,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(fontSize: 16, color: b.ink),
              decoration: InputDecoration(labelText: l10n.senderLabel, helperText: l10n.optional),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: ready && !vm.busy ? _verifyEmail : null,
          child: vm.verifyEmail.running ? _spinner(b) : Text(l10n.verifyAndContinue),
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: vm.busy ? null : () => unawaited(vm.skipEmail()),
            child: Text(l10n.skipEmailCodes),
          ),
        ),
      ],
    );
  }

  Widget _permissionsStep(Brand b, AppLocalizations l10n) => _frame(
    title: l10n.permissionsTitle,
    body: l10n.permissionsBody,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Feature(icon: Icons.vpn_lock_rounded, title: l10n.permissionVpnTitle, body: l10n.permissionVpnBody),
        _Feature(
          icon: Icons.notifications_none_rounded,
          title: l10n.permissionNotificationsTitle,
          body: l10n.permissionNotificationsBody,
        ),
        _Feature(icon: Icons.privacy_tip_rounded, title: l10n.disclosureTitle, body: l10n.disclosureBody),
      ],
    ),
    actions: [
      FilledButton(
        onPressed: vm.busy ? null : () => unawaited(vm.finish.execute()),
        child: vm.finish.running ? _spinner(b) : Text(l10n.agreeAndConnect),
      ),
    ],
  );
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: b.surfaceAlt, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: b.accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: b.ink),
                ),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(fontSize: 14, height: 1.4, color: b.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
