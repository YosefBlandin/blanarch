import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Brand palette. Warm beige/linen surfaces, espresso ink, a bronze accent,
/// and muted status colours (sage / amber / terracotta) that stay calm under
/// stress. Text colours meet WCAG AA (4.5:1) on bg and surface; [outline]
/// meets 3:1 for field and switch edges, [border] is only for dividers.
@immutable
class Brand extends ThemeExtension<Brand> {
  final Color bg, surface, surfaceAlt, border, outline, ink, muted, accent, onAccent, ok, busy, bad;
  const Brand({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.outline,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.ok,
    required this.busy,
    required this.bad,
  });

  static const light = Brand(
    bg: Color(0xFFF3ECE1), // linen
    surface: Color(0xFFFBF8F2), // ivory
    surfaceAlt: Color(0xFFEAE1D2), // sand
    border: Color(0xFFDFD2BE),
    outline: Color(0xFF907C63),
    ink: Color(0xFF2A241E), // espresso
    muted: Color(0xFF6E6356), // taupe
    accent: Color(0xFF7A5B39), // bronze
    onAccent: Color(0xFFFFFAF2),
    ok: Color(0xFF466F52), // sage
    busy: Color(0xFF9C7130), // amber
    bad: Color(0xFFAE4E38), // terracotta
  );

  static const dark = Brand(
    bg: Color(0xFF16130F),
    surface: Color(0xFF211D18),
    surfaceAlt: Color(0xFF2B261F),
    border: Color(0xFF3A3229),
    outline: Color(0xFF807262),
    ink: Color(0xFFF1E9DC),
    muted: Color(0xFFA99C8B),
    accent: Color(0xFFD2B48A), // champagne
    onAccent: Color(0xFF1E1812),
    ok: Color(0xFF93C4A0),
    busy: Color(0xFFE2B665),
    bad: Color(0xFFE8907A),
  );

  @override
  Brand copyWith() => this;

  @override
  Brand lerp(ThemeExtension<Brand>? other, double t) {
    if (other is! Brand) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Brand(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      border: l(border, other.border),
      outline: l(outline, other.outline),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      ok: l(ok, other.ok),
      busy: l(busy, other.busy),
      bad: l(bad, other.bad),
    );
  }
}

extension BrandContext on BuildContext {
  Brand get brand => Theme.of(this).extension<Brand>()!;
}

const serif = 'InstrumentSerif';

ThemeData buildTheme(Brand b, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: b.accent,
    brightness: brightness,
    primary: b.accent,
    onPrimary: b.onAccent,
    surface: b.bg,
    onSurface: b.ink,
    error: b.bad,
    outline: b.outline,
    outlineVariant: b.border,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: b.bg,
    extensions: [b],
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: b.ink, displayColor: b.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: b.bg,
      foregroundColor: b.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: _overlay(b, brightness),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: b.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      labelStyle: TextStyle(color: b.muted),
      hintStyle: TextStyle(color: b.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: b.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: b.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: b.accent, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: b.bad),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: b.bad, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: b.ink,
        foregroundColor: b.bg,
        disabledBackgroundColor: b.surfaceAlt,
        disabledForegroundColor: b.muted,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: b.accent,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: b.bg,
      showDragHandle: true,
      dragHandleColor: b.border,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dividerTheme: DividerThemeData(color: b.border, thickness: 1, space: 1),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: PredictiveBackPageTransitionsBuilder()},
    ),
  );
}

SystemUiOverlayStyle _overlay(Brand b, Brightness brightness) => SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  systemNavigationBarColor: b.bg,
  statusBarIconBrightness: brightness == Brightness.light ? Brightness.dark : Brightness.light,
  systemNavigationBarIconBrightness: brightness == Brightness.light ? Brightness.dark : Brightness.light,
);

SystemUiOverlayStyle overlayFor(BuildContext context) => _overlay(context.brand, Theme.of(context).brightness);

/// [duration], or next to none when the user turned animations off in Android
/// settings. Not zero: AnimatedSize asserts on a zero duration.
Duration motion(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? const Duration(milliseconds: 1) : duration;

/// Content never gets wider than this, so tablets and landscape don't stretch it.
const maxContentWidth = 560.0;

/// Padding for a scrolling page: 24 at the sides (more on wide screens, so the
/// content stays [maxContentWidth]) and room for the navigation bar at the bottom.
EdgeInsets pagePadding(BuildContext context, {double top = 8, double bottom = 32}) {
  final side = ((MediaQuery.sizeOf(context).width - maxContentWidth) / 2).clamp(24.0, double.infinity);
  return EdgeInsets.fromLTRB(side, top, side, bottom + MediaQuery.paddingOf(context).bottom);
}
