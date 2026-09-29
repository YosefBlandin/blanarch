import 'package:flutter/material.dart';

import '../../../domain/models/vpn_status.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/vpn_texts.dart';
import '../../core/theme/theme.dart';

/// The four steps of a connection as a status track: done steps get a check,
/// the current one a small spinning arc and its details, later ones just their
/// number. Nothing here is tappable, so nothing looks like a choice.
class ConnectTimeline extends StatelessWidget {
  const ConnectTimeline({super.key, required this.status, this.reveal = 1});
  final VpnStatus status;

  /// 0 to 1 while the card appears: rows arrive one after another.
  final double reveal;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final l10n = context.l10n;
    final current = status.step ?? ConnectStep.gateway;
    final names = [l10n.stepChipServer, l10n.stepChipSignIn, l10n.secondFactorLabel, l10n.stepChipTunnel];
    final host = status.host;
    final retrying = status.attempt > 1 && host != null;
    final offline = status.phase == VpnPhase.waitingNetwork;
    final details = <(String, Color)>[
      if (current != ConnectStep.gateway || offline) (l10n.stepLabel(status), b.muted),
      if (retrying)
        (l10n.attemptOf(status.attempt, status.maxAttempts, host), b.muted)
      else if (current == ConnectStep.gateway && host != null && !offline)
        (l10n.reachingHost(host), b.muted),
      if (status.retryReason != null) (l10n.lastTry(l10n.error(status.retryReason!)), b.bad),
    ];
    return Semantics(
      container: true,
      label: l10n.progressOf(current.index + 1, names.length, names[current.index]),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
        decoration: BoxDecoration(color: b.surface, borderRadius: BorderRadius.circular(22)),
        child: Column(
          children: [
            for (final (i, name) in names.indexed)
              _Reveal(
                value: Interval(i * 0.12, i * 0.12 + 0.64).transform(reveal),
                child: _StepRow(
                  number: i + 1,
                  name: name,
                  state: i < current.index
                      ? _StepState.done
                      : i == current.index
                      ? _StepState.current
                      : _StepState.todo,
                  lineDone: i < current.index,
                  last: i == names.length - 1,
                  details: i == current.index ? details : const [],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _StepState { done, current, todo }

class _Reveal extends StatelessWidget {
  const _Reveal({required this.value, required this.child});
  final double value;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: value,
    child: Transform.translate(offset: Offset(0, 12 * (1 - value)), child: child),
  );
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.name,
    required this.state,
    required this.lineDone,
    required this.last,
    required this.details,
  });
  final int number;
  final String name;
  final _StepState state;
  final bool lineDone;
  final bool last;
  final List<(String, Color)> details;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final marker = switch (state) {
      _StepState.done => Icon(Icons.check_rounded, size: 20, color: b.ok),
      _StepState.current => SizedBox.square(
        dimension: 15,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: b.busy,
          // Frozen when animations are off; still reads as "in progress".
          value: MediaQuery.disableAnimationsOf(context) ? 0.3 : null,
        ),
      ),
      _StepState.todo => Text(
        '$number',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: b.outline),
      ),
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                ExcludeSemantics(
                  child: SizedBox(height: 20, child: Center(child: marker)),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      decoration: BoxDecoration(
                        color: lineDone ? b.ok : b.border,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      height: 20 / 15,
                      fontWeight: state == _StepState.current ? FontWeight.w600 : FontWeight.w500,
                      color: state == _StepState.todo ? b.muted : b.ink,
                    ),
                  ),
                  for (final (text, color) in details)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The latest main steps, newest first, older ones fading. Always visible while
/// connecting so the user can see it is working, and what went wrong.
class ActivityFeed extends StatelessWidget {
  const ActivityFeed({super.key, required this.entries, required this.onSeeAll});
  final List<LogEntry> entries;
  final VoidCallback onSeeAll;

  static const _fade = [1.0, 0.85, 0.72, 0.6, 0.5];

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final l10n = context.l10n;
    final time = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.activity,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: b.muted),
                ),
              ),
            ),
            const Spacer(),
            TextButton(onPressed: onSeeAll, child: Text(l10n.seeAll)),
          ],
        ),
        for (final (i, e) in entries.indexed)
          Semantics(
            // The newest line is spoken as it arrives.
            liveRegion: i == 0,
            child: Opacity(
              opacity: _fade[i.clamp(0, _fade.length - 1)],
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 18,
                      child: Center(
                        child: switch (e.level) {
                          LogLevel.error => Icon(
                            Icons.error_rounded,
                            size: 14,
                            color: b.bad,
                            semanticLabel: l10n.logError,
                          ),
                          LogLevel.ok => Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: b.ok,
                            semanticLabel: l10n.logOk,
                          ),
                          LogLevel.info => Icon(Icons.circle_outlined, size: 9, color: b.outline),
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      time.formatTimeOfDay(TimeOfDay.fromDateTime(e.time), alwaysUse24HourFormat: true),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 18 / 12.5,
                        color: b.muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.activityLine(e),
                        style: TextStyle(
                          fontSize: 13,
                          height: 18 / 13,
                          fontWeight: i == 0 ? FontWeight.w500 : FontWeight.w400,
                          color: e.level == LogLevel.error ? b.bad : b.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
