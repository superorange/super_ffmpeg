import 'package:flutter/material.dart';

import 'tokens.dart';

abstract final class AppTheme {
  /// Null in the app (platform system font). Set by screenshot tests, which
  /// have no system font and must load one explicitly.
  @visibleForTesting
  static String? fontFamilyOverride;

  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: c.accent,
          brightness: brightness,
        ).copyWith(
          primary: c.accent,
          onPrimary: c.onAccent,
          surface: c.surface,
          onSurface: c.text,
          onSurfaceVariant: c.textMuted,
          outline: c.border,
          outlineVariant: c.border,
          error: c.danger,
          surfaceContainerHighest: c.surfaceAlt,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      dividerColor: c.border,
      splashFactory: NoSplash.splashFactory,
      hoverColor: c.hover,
      highlightColor: Colors.transparent,
      visualDensity: VisualDensity.compact,
      extensions: [c],
    );

    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.control),
      borderSide: BorderSide(color: color, width: width),
    );

    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(
            bodyMedium: TextStyles.body,
            bodySmall: TextStyles.caption,
            labelLarge: TextStyles.label,
            titleMedium: TextStyles.heading,
            titleLarge: TextStyles.title,
          )
          .apply(bodyColor: c.text, displayColor: c.text, fontFamily: fontFamilyOverride),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accent.withValues(alpha: 0.28),
        selectionHandleColor: c.accent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: c.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        hintStyle: TextStyles.body.copyWith(color: c.textSubtle),
        border: border(c.border),
        enabledBorder: border(c.border),
        focusedBorder: border(c.accent, 1.5),
        errorBorder: border(c.danger),
        focusedErrorBorder: border(c.danger, 1.5),
        errorStyle: TextStyles.caption.copyWith(color: c.danger),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        textStyle: TextStyles.caption.copyWith(color: c.bg),
        decoration: BoxDecoration(
          color: c.text,
          borderRadius: BorderRadius.circular(Radii.control),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.text,
        contentTextStyle: TextStyles.body.copyWith(color: c.bg),
        actionTextColor: c.accent,
        width: 420,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: c.accent,
        inactiveTrackColor: c.border,
        thumbColor: c.accent,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7, elevation: 0),
        rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 7, elevation: 0),
        showValueIndicator: ShowValueIndicator.never,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onAccent : c.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.accent : c.surfaceAlt,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.accent : c.borderStrong,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: c.borderStrong, width: 1.5),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.surfaceAlt,
        circularTrackColor: Colors.transparent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(5),
        radius: const Radius.circular(3),
        thumbColor: WidgetStateProperty.all(c.textSubtle.withValues(alpha: 0.35)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.elevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.panel),
          side: BorderSide(color: c.border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.elevated,
        elevation: 12,
        shadowColor: c.shadow,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyles.body.copyWith(color: c.text),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: c.border),
        ),
      ),
    );
  }
}
