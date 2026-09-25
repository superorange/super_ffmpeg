import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/toolbox/tool.dart';
import '../theme/tokens.dart';
import 'buttons.dart';
import 'feedback.dart';

/// Page frame for every non-media tool (docs/DESIGN.md §2.2):
/// header (icon · title · description · actions) · optional toolbar · body.
class ToolScaffold extends StatefulWidget {
  const ToolScaffold({
    super.key,
    required this.tool,
    required this.body,
    this.actions = const [],
    this.toolbar,
    this.padding = const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.xxl),
    this.scrollable = false,
    this.onFiles,
  });

  final ToolDefinition tool;
  final Widget body;
  final List<Widget> actions;

  /// Options row shown between the header and the body.
  final Widget? toolbar;
  final EdgeInsets padding;

  /// Body scrolls as a page instead of filling the remaining height.
  final bool scrollable;

  /// Accept files dropped anywhere on the page.
  final ValueChanged<List<String>>? onFiles;

  @override
  State<ToolScaffold> createState() => _ToolScaffoldState();
}

class _ToolScaffoldState extends State<ToolScaffold> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tool = widget.tool;
    final actions = widget.actions;
    final toolbar = widget.toolbar;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(Space.xxl, 22, Space.xxl, Space.lg),
      child: Row(
        children: [
          ToolIcon.of(tool, size: 38),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tool.nameKey.tr(), style: TextStyles.title.copyWith(color: c.text)),
                const SizedBox(height: 1),
                Text(
                  tool.descKey.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.body.copyWith(color: c.textMuted),
                ),
              ],
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: Space.sm), a],
        ],
      ),
    );

    final content = Padding(padding: widget.padding, child: widget.body);
    final page = Scaffold(
      backgroundColor: c.bg,
      body: widget.scrollable
          ? ListView(
              children: [
                header,
                if (toolbar != null) _ToolbarStrip(child: toolbar),
                content,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                if (toolbar != null) _ToolbarStrip(child: toolbar),
                Expanded(child: content),
              ],
            ),
    );
    if (widget.onFiles == null) return page;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) {
        setState(() => _dragging = false);
        if (d.files.isNotEmpty) widget.onFiles!([for (final f in d.files) f.path]);
      },
      child: Stack(
        children: [
          Positioned.fill(child: page),
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(Radii.panel),
                    border: Border.all(color: c.accent, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text('common.drop_to_open'.tr(), style: TextStyles.title.copyWith(color: c.accent)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolbarStrip extends StatelessWidget {
  const _ToolbarStrip({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.md),
      child: child,
    );
  }
}

/// Horizontal group of labelled toolbar controls that wraps when narrow.
class ToolbarRow extends StatelessWidget {
  const ToolbarRow({super.key, required this.children, this.trailing});
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            spacing: Space.lg,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: children,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: Space.md), trailing!],
      ],
    );
  }
}

/// A small caption + control pair for [ToolbarRow].
class ToolbarField extends StatelessWidget {
  const ToolbarField({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyles.label.copyWith(color: context.colors.textSubtle)),
        const SizedBox(width: Space.sm),
        child,
      ],
    );
  }
}

/// Titled card that fills its space: header (title · actions), body, footer.
class Pane extends StatelessWidget {
  const Pane({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.actions = const [],
    this.footer,
    this.padding = EdgeInsets.zero,
    this.color,
    this.headerExtra,
    this.shrinkWrap = false,
  });

  final Widget child;

  /// Size to the child instead of filling the available height.
  final bool shrinkWrap;
  final String? title;
  final IconData? icon;
  final List<Widget> actions;
  final Widget? footer;
  final EdgeInsets padding;
  final Color? color;

