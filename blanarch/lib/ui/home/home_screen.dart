import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../domain/models/vpn_status.dart';
import '../../utils/result.dart';
import '../app/app_view_model.dart';
import '../core/l10n/l10n.dart';
import '../core/l10n/vpn_texts.dart';
import '../core/theme/status_colors.dart';
import '../core/theme/theme.dart';
import '../core/widgets/connect_orb.dart';
import '../core/widgets/segmented.dart';
import '../core/widgets/wordmark.dart';
import '../settings/activity_log_screen.dart';
import '../settings/password_sheet.dart';
import '../settings/profile_editor_screen.dart';
import '../settings/settings_screen.dart';
import '../setup/setup_route.dart';
import 'home_view_model.dart';
import 'widgets/code_card.dart';
import 'widgets/connect_progress.dart';
import 'widgets/connected_details.dart';
import 'widgets/error_sheet.dart';
import 'widgets/profile_picker.dart';
import 'widgets/waiting_cards.dart';

/// One screen, one action: pick a connection, tap the button. Cards for the
/// code, push approval or browser sign-in only appear while they're needed.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.viewModel, this.clock = DateTime.now});
  final HomeViewModel viewModel;

  /// Source of "now" for the connected timer; fixed in tests.
  final DateTime Function() clock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  Timer? _ticker;

  /// 0 = resting (big button in the middle), 1 = connecting (small button in the
  /// corner, steps and activity). The button is one widget that travels between
  /// the two spots, so the eye follows it from one screen to the other.
  late final AnimationController _glide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    reverseDuration: const Duration(milliseconds: 700),
    value: widget.viewModel.status.active ? 1 : 0,
  );
  final _stackKey = GlobalKey();
  final _restSlot = GlobalKey();
  final _connSlot = GlobalKey();
  Rect? _restRect;
  Rect? _connRect;

  /// What each layout last showed, so a layout that is fading out keeps its
  /// content instead of jumping to the other state's.
  VpnStatus? _restStatus;
  VpnStatus? _busyStatus;
  VpnPhase _lastPhase = VpnPhase.idle;
  AppViewModel? _app;

  HomeViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _lastPhase = vm.status.phase;
    vm.addListener(_onChange);
    vm.toggle.addListener(_onToggle);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if ((vm.status.phase == VpnPhase.connected || vm.status.busy) && mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_app == null) {
      _app = context.read<AppViewModel>()..addListener(_onAppChange);
      WidgetsBinding.instance.addPostFrameCallback((_) => _onAppChange());
    }
  }

  /// A setup link arrived: open the add-connection flow with it.
  void _onAppChange() {
    if (!mounted || _app?.pendingLink == null) return;
    final link = _app!.takePendingLink();
    unawaited(openAddConnection(context, link: link));
  }

  @override
  void dispose() {
    _app?.removeListener(_onAppChange);
    vm.removeListener(_onChange);
    vm.toggle.removeListener(_onToggle);
    _ticker?.cancel();
    _glide.dispose();
    super.dispose();
  }

  void _onChange() {
    // Connecting and connected share the corner layout; the button only goes
    // back to the middle when the connection ends.
    final active = vm.status.active;
    if (active != (_glide.status == AnimationStatus.forward || _glide.status == AnimationStatus.completed)) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _glide.value = active ? 1 : 0;
      } else if (active) {
        unawaited(_glide.forward());
      } else {
        unawaited(_glide.reverse());
      }
    }
    final phase = vm.status.phase;
    if (phase == VpnPhase.waitingSso) unawaited(vm.openSsoOnce());
    if (phase != _lastPhase) {
      if (phase == VpnPhase.connected) {
        unawaited(HapticFeedback.heavyImpact());
        vm.offerQuickSettingsTile();
      }
      // A light tap, not an alarm: most failures are expected and fixable.
      if (phase == VpnPhase.error) unawaited(HapticFeedback.mediumImpact());
      // The tunnel dropped: a tap so the user notices even with the screen in view.
      final dropped = phase == VpnPhase.reconnecting || phase == VpnPhase.waitingNetwork;
      if (_lastPhase == VpnPhase.connected && dropped) unawaited(HapticFeedback.mediumImpact());
      _lastPhase = phase;
    }
  }

  Future<void> _onToggle() async {
    final result = vm.toggle.result;
    if (result is! Ok<ToggleOutcome>) return;
    vm.toggle.clearResult();
    switch (result.value) {
      case ToggleOutcome.needsSetup:
        await openAddConnection(context);
      case ToggleOutcome.needsPassword:
        await _updatePassword();
      case ToggleOutcome.permissionDenied:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.vpnPermissionNeeded)));
      case ToggleOutcome.unlockCancelled:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.errorLocked)));
      case ToggleOutcome.started || ToggleOutcome.stopped:
        break;
    }
  }

  /// Asks for the password and connects with it once it's saved.
  Future<void> _updatePassword() async {
    final profile = vm.selected;
    if (profile == null) return;
    if (await showPasswordSheet(context, profile: profile)) unawaited(vm.toggle.execute());
  }

  void _cancel() => unawaited(vm.toggle.execute());

  Future<void> _editSelected() async {
    final id = vm.selectedId;
    if (id == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProfileEditorScreen(profileId: id)));
  }

  void _explainLockedSwitch() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.switchWhileConnected)));
  }

  String _subtitle(AppLocalizations l10n, VpnStatus s) {
    switch (s.phase) {
      case VpnPhase.connected:
        final since = s.connectedSince;
        if (since == null) return '';
        final d = widget.clock().difference(since);
        String two(int n) => n.toString().padLeft(2, '0');
        return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
      case VpnPhase.idle:
        return l10n.tapToConnect;
      case VpnPhase.error:
        return s.error == null ? '' : l10n.error(s.error!, attempts: s.maxAttempts);
      default:
        return l10n.stepLabel(s);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final b = context.brand;
        final l10n = context.l10n;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayFor(context),
          child: Scaffold(
            body: SafeArea(
              child: CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: maxContentWidth),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 56,
                                child: Row(
                                  children: [
                                    const Wordmark(size: 26),
                                    const Spacer(),
                                    IconButton(
                                      tooltip: l10n.settingsTooltip,
                                      onPressed: () => unawaited(
                                        Navigator.of(context)
                                            .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
                                      ),
                                      icon: Icon(Icons.tune_rounded, color: b.ink),
                                    ),
                                  ],
                                ),
                              ),
                              if (vm.profiles.isEmpty) ..._empty(b, l10n) else ..._main(b, l10n),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _empty(Brand b, AppLocalizations l10n) => [
    const Spacer(flex: 2),
    Icon(Icons.vpn_lock_rounded, size: 56, color: b.accent),
    const SizedBox(height: 20),
    Text(
      l10n.noProfilesTitle,
      textAlign: TextAlign.center,
      style: TextStyle(fontFamily: serif, fontSize: 36, height: 1.1, color: b.ink),
    ),
    const SizedBox(height: 10),
    Text(
      l10n.noProfilesBody,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 15, height: 1.5, color: b.muted),
    ),
    const Spacer(flex: 3),
    FilledButton(onPressed: () => unawaited(openAddConnection(context)), child: Text(l10n.addConnection)),
  ];

  /// Idle, connected or failed: the big button with the status above it.
  List<Widget> _resting(Brand b, AppLocalizations l10n, VpnStatus status) {
    final color = statusColor(status, b);
    final profile = vm.selected;
    final subtitle = _subtitle(l10n, status);
    return [
      const Spacer(flex: 2),
      _profileName(b, profile?.name, TextAlign.center),
      const SizedBox(height: 8),
      _headline(status, status.phase == VpnPhase.idle ? b.ink : color, 44, TextAlign.center),
      const SizedBox(height: 8),
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: AnimatedSwitcher(
          duration: motion(context, const Duration(milliseconds: 220)),
          child: Semantics(
            key: ValueKey(status.phase == VpnPhase.connected ? 'timer' : subtitle),
            // The reason for a failure is spoken along with the headline.
            liveRegion: status.phase == VpnPhase.error,
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: status.phase == VpnPhase.connected ? 17 : 15,
                height: 1.35,
                color: status.phase == VpnPhase.error ? b.bad : b.muted,
                fontWeight: status.phase == VpnPhase.connected ? FontWeight.w500 : FontWeight.w400,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
      const Spacer(),
      SizedBox.square(key: _restSlot, dimension: 236),
      const SizedBox(height: 22),
      if (status.phase == VpnPhase.error)
        TextButton.icon(
          onPressed: () => unawaited(
            showErrorSheet(
              context,
              vm: vm,
              onEdit: () => unawaited(_editSelected()),
              onUpdatePassword: () => unawaited(_updatePassword()),
            ),
          ),
          icon: const Icon(Icons.info_outline_rounded, size: 18),
          label: Text(l10n.details),
        )
      else
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            [
              if (status.phase == VpnPhase.connected && status.ip != null) l10n.tunnelIp(status.ip!),
              if (profile != null)
                status.phase == VpnPhase.connected ? status.host ?? profile.address : profile.address,
            ].join('   ·   '),
            style: TextStyle(fontSize: 13, color: b.muted, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
      const Spacer(),
    ];
  }

  /// While connecting: a small button beside the headline, the steps with
  /// the current one explained, and the latest activity, so the user can see
  /// it is working and why it is retrying.
  List<Widget> _connecting(
    Brand b,
    AppLocalizations l10n,
    VpnStatus status, {
    required bool compactFeed,
    required double t,
    bool returning = false,
  }) {
    // Arriving: parts come in one after another. Returning: they all fade together.
    double stage(double begin, double end) =>
        returning ? t : Interval(begin, end, curve: Curves.easeOutCubic).transform(t);
    final header = stage(0.3, 0.8);
    final card = stage(0.3, 0.9);
    final feed = stage(0.6, 1);
    final profile = vm.selected;
    final startedAt = status.startedAt;
    final activity = vm.recentActivity(max: compactFeed ? 3 : 5);
    final connected = status.phase == VpnPhase.connected;
    final facts = ConnectionFacts(l10n, status, profile, widget.clock());
    return [
      const SizedBox(height: 20),
      Row(
        children: [
          // The travelling button lands here.
          SizedBox.square(key: _connSlot, dimension: 104),
          const SizedBox(width: 18),
          Expanded(
            child: Opacity(
              opacity: header,
              child: Transform.translate(
                offset: Offset(returning ? 0 : 28 * (1 - header), 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _profileName(b, profile?.name, TextAlign.start),
                    const SizedBox(height: 4),
                    _headline(status, statusColor(status, b), 40, TextAlign.start),
                    if (connected || startedAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        connected
                            ? '${facts.uptime} · ${facts.latency}'
                            : l10n.tryingFor(_clock(widget.clock().difference(startedAt!))),
                        style: TextStyle(
                          fontSize: 14,
                          color: b.muted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      Opacity(
        opacity: card,
        child: Transform.translate(
          offset: Offset(0, returning ? 0 : 40 * (1 - card)),
          // The steps card turns into the facts card when the tunnel is up.
          child: AnimatedSwitcher(
            duration: motion(context, const Duration(milliseconds: 360)),
            switchInCurve: Curves.easeOutCubic,
            layoutBuilder: (current, previous) =>
                Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
            child: connected
                ? Column(
                    key: const ValueKey('facts'),
                    children: [
                      if (_recentRejoin() case final reason?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Semantics(
                            liveRegion: true,
                            child: Row(
                              children: [
                                const SizedBox(width: 4),
                                Icon(Icons.sync_rounded, size: 16, color: b.ok),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    l10n.reconnectedAfter(l10n.error(reason)),
                                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: b.ok),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ConnectedFactsCard(facts: facts),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const SizedBox(width: 4),
                          Icon(
                            status.certSha256 != null ? Icons.verified_user_rounded : Icons.lock_rounded,
                            size: 15,
                            color: b.ok,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(facts.certificateNote, style: TextStyle(fontSize: 13, color: b.muted)),
                          ),
                        ],
                      ),
                    ],
                  )
                : ConnectTimeline(key: const ValueKey('steps'), status: status, reveal: stage(0.35, 1)),
          ),
        ),
      ),
      if (!connected && activity.isNotEmpty) ...[
        const SizedBox(height: 10),
        Opacity(
          opacity: feed,
          child: ActivityFeed(
            entries: activity,
            onSeeAll: () => unawaited(
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ActivityLogScreen())),
            ),
          ),
        ),
      ],
      const Spacer(),
      // Waiting cards carry their own Cancel. Inside this layout, so it takes no
      // room from the resting layout while the button is still travelling.
      if (connected)
        Opacity(
          opacity: stage(0.7, 1),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _cancel,
                style: TextButton.styleFrom(foregroundColor: b.muted),
                child: Text(l10n.actionDisconnect),
              ),
              TextButton(
                onPressed: () => unawaited(
                  showConnectionDetails(
                    context,
                    facts: () => ConnectionFacts(context.l10n, vm.status, vm.selected, widget.clock()),
                    share: vm.shareDetails,
                  ),
                ),
                child: Text(l10n.allDetails),
              ),
            ],
          ),
        )
      else if (!compactFeed)
        Opacity(
          opacity: stage(0.7, 1),
          child: TextButton(
            onPressed: _cancel,
            style: TextButton.styleFrom(foregroundColor: b.muted),
            child: Text(l10n.cancel),
          ),
        ),
      const SizedBox(height: 8),
    ];
  }

  /// Both layouts stacked, cross-fading in stages, with the one button flying
  /// between its spot in each: big and centred at rest, small beside the
  /// headline while connecting. Positions are measured after layout.
  Widget _glideStack(Brand b, AppLocalizations l10n, {required bool compactFeed}) {
    final live = vm.status;
    if (live.active) {
      _busyStatus = live;
    } else {
      _restStatus = live;
    }
    final rest = _restStatus ?? live;
    final busy = _busyStatus ?? live;
    WidgetsBinding.instance.addPostFrameCallback(_measure);
    return AnimatedBuilder(
      animation: _glide,
      builder: (context, _) {
        final t = _glide.value;
        // Cancelling is not the entrance played backwards (that snaps the button
        // home at speed): the connecting parts fade out together, the button
        // glides back on an even ease, and the resting text fades in last.
        final returning = _glide.status == AnimationStatus.reverse;
        final back = 1 - t;
        final leave = returning
            ? 1 - const Interval(0.55, 1, curve: Curves.easeOut).transform(back)
            : const Interval(0, 0.3, curve: Curves.easeOut).transform(t);
        final orbT = returning
            ? 1 - const Interval(0.1, 1, curve: Curves.easeInOutCubic).transform(back)
            : const Interval(0, 0.75, curve: Cubic(0.2, 0.8, 0.2, 1)).transform(t);
        final connT = returning ? 1 - const Interval(0, 0.4, curve: Curves.easeIn).transform(back) : t;
        final from = _restRect;
        final to = _connRect;
        final orbRect = from == null || to == null ? null : Rect.lerp(from, to, orbT);
        return Stack(
          key: _stackKey,
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              ignoring: t > 0.5,
              child: ExcludeSemantics(
                excluding: t > 0.5,
                // Fades only: moving it would move the button's measured spot.
                child: Opacity(
                  opacity: 1 - leave,
                  child: Column(children: _resting(b, l10n, rest)),
                ),
              ),
            ),
            IgnorePointer(
              ignoring: t < 0.5,
              child: ExcludeSemantics(
                excluding: t < 0.5,
                child: Column(
                  children: _connecting(b, l10n, busy, compactFeed: compactFeed, t: connT, returning: returning),
                ),
              ),
            ),
            if (orbRect != null)
              Positioned.fromRect(
                rect: orbRect,
                child: ConnectOrb(
                  status: live,
                  name: vm.selected?.name,
                  size: orbRect.width,
                  onTap: () => unawaited(vm.toggle.execute()),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Where the button's two spots are, relative to the stack.
  void _measure(Duration _) {
    if (!mounted) return;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    Rect? spot(GlobalKey key) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (stack == null || box == null || !box.hasSize || !stack.hasSize) return null;
      return box.localToGlobal(Offset.zero, ancestor: stack) & box.size;
    }

    final rest = spot(_restSlot);
    final conn = spot(_connSlot);
    if (rest != _restRect || conn != _connRect) {
      setState(() {
        _restRect = rest;
        _connRect = conn;
      });
    }
  }

  /// Shown for a few seconds after the tunnel comes back from a drop.
  VpnErrorCode? _recentRejoin() {
    final r = vm.lastRejoin;
    if (r == null || widget.clock().difference(r.at) > const Duration(seconds: 10)) return null;
    return r.reason;
  }

  Widget _profileName(Brand b, String? name, TextAlign align) => Text(
    (name ?? '').toUpperCase(),
    semanticsLabel: name,
    textAlign: align,
    style: TextStyle(fontSize: 12, letterSpacing: 2.6, fontWeight: FontWeight.w600, color: b.muted),
  );

  Widget _headline(VpnStatus status, Color color, double size, TextAlign align) {
    final l10n = context.l10n;
    return Semantics(
      liveRegion: true,
      child: AnimatedSwitcher(
        duration: motion(context, const Duration(milliseconds: 280)),
        layoutBuilder: (current, previous) => Stack(
          alignment: align == TextAlign.center ? Alignment.center : AlignmentDirectional.centerStart,
          children: [...previous, ?current],
        ),
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(a),
            child: c,
          ),
        ),
        child: Text(
          l10n.headline(status.phase),
          key: ValueKey(status.phase == VpnPhase.idle ? 'idle' : l10n.headline(status.phase)),
          textAlign: align,
          style: TextStyle(fontFamily: serif, fontSize: size, height: 1.05, color: color),
        ),
      ),
    );
  }

  /// 0:41, or 1:02:05 past an hour.
  String _clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = d.inMinutes % 60;
    return d.inHours > 0 ? '${d.inHours}:${two(m)}:${two(d.inSeconds % 60)}' : '$m:${two(d.inSeconds % 60)}';
  }

  List<Widget> _main(Brand b, AppLocalizations l10n) {
    final status = vm.status;
    final profiles = vm.profiles;
    final waiting = const {VpnPhase.waitingOtp, VpnPhase.waitingPush, VpnPhase.waitingSso}.contains(status.phase);
    return [
      Expanded(child: _glideStack(b, l10n, compactFeed: waiting)),
      AnimatedSize(
        duration: motion(context, const Duration(milliseconds: 320)),
        curve: Curves.easeOutCubic,
        child: switch (status.phase) {
          VpnPhase.waitingOtp => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: CodeCard(
              status: status,
              submit: vm.submitOtp,
              onFixEmail: () => unawaited(_editSelected()),
              onCancel: _cancel,
              clock: widget.clock,
            ),
          ),
          VpnPhase.waitingPush => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: PushCard(onUseCode: () => unawaited(vm.useCodeInstead.execute()), onCancel: _cancel),
          ),
          VpnPhase.waitingSso => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SsoCard(
              onOpen: () => unawaited(vm.openSso.execute()),
              onCancel: _cancel,
              deadline: status.deadline,
              clock: widget.clock,
            ),
          ),
          _ => const SizedBox(width: double.infinity),
        },
      ),
      if (profiles.length >= 2 && profiles.length <= 3)
        Segmented<String>(
          items: [for (final p in profiles) (p.id, p.name)],
          value: vm.selectedId ?? profiles.first.id,
          onChanged: vm.canChangeSite ? vm.select : null,
          disabledHint: l10n.switchWhileConnected,
          onDisabledTap: _explainLockedSwitch,
        )
      else if (profiles.length > 3)
        ProfilePicker(
          profiles: profiles,
          selectedId: vm.selectedId,
          enabled: vm.canChangeSite,
          onDisabledTap: _explainLockedSwitch,
          onSelect: vm.select,
          onAdd: () => unawaited(openAddConnection(context)),
        ),
    ];
  }
}
