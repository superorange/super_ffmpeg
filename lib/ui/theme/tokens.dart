import 'package:flutter/material.dart';

/// Design tokens (docs/DESIGN.md §1). Access via `context.colors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brightness,
    required this.bg,
    required this.sidebar,
    required this.surface,
    required this.surfaceAlt,
    required this.elevated,
    required this.hover,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textMuted,
    required this.textSubtle,
    required this.accent,
    required this.accent2,
    required this.onAccent,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.stage,
    required this.codeBg,
    required this.shadow,
  });

  final Brightness brightness;

  /// Window background.
  final Color bg;
  final Color sidebar;

  /// Cards and panels.
  final Color surface;

  /// Inputs, segmented tracks, wells.
  final Color surfaceAlt;

  /// Popovers, dialogs, selected segments — sits above [surface].
  final Color elevated;
  final Color hover;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color textMuted;
  final Color textSubtle;
  final Color accent;

  /// Second stop of the brand gradient.
  final Color accent2;
  final Color onAccent;
  final Color accentSoft;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  /// Media preview backdrop — always near-black so footage reads correctly.
  final Color stage;

  /// Code editors and command blocks.
  final Color codeBg;
  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  LinearGradient get brandGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accent2],
  );

  List<BoxShadow> get cardShadow => isDark
      ? const []
      : [
          BoxShadow(color: shadow, blurRadius: 2, offset: const Offset(0, 1)),
          BoxShadow(
            color: shadow.withValues(alpha: shadow.a * 0.6),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ];

  List<BoxShadow> get popShadow => [
    BoxShadow(color: shadow, blurRadius: 32, offset: const Offset(0, 16)),
    BoxShadow(
      color: shadow.withValues(alpha: shadow.a * 0.5),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static const dark = AppColors(
    brightness: Brightness.dark,
    bg: Color(0xFF0C0C10),
    sidebar: Color(0xFF111116),
    surface: Color(0xFF16161C),
    surfaceAlt: Color(0xFF1D1D25),
    elevated: Color(0xFF23232C),
    hover: Color(0xFF25252F),
    border: Color(0xFF26262F),
    borderStrong: Color(0xFF363642),
    text: Color(0xFFF1F1F4),
    textMuted: Color(0xFFA3A3B2),
    textSubtle: Color(0xFF6C6C7C),
    accent: Color(0xFF7C6CFF),
    accent2: Color(0xFFC06CFF),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0x2E7C6CFF),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFFB7185),
    info: Color(0xFF60A5FA),
    stage: Color(0xFF050507),
    codeBg: Color(0xFF101015),
    shadow: Color(0x80000000),
  );

  static const light = AppColors(
    brightness: Brightness.light,
    bg: Color(0xFFF6F6F9),
    sidebar: Color(0xFFEEEEF3),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF3F3F7),
    elevated: Color(0xFFFFFFFF),
    hover: Color(0xFFEAEAF0),
    border: Color(0xFFE4E4EB),
    borderStrong: Color(0xFFD2D2DC),
    text: Color(0xFF16161D),
    textMuted: Color(0xFF585866),
    textSubtle: Color(0xFF9696A6),
    accent: Color(0xFF6554F0),
    accent2: Color(0xFFA64DF5),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0x1F6554F0),
    success: Color(0xFF10A36B),
    warning: Color(0xFFD08700),
    danger: Color(0xFFE11D48),
    info: Color(0xFF2563EB),
    stage: Color(0xFF0B0B0E),
    codeBg: Color(0xFFFAFAFC),
    shadow: Color(0x14101028),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: l(bg, other.bg),
      sidebar: l(sidebar, other.sidebar),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      elevated: l(elevated, other.elevated),
      hover: l(hover, other.hover),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      textSubtle: l(textSubtle, other.textSubtle),
      accent: l(accent, other.accent),
      accent2: l(accent2, other.accent2),
      onAccent: l(onAccent, other.onAccent),
      accentSoft: l(accentSoft, other.accentSoft),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      info: l(info, other.info),
      stage: l(stage, other.stage),
      codeBg: l(codeBg, other.codeBg),
      shadow: l(shadow, other.shadow),
    );
  }
}

abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
}

abstract final class Radii {
  static const control = 8.0;
  static const card = 12.0;
  static const panel = 16.0;
}

abstract final class TextStyles {
  static const display = TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.6);
  static const title = TextStyle(fontSize: 19, fontWeight: FontWeight.w600, height: 1.3, letterSpacing: -0.3);
  static const heading = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35, letterSpacing: -0.1);
  static const body = TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.45);
  static const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.35);
  static const caption = TextStyle(fontSize: 11, fontWeight: FontWeight.w400, height: 1.35);
  static const overline = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, height: 1.3, letterSpacing: 0.6);
  static const mono = TextStyle(
    fontSize: 12.5,
    height: 1.55,
    fontFamily: 'Menlo',
    fontFamilyFallback: ['SF Mono', 'JetBrains Mono', 'Consolas', 'monospace'],
  );
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 180);
  static const slow = Duration(milliseconds: 260);
  static const curve = Curves.easeOutCubic;
}

extension ThemeTokens on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
