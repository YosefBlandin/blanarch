import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/vpn_status.dart';
import '../../../utils/command.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/vpn_texts.dart';
import '../../core/theme/theme.dart';
import 'waiting_cards.dart';

/// Shown only while the gateway waits for a one-time code. Three cases:
/// the app is reading the inbox, the user chose to type codes, or the inbox
/// couldn't be read (then it says why and offers a fix).
class CodeCard extends StatefulWidget {
  const CodeCard({
    super.key,
    required this.status,
    required this.submit,
    required this.onFixEmail,
    required this.onCancel,
    this.clock = DateTime.now,
  });
  final VpnStatus status;
  final Command1<void, String> submit;
  final VoidCallback onFixEmail;
  final VoidCallback onCancel;
  final DateTime Function() clock;

  @override
  State<CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends State<CodeCard> {
  final _ctl = TextEditingController();
  bool _open = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _ctl.text.trim();
    if (code.length < 4) return;
    unawaited(HapticFeedback.lightImpact());
    FocusScope.of(context).unfocus();
    unawaited(widget.submit.execute(code));
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final l10n = context.l10n;
    final status = widget.status;
    final watching = status.emailWatching;
    // No mailbox set up is a choice, not a problem: just ask for the code.
    final issue = status.emailIssue == VpnErrorCode.emailNotConfigured ? null : status.emailIssue;
    final open = _open || !watching;
    final deadline = status.deadline;
    return WaitingCard(
      icon: watching
          ? Icons.mark_email_unread_rounded
          : issue != null
          ? Icons.error_outline_rounded
          : Icons.dialpad_rounded,
      iconColor: issue != null ? b.bad : null,
      title: watching
          ? l10n.checkingInbox
          : issue != null
          ? l10n.error(issue)
          : l10n.enterCodeTitle,
      body: watching || issue != null ? l10n.codeExpiresHint : l10n.enterCodeBody,
      trailing: deadline == null ? null : Countdown(deadline: deadline, clock: widget.clock),
      onCancel: widget.onCancel,
      action: watching && !_open
          ? TextButton(onPressed: () => setState(() => _open = true), child: Text(l10n.typeCode))
          : issue != null
          ? TextButton(onPressed: widget.onFixEmail, child: Text(l10n.fix))
          : null,
      child: open
          ? Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctl,
                      autofocus: _open || issue == null,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      style: TextStyle(fontSize: 20, letterSpacing: 6, fontWeight: FontWeight.w600, color: b.ink),
                      decoration: InputDecoration(
                        hintText: l10n.codeHint,
                        hintStyle: TextStyle(
                          fontSize: 17,
                          letterSpacing: 0,
                          fontWeight: FontWeight.w400,
                          color: b.muted,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Tooltip(
                    message: l10n.submitCode,
                    child: SizedBox.square(
                      dimension: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(56, 56)),
                        onPressed: _submit,
                        child: Icon(Icons.arrow_forward_rounded, semanticLabel: l10n.submitCode),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}
