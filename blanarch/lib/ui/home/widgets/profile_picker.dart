import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/profile.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/theme.dart';

/// For four or more connections: a pill showing the current one; tapping it
/// opens a list to choose another or add a new one.
class ProfilePicker extends StatelessWidget {
  const ProfilePicker({
    super.key,
    required this.profiles,
    required this.selectedId,
    required this.enabled,
    required this.onSelect,
    required this.onAdd,
    this.onDisabledTap,
  });
  final List<Profile> profiles;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;

  /// Called on tap while switching is locked (during a connection), to say why.
  final VoidCallback? onDisabledTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final current = profiles.where((p) => p.id == selectedId).firstOrNull ?? profiles.first;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: b.surfaceAlt,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: enabled ? () => unawaited(_open(context)) : onDisabledTap,
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    current.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: b.ink),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.unfold_more_rounded, size: 20, color: b.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheet) {
      final b = sheet.brand;
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          for (final p in profiles)
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              selected: p.id == selectedId,
              selectedColor: b.ink,
              leading: Icon(
                p.id == selectedId ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: b.accent,
              ),
              title: Text(
                p.name,
                style: TextStyle(color: b.ink, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(p.address, style: TextStyle(color: b.muted)),
              onTap: () {
                Navigator.pop(sheet);
                onSelect(p.id);
              },
            ),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: Icon(Icons.add_rounded, color: b.accent),
            title: Text(
              sheet.l10n.addConnection,
              style: TextStyle(color: b.accent, fontWeight: FontWeight.w600),
            ),
            onTap: () {
              Navigator.pop(sheet);
              onAdd();
            },
          ),
        ],
      );
    },
  );
}
