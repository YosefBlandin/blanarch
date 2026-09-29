import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/surface.dart';

/// Shown while the gateway waits for a FortiToken push approval.
class PushCard extends StatelessWidget {
  const PushCard({super.key, required this.onUseCode, required this.onCancel});
  final VoidCallback onUseCode;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WaitingCard(
      icon: Icons.phonelink_lock_rounded,
      title: l10n.waitingPushTitle,
      body: l10n.waitingPushBody,
      onCancel: onCancel,
      action: TextButton(onPressed: onUseCode, child: Text(l10n.useCodeInstead)),
    );
  }
}

/// Shown while the user signs in with their company account in the browser.
class SsoCard extends StatelessWidget {
  const SsoCard({super.key, required this.onOpen, required this.onCancel, this.deadline, this.clock = DateTime.now});
  final VoidCallback onOpen;
  final VoidCallback onCancel;
  final DateTime? deadline;
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WaitingCard(
      icon: Icons.open_in_browser_rounded,
      title: l10n.waitingSsoTitle,
      body: l10n.waitingSsoBody,
      trailing: deadline == null ? null : Countdown(deadline: deadline!, clock: clock),
      onCancel: onCancel,
      action: TextButton(onPressed: onOpen, child: Text(l10n.openSignInPage)),
    );
  }
}

/// A card for one wait: what is happening, how to go on, and how to stop.
class WaitingCard extends StatelessWidget {
  const WaitingCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.onCancel,
    this.action,
    this.trailing,
    this.iconColor,
    this.child,
  });
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onCancel;
  final Widget? action;
  final Widget? trailing;
  final Color? iconColor;

  /// Extra content under the text, such as the code field.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final l10n = context.l10n;
    return Semantics(
      container: true,
      child: Surface(
        padding: const EdgeInsets.fromLTRB(18, 16, 10, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: iconColor ?? b.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Announced when the card appears, so TalkBack users hear what to do next.
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          title,
                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: b.ink),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(body, style: TextStyle(fontSize: 13.5, height: 1.4, color: b.muted)),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!, const SizedBox(width: 8)],
              ],
            ),
            if (child != null) ...[const SizedBox(height: 12), child!],
            Row(
              children: [
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(foregroundColor: b.muted),
                  child: Text(l10n.cancel),
                ),
                const Spacer(),
                ?action,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Seconds left until [deadline], updated every second.
class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.deadline, this.clock = DateTime.now});
  final DateTime deadline;
  final DateTime Function() clock;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final left = math.max(0, widget.deadline.difference(widget.clock()).inSeconds);
    // Not a live region: announcing every second would drown out TalkBack.
    return Text(
      context.l10n.timeLeft(left),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: left <= 15 ? b.bad : b.muted,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