  /// Widget placed right after the title (e.g. a mode switch).
  final Widget? headerExtra;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.border),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (title != null || actions.isNotEmpty)
            Container(
              height: 40,
              padding: const EdgeInsets.only(left: 14, right: 6),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: c.textSubtle),
                    const SizedBox(width: 7),
                  ],
                  if (title != null)
                    Text(
                      title!,
                      style: TextStyles.label.copyWith(color: c.textMuted, fontWeight: FontWeight.w600),
                    ),
                  if (headerExtra != null) ...[const SizedBox(width: Space.md), headerExtra!],
                  const Spacer(),
                  for (final a in actions) Padding(padding: const EdgeInsets.only(left: 2), child: a),
                ],
              ),
            ),
          if (shrinkWrap)
            Padding(padding: padding, child: child)
          else
            Expanded(
              child: Padding(padding: padding, child: child),
            ),
          if (footer != null)
            Container(
              constraints: const BoxConstraints(minHeight: 32),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: c.surfaceAlt.withValues(alpha: 0.5),
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: footer,
            ),
        ],
      ),
    );
  }
}

/// Two panes side by side (or stacked when narrow) with a draggable divider.
class SplitPane extends StatefulWidget {
  const SplitPane({
    super.key,
    required this.first,
    required this.second,
    this.initial = 0.5,
    this.minExtent = 220,
    this.breakpoint = 760,
    this.vertical = false,
  });

  final Widget first;
  final Widget second;
  final double initial;
  final double minExtent;

  /// Below this width the panes stack vertically.
  final double breakpoint;

  /// Always stack (top/bottom) regardless of width.
  final bool vertical;

  @override
  State<SplitPane> createState() => _SplitPaneState();
}

class _SplitPaneState extends State<SplitPane> {
  late double _fraction = widget.initial;
  bool _hover = false;
  bool _drag = false;
  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        final vertical = widget.vertical || box.maxWidth < widget.breakpoint;
        final total = (vertical ? box.maxHeight : box.maxWidth) - _gap;
        if (!total.isFinite || total <= 0) {
          return Column(children: [widget.first, widget.second]);
        }
        final min = widget.minExtent.clamp(0.0, total / 2);
        final firstExtent = (total * _fraction).clamp(min, total - min);
        final handle = MouseRegion(
          cursor: vertical ? SystemMouseCursors.resizeRow : SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => setState(() => _drag = true),
            onPanEnd: (_) => setState(() => _drag = false),
            onDoubleTap: () => setState(() => _fraction = widget.initial),
            onPanUpdate: (d) => setState(() {
              final delta = vertical ? d.delta.dy : d.delta.dx;
              _fraction = ((firstExtent + delta) / total).clamp(min / total, 1 - min / total);
            }),
            child: SizedBox(
              width: vertical ? double.infinity : _gap,
              height: vertical ? _gap : double.infinity,
              child: Center(
                child: AnimatedContainer(
                  duration: Motion.fast,
                  width: vertical ? 36 : 3,
                  height: vertical ? 3 : 36,
                  decoration: BoxDecoration(
                    color: _hover || _drag ? c.accent : c.borderStrong.withValues(alpha: 0.0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        );
        final children = [
          SizedBox(
            width: vertical ? null : firstExtent,
            height: vertical ? firstExtent : null,
            child: widget.first,
          ),
          handle,
          Expanded(child: widget.second),
        ];
        return vertical
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
            : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
      },
    );
  }
}

/// Small icon button used in pane headers.
class PaneAction extends StatelessWidget {
  const PaneAction({super.key, required this.icon, required this.tooltip, this.onPressed, this.active = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      size: 28,
      color: active ? context.colors.accent : null,
    );
  }
}

/// Copies the value returned by [text] and confirms with a toast.
class CopyAction extends StatelessWidget {
  const CopyAction({super.key, required this.text, this.label});
  final String Function() text;
  final String? label;

  static void copy(BuildContext context, String value) {
    Clipboard.setData(ClipboardData(text: value));
    showToast(context, 'common.copied'.tr());
  }

  @override
  Widget build(BuildContext context) {
    if (label != null) {
      return AppButton.ghost(
        label: label!,
        icon: Icons.copy_rounded,
        size: ButtonSize.sm,
        onPressed: () => copy(context, text()),
      );
    }
    return PaneAction(
      icon: Icons.copy_rounded,
      tooltip: 'common.copy'.tr(),
      onPressed: () => copy(context, text()),
    );
  }
}

/// Editors notify their listeners while they mount (mid-build); defer
/// listener work that calls setState to after the frame in that case.
VoidCallback outsideBuild(VoidCallback f) => () {
  if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
    SchedulerBinding.instance.addPostFrameCallback((_) => f());
  } else {
    f();
  }
};

/// Paste-from-clipboard helper for input panes.
Future<String?> readClipboard() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;

enum StatusTone { neutral, success, warning, danger }

/// One-line status (validation result, counts…) for pane footers.
class StatusLine extends StatelessWidget {
  const StatusLine(this.text, {super.key, this.tone = StatusTone.neutral, this.trailing});
  final String text;
  final StatusTone tone;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (color, icon) = switch (tone) {
      StatusTone.neutral => (c.textSubtle, null),
      StatusTone.success => (c.success, Icons.check_circle_rounded),
      StatusTone.warning => (c.warning, Icons.warning_amber_rounded),
      StatusTone.danger => (c.danger, Icons.error_rounded),
    };
    return Row(
      children: [
        if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 5)],
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyles.caption.copyWith(
              color: tone == StatusTone.neutral ? c.textSubtle : color,
              fontWeight: tone == StatusTone.neutral ? FontWeight.w400 : FontWeight.w500,
            ),
          ),
        ),
        if (trailing != null) Text(trailing!, style: TextStyles.caption.copyWith(color: c.textSubtle)),
      ],
    );
  }
}

