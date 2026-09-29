import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/theme/theme.dart';

/// Opening animation: on linen beige, the letters of "Blanarch" rise
/// out of a soft blur one after another, then a bronze hairline draws
/// beneath them and the tagline settles in.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashState();
}

class _SplashState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  static const _word = 'Blanarch';
  static const _accentFrom = 4; // "arch"

  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = 1;
      Future.delayed(const Duration(milliseconds: 300), widget.onDone);
    } else {
      // Short enough to open a VPN app many times a day: about 1.6 s in all.
      _c.forward().whenComplete(() => Future.delayed(const Duration(milliseconds: 200), widget.onDone));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Progress of an interval [start, start+len] of the timeline, eased.
  double _seg(double start, double len, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((_c.value - start) / len).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    const b = Brand.light; // the brand moment is always beige
    final width = MediaQuery.of(context).size.width;
    // Fits the word with generous margins; capped so tablets don't get a giant word.
    final fontSize = ((width - 64) / 4.4).clamp(40.0, 120.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: b.bg,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Material(
        color: b.bg,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final settle = _seg(0.0, 0.9, Curves.easeOutQuart);
            return Stack(
              children: [
                // Warm vignette that blooms in very slightly.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        radius: 0.9,
                        colors: [Color.lerp(b.bg, Colors.white, 0.35 * _seg(0, 0.6))!, b.bg],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: 1.035 - 0.035 * settle,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [for (var i = 0; i < _word.length; i++) _letter(i, fontSize, b)],
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Hairline drawn from the centre outwards.
                      Container(
                        width: 64 * _seg(0.62, 0.3),
                        height: 1.2,
                        decoration: BoxDecoration(
                          color: b.accent.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Opacity(
                        opacity: _seg(0.72, 0.28),
                        child: Transform.translate(
                          offset: Offset(0, 6 * (1 - _seg(0.72, 0.28))),
                          child: Text(
                            context.l10n.splashTagline,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              letterSpacing: 3.2,
                              fontWeight: FontWeight.w500,
                              color: b.muted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _letter(int i, double fontSize, Brand b) {
    // Letters start 55ms apart; each takes ~560ms to arrive.
    final p = _seg(0.04 + i * 0.026, 0.27);
    final accent = i >= _accentFrom;
    final blur = 10 * (1 - p);
    Widget glyph = Text(
      _word[i],
      style: TextStyle(
        fontFamily: serif,
        fontSize: fontSize,
        height: 1.0,
        fontStyle: accent ? FontStyle.italic : FontStyle.normal,
        color: accent ? b.accent : b.ink,
        letterSpacing: -0.2,
      ),
    );
    if (blur > 0.05) {
      glyph = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: glyph,
      );
    }
    return Opacity(
      opacity: p,
      child: Transform.translate(offset: Offset(0, fontSize * 0.28 * (1 - p)), child: glyph),
    );
  }
}
