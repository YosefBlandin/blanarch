import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../domain/models/vpn_status.dart';
import '../core/l10n/l10n.dart';
import '../core/theme/theme.dart';
import 'settings_view_model.dart';

class ActivityLogScreen extends StatelessWidget {
  const ActivityLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final l10n = context.l10n;
    return ChangeNotifierProvider(
      create: (c) => ActivityLogViewModel(vpn: c.read()),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            l10n.activityTitle,
            style: TextStyle(fontFamily: serif, fontSize: 30, color: b.ink),
          ),
          actions: [
            Consumer<ActivityLogViewModel>(
              builder: (context, vm, _) => Row(
                children: [
                  IconButton(
                    tooltip: l10n.copy,
                    onPressed: vm.entries.isEmpty
                        ? null
                        : () {
                            unawaited(Clipboard.setData(ClipboardData(text: vm.asText)));
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.copied)));
                          },
                    icon: const Icon(Icons.copy_all_rounded),
                  ),
                  IconButton(
                    tooltip: l10n.shareLog,
                    onPressed: vm.entries.isEmpty ? null : () => unawaited(vm.share(l10n.shareLogSubject)),
                    icon: const Icon(Icons.share_rounded),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ],
        ),
        body: Consumer<ActivityLogViewModel>(
          builder: (context, vm, _) {
            final entries = vm.entries;
            if (entries.isEmpty) {
              return Center(
                child: Text(l10n.nothingYet, style: TextStyle(color: b.muted)),
              );
            }
            final time = MaterialLocalizations.of(context);
            return ListView.builder(
              reverse: true,
              padding: pagePadding(context, bottom: 24),
              itemCount: entries.length,
              itemBuilder: (_, i) {
                final e = entries[i];
                // Level is shown by a glyph and spoken, not by colour alone.
                final (color, icon, level) = switch (e.level) {
                  LogLevel.error => (b.bad, Icons.error_rounded, l10n.logError),
                  LogLevel.ok => (b.ok, Icons.check_circle_rounded, l10n.logOk),
                  LogLevel.info => (b.muted, Icons.circle_outlined, l10n.logInfo),
                };
                final stamp = time.formatTimeOfDay(TimeOfDay.fromDateTime(e.time), alwaysUse24HourFormat: true);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 8),
                        child: Icon(icon, size: 14, color: color, semanticLabel: level),
                      ),
                      Expanded(
                        child: SelectableText(
                          '$stamp  ${e.message}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12.5,
                            height: 1.4,
                            color: e.level == LogLevel.info ? b.ink : color,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
