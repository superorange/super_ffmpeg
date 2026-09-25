import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum ButtonVariant { primary, secondary, ghost, danger }

enum ButtonSize { sm, md, lg }

class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = ButtonVariant.secondary,
    this.size = ButtonSize.md,
    this.loading = false,
    this.expand = false,
  });

  const AppButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.size = ButtonSize.md,
    this.loading = false,
    this.expand = false,
  }) : variant = ButtonVariant.primary;

  const AppButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.size = ButtonSize.md,
    this.loading = false,
    this.expand = false,
  }) : variant = ButtonVariant.ghost;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonVariant variant;
  final ButtonSize size;
  final bool loading;
  final bool expand;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onPressed != null && !widget.loading;
    final (Color bg, Color fg, Color? border) = switch (widget.variant) {
      ButtonVariant.primary => (c.accent, c.onAccent, null),
      ButtonVariant.secondary => (c.elevated, c.text, c.borderStrong),
      ButtonVariant.ghost => (Colors.transparent, c.textMuted, null),
      ButtonVariant.danger => (c.danger.withValues(alpha: 0.12), c.danger, null),
    };
    final hoverBg = switch (widget.variant) {
      ButtonVariant.primary => Color.lerp(c.accent, Colors.white, 0.1)!,
      ButtonVariant.secondary => c.hover,
      ButtonVariant.ghost => c.hover,
      ButtonVariant.danger => c.danger.withValues(alpha: 0.2),
    };
    final (double height, double padX, double font, double iconSize) = switch (widget.size) {
      ButtonSize.sm => (28.0, 10.0, 12.0, 14.0),
      ButtonSize.md => (34.0, 14.0, 13.0, 16.0),
      ButtonSize.lg => (42.0, 20.0, 14.0, 18.0),
    };

    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox.square(
            dimension: iconSize - 2,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (widget.icon != null)
          Icon(widget.icon, size: iconSize, color: fg),
        if (widget.icon != null || widget.loading) const SizedBox(width: 6),
        Flexible(
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: font, fontWeight: FontWeight.w500, color: fg),
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: () => setState(() => _pressed = false),
          onTap: enabled ? widget.onPressed : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: enabled ? 1 : 0.45,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 90),
              scale: _pressed ? 0.98 : 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: height,
                padding: EdgeInsets.symmetric(horizontal: padX),
                decoration: BoxDecoration(
                  color: enabled && _hover ? hoverBg : bg,
                  gradient: widget.variant == ButtonVariant.primary
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            enabled && _hover ? hoverBg : c.accent,
                            Color.lerp(enabled && _hover ? hoverBg : c.accent, c.accent2, 0.45)!,
                          ],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(Radii.control),
                  border: border == null ? null : Border.all(color: border),
                  boxShadow: widget.variant == ButtonVariant.primary && enabled
                      ? [BoxShadow(color: c.accent.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 3))]
                      : null,
                ),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Square icon-only button with a tooltip.
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 28,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onPressed != null;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: enabled && _hover ? c.hover : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Icon(
                widget.icon,
                size: widget.size * 0.57,
                color: enabled ? (widget.color ?? c.textMuted) : c.textSubtle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
