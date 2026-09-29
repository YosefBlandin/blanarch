import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models/vpn_status.dart';
import '../l10n/l10n.dart';
import '../theme/status_colors.dart';
import '../theme/theme.dart';

class ConnectOrb extends StatefulWidget {
  final VpnStatus status;
  final VoidCallback? onTap;
  final double size;

  /// The connection this button acts on, read by screen readers.
  final String? name;
  const ConnectOrb({super.key, required this.status, this.onTap, this.size = 236, this.name});

  @override
  State<ConnectOrb> createState() => _ConnectOrbState();
}

class _ConnectOrbState extends State<ConnectOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
  bool _down = false;

  /// Animates only while something is happening, so an idle home screen costs no frames.
  void _syncMotion() {
    final moving =
        (widget.status.busy || widget.status.phase == VpnPhase.connected) && !MediaQuery.disableAnimationsOf(context);
    if (moving && !_c.isAnimating) {
      unawaited(_c.repeat());
    } else if (!moving && _c.isAnimating) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(ConnectOrb old) {
    super.didUpdateWidget(old);
    _syncMotion();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final s = widget.status;
    final connected = s.phase == VpnPhase.connected;
    final l10n = context.l10n;
    final label = switch (s.phase) {
      VpnPhase.connected => l10n.actionDisconnect,
      VpnPhase.idle || VpnPhase.error => widget.name == null ? l10n.actionConnect : l10n.connectTo(widget.name!),
      _ => l10n.actionCancelConnecting,
    };
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.96 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: statusColor(s, b)),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOut,
            builder: (context, color, _) => TweenAnimationBuilder<double>(
              tween: Tween(end: connected ? 1 : 0),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (context, fill, _) => AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  size: Size.square(widget.size),
                  painter: _OrbPainter(
                    t: _c.value,
                    color: color!,
                    fill: fill,
                    busy: s.busy,
                    brand: b,
                    dark: Theme.of(context).brightness == Brightness.dark,
                  ),
                  child: SizedBox.square(
                    dimension: widget.size,
                    child: Center(
                      child: Icon(
                        Icons.power_settings_new_rounded,
                        size: widget.size * 0.23,
                        color: Color.lerp(color, b.onAccent, fill),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double t, fill;
  final Color color;
  final bool busy, dark;
  final Brand brand;
  _OrbPainter({
    required this.t,
    required this.color,
    required this.fill,
    required this.busy,
    required this.brand,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final core = size.width * 0.33;
    final ring = core + size.width * 0.068;

    // Radiating rings once connected.
    if (fill > 0) {
      for (var i = 0; i < 3; i++) {
        final p = (t + i / 3) % 1.0;
        final r = ring + p * (size.width / 2 - ring);
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = color.withValues(alpha: (1 - p) * 0.45 * fill),
        );
      }
    }

    // Soft shadow under the disc.
    canvas.drawCircle(
      c.translate(0, 10),
      core,
      Paint()
        ..color = Colors.black.withValues(alpha: dark ? 0.45 : 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );

    // Track ring.
    final ringRect = Rect.fromCircle(center: c, radius: ring);
    canvas.drawCircle(
      c,
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Color.lerp(brand.outline, color, fill * 0.5)!,
    );

    // Travelling arc while connecting.
    if (busy) {
      final start = t * 2 * math.pi * 2 - math.pi / 2;
      final sweep = math.pi * (0.35 + 0.25 * math.sin(t * 2 * math.pi));
      canvas.drawArc(
        ringRect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }

    // Disc: ivory when idle, filled with the status colour when connected.
    final discRect = Rect.fromCircle(center: c, radius: core);
    final base = Color.lerp(brand.surface, color, fill)!;
    canvas.drawCircle(
      c,
      core,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(base, Colors.white, dark ? 0.04 : 0.5)!, Color.lerp(base, Colors.black, 0.06)!],
        ).createShader(discRect),
    );
    canvas.drawCircle(
      c,
      core,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Color.lerp(brand.border, color, fill)!.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter o) =>
      o.t != t || o.color != color || o.fill != fill || o.busy != busy || o.brand != brand || o.dark != dark;
}
