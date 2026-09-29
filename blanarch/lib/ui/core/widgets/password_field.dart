import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/theme.dart';

class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? error;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.error,
    this.autofocus = false,
    this.onSubmitted,
    this.onChanged,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return TextField(
      controller: widget.controller,
      autofocus: widget.autofocus,
      obscureText: _obscure,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      style: TextStyle(fontSize: 17, color: b.ink),
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.error,
        errorMaxLines: 2,
        suffixIcon: IconButton(
          tooltip: _obscure ? context.l10n.showPassword : context.l10n.hidePassword,
          icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: b.muted),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}
