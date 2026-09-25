import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import '../../core/toolbox/tool.dart';
import 'buttons.dart';

/// Small rounded label (e.g. "GPU", "H.264").
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = color ?? c.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color == null ? c.surfaceAlt : fg.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color == null ? c.border : fg.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: fg), const SizedBox(width: 3)],
          Text(
            text,
            style: TextStyles.caption.copyWith(color: fg, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Category-coloured rounded icon tile. [ToolIcon.of] renders the vivid
/// gradient style used for tool identity; the default is a soft tint.
class ToolIcon extends StatelessWidget {
  const ToolIcon({
    super.key,
    required this.icon,
    required this.color,
    this.color2,
    this.size = 36,
    this.muted = false,
  });

  ToolIcon.of(ToolDefinition tool, {Key? key, double size = 36, bool muted = false})
    : this(
        key: key,
        icon: tool.icon,
        color: tool.category.color,
        color2: tool.category.color2,
        size: size,
        muted: muted,
      );

  final IconData icon;
  final Color color;

  /// Second gradient stop; when set the tile is solid with a white glyph.
  final Color? color2;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(size * 0.3);
    if (muted) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: radius,
          border: Border.all(color: c.border),
        ),
        child: Icon(icon, size: size * 0.5, color: c.textSubtle),
      );
    }
    if (color2 != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color2!],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: c.isDark ? 0.28 : 0.3),
              blurRadius: size * 0.3,
              offset: Offset(0, size * 0.08),
            ),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Icon(icon, size: size * 0.52, color: Colors.white),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: c.isDark ? 0.16 : 0.12),
        borderRadius: radius,
      ),
      child: Icon(icon, size: size * 0.52, color: color),
    );
  }
}

/// Monospace command block with copy button.
class CommandPreview extends StatelessWidget {
  const CommandPreview({super.key, required this.command, this.maxHeight = 160});
  final String command;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: c.codeBg,
        borderRadius: BorderRadius.circular(Radii.control + 2),
        border: Border.all(color: c.border),
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.md, 40, Space.md),
            child: SelectableText(command, style: TextStyles.mono.copyWith(color: c.textMuted)),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: AppIconButton(
              icon: Icons.copy_rounded,
              tooltip: 'common.copy'.tr(),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: command));
                showToast(context, 'common.copied'.tr());
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline notice banner.
class Notice extends StatelessWidget {
  const Notice({super.key, required this.message, this.tone = NoticeTone.info, this.action});
  final String message;
  final NoticeTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (color, icon) = switch (tone) {
      NoticeTone.info => (c.accent, Icons.info_outline_rounded),
      NoticeTone.warning => (c.warning, Icons.warning_amber_rounded),
      NoticeTone.danger => (c.danger, Icons.error_outline_rounded),
      NoticeTone.success => (c.success, Icons.check_circle_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(Radii.control + 2),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(message, style: TextStyles.body.copyWith(color: c.text)),
          ),
          if (action != null) ...[const SizedBox(width: Space.sm), action!],
        ],
      ),
    );
  }
}

enum NoticeTone { info, warning, danger, success }

void showToast(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
      ),
    );
}