/// Read-only value row with a copy button — for converters that produce
/// several representations (hash digests, timestamps, colours…).
class ValueRow extends StatefulWidget {
  const ValueRow({
    super.key,
    required this.label,
    required this.value,
    this.mono = true,
    this.hint,
    this.leading,
    this.labelWidth = 128,
  });
  final String label;
  final double labelWidth;
  final String value;
  final bool mono;
  final String? hint;
  final Widget? leading;

  @override
  State<ValueRow> createState() => _ValueRowState();
}

class _ValueRowState extends State<ValueRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = (widget.mono ? TextStyles.mono : TextStyles.body).copyWith(color: c.text);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          color: _hover ? c.hover.withValues(alpha: 0.5) : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Row(
          children: [
            if (widget.label.isNotEmpty)
              SizedBox(
                width: widget.labelWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label, style: TextStyles.label.copyWith(color: c.textMuted)),
                    if (widget.hint != null)
                      Text(widget.hint!, style: TextStyles.caption.copyWith(color: c.textSubtle)),
                  ],
                ),
              ),
            if (widget.leading != null) ...[widget.leading!, const SizedBox(width: Space.sm)],
            Expanded(
              child: SelectableText(
                widget.value.isEmpty ? '—' : widget.value,
                style: widget.value.isEmpty ? style.copyWith(color: c.textSubtle) : style,
              ),
            ),
            AnimatedOpacity(
              duration: Motion.fast,
              opacity: _hover ? 1 : 0.35,
              child: PaneAction(
                icon: Icons.copy_rounded,
                tooltip: 'common.copy'.tr(),
                onPressed: widget.value.isEmpty ? null : () => CopyAction.copy(context, widget.value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plain multi-line text input styled like the code editors (for tools that
/// don't need line numbers or highlighting).
class TextArea extends StatelessWidget {
  const TextArea({
    super.key,
    required this.controller,
    this.hint,
    this.mono = true,
    this.readOnly = false,
    this.onChanged,
    this.expands = true,
    this.minLines,
  });

  final TextEditingController controller;
  final String? hint;
  final bool mono;
  final bool readOnly;
  final ValueChanged<String>? onChanged;
  final bool expands;
  final int? minLines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextField(
      controller: controller,
      readOnly: readOnly,
      onChanged: onChanged,
      expands: expands,
      minLines: expands ? null : minLines,
      maxLines: null,
      textAlignVertical: TextAlignVertical.top,
      style: (mono ? TextStyles.mono : TextStyles.body.copyWith(fontSize: 13.5, height: 1.6)).copyWith(color: c.text),
      decoration: InputDecoration(
        hintText: hint,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.all(14),
      ),
    );
  }
}
