import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/jobs/job.dart';
import '../../core/jobs/job_queue.dart';
import '../../core/toolbox/tool.dart';
import '../../modules/media/providers.dart';
import '../../modules/media/studio/studio_state.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/feedback.dart';
import '../tool_registry.dart';
import 'command_palette.dart';

class Sidebar extends ConsumerStatefulWidget {
  const Sidebar({super.key, required this.location, this.compact = false});
  final String location;
  final bool compact;

  static const width = 244.0;
  static const compactWidth = 64.0;

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  final _collapsed = <ToolCategory>{ToolCategory.file};

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final compact = widget.compact;
    final jobs = ref.watch(jobQueueProvider);
    final running = jobs.where((j) => j.status == JobStatus.running).length;
    final queued = jobs.where((j) => j.status == JobStatus.queued).length;
    final studioFiles = ref.watch(studioProvider.select((s) => s.files.length));
    // macOS draws traffic lights over the top-left corner.
    final topInset = Platform.isMacOS ? 40.0 : 14.0;
    final loc = widget.location;

    final categories = toolsByCategory().entries.where((e) => e.key != ToolCategory.media);

    return Container(
      width: compact ? Sidebar.compactWidth : Sidebar.width,
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(right: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: topInset),
          _Brand(compact: compact),
          const SizedBox(height: Space.lg),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : Space.md),
            child: _SearchButton(compact: compact),
          ),
          const SizedBox(height: Space.md),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(compact ? 10 : Space.sm, 0, compact ? 10 : Space.sm, Space.md),
              children: [
                _NavItem(
                  icon: Icons.space_dashboard_rounded,
                  label: 'nav.home'.tr(),
                  selected: loc == '/',
                  compact: compact,
                  onTap: () => context.go('/'),
                ),
                _NavItem(
                  icon: Icons.layers_rounded,
                  label: 'nav.tasks'.tr(),
                  selected: loc == '/tasks',
                  compact: compact,
                  badge: running + queued > 0 ? '${running + queued}' : null,
                  busy: running > 0,
                  onTap: () => context.go('/tasks'),
                ),
                const SizedBox(height: Space.sm),
                _StudioItem(
                  selected: loc.startsWith('/media'),
                  compact: compact,
                  files: studioFiles,
                  onTap: () => context.go('/media'),
                ),
                for (final entry in categories) ...[
                  if (!compact)
                    _CategoryHeader(
                      category: entry.key,
                      count: entry.value.where((t) => t.isAvailable).length,
                      collapsed: _collapsed.contains(entry.key) && !entry.value.any((t) => t.route == loc),
                      planned: entry.value.every((t) => !t.isAvailable),
                      onTap: () => setState(() {
                        _collapsed.contains(entry.key) ? _collapsed.remove(entry.key) : _collapsed.add(entry.key);
                      }),
                    )
                  else if (entry.value.any((t) => t.isAvailable))
                    Divider(color: c.border, height: Space.lg),
                  if (compact || !_collapsed.contains(entry.key) || entry.value.any((t) => t.route == loc))
                    for (final tool in entry.value)
                      if (!compact || tool.isAvailable)
                        _NavItem(
                          icon: tool.icon,
                          iconColor: tool.category.color,
                          label: tool.nameKey.tr(),
                          selected: loc == tool.route,
                          compact: compact,
                          dense: true,
                          disabled: !tool.isAvailable,
                          onTap: () => tool.isAvailable
                              ? context.go(tool.route)
                              : showToast(context, 'home.coming_soon_toast'.tr()),
                        ),
                ],
              ],
            ),
          ),
          Container(height: 1, color: c.border),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : Space.sm, vertical: Space.sm),
            child: Column(
              children: [
                _NavItem(
                  icon: Icons.settings_rounded,
                  label: 'nav.settings'.tr(),
                  selected: loc == '/settings',
                  compact: compact,
                  onTap: () => context.go('/settings'),
                ),
                if (!compact) const _EngineStatus(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final logo = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: c.brandGradient,
        borderRadius: BorderRadius.circular(9),
        boxShadow: [BoxShadow(color: c.accent.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: const Icon(Icons.bolt_rounded, size: 20, color: Colors.white),
    );
    if (compact) return Center(child: logo);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: Row(
        children: [
          logo,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Super Toolbox', style: TextStyles.heading.copyWith(color: c.text, fontSize: 14.5)),
                Text('app.tagline'.tr(), style: TextStyles.caption.copyWith(color: c.textSubtle)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchButton extends StatefulWidget {
  const _SearchButton({required this.compact});
  final bool compact;

  @override
  State<_SearchButton> createState() => _SearchButtonState();
}

class _SearchButtonState extends State<_SearchButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: widget.compact ? 'nav.search'.tr() : '',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: () => CommandPalette.show(context),
          child: AnimatedContainer(
            duration: Motion.fast,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _hover ? c.hover : c.surface,
              borderRadius: BorderRadius.circular(Radii.control),
              border: Border.all(color: _hover ? c.borderStrong : c.border),
              boxShadow: c.cardShadow,
            ),
            child: Row(
              mainAxisAlignment: widget.compact ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Icon(Icons.search_rounded, size: 16, color: c.textSubtle),
                if (!widget.compact) ...[
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text('nav.search'.tr(), style: TextStyles.body.copyWith(color: c.textSubtle)),
                  ),
                  _Kbd(Platform.isMacOS ? '⌘K' : 'Ctrl K'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Kbd extends StatelessWidget {
  const _Kbd(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.border),
      ),
      child: Text(text, style: TextStyles.caption.copyWith(color: c.textMuted, fontSize: 10.5)),
    );
  }
}

/// Prominent entry for the media workspace.
class _StudioItem extends StatefulWidget {
  const _StudioItem({required this.selected, required this.compact, required this.files, required this.onTap});
  final bool selected;
  final bool compact;
  final int files;
  final VoidCallback onTap;

  @override
  State<_StudioItem> createState() => _StudioItemState();
}

class _StudioItemState extends State<_StudioItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = ToolIcon(
      icon: Icons.movie_filter_rounded,
      color: ToolCategory.media.color,
      color2: ToolCategory.media.color2,
      size: widget.compact ? 30 : 28,
    );
    final label = 'studio.title'.tr();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: widget.compact ? label : '',
        child: Semantics(
          button: true,
          selected: widget.selected,
          label: label,
          excludeSemantics: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: Motion.fast,
                padding: EdgeInsets.all(widget.compact ? 4 : 8),
                decoration: BoxDecoration(
                  color: widget.selected
                      ? ToolCategory.media.color.withValues(alpha: c.isDark ? 0.14 : 0.1)
                      : (_hover ? c.hover.withValues(alpha: 0.7) : Colors.transparent),
                  borderRadius: BorderRadius.circular(Radii.card),
                  border: Border.all(
                    color: widget.selected ? ToolCategory.media.color.withValues(alpha: 0.35) : Colors.transparent,
                  ),
                ),
                child: widget.compact
                    ? Center(child: icon)
                    : Row(
                        children: [
                          icon,
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: TextStyles.body.copyWith(color: c.text, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  widget.files > 0
                                      ? 'studio.files_loaded'.tr(namedArgs: {'n': '${widget.files}'})
                                      : 'studio.sidebar_hint'.tr(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyles.caption.copyWith(color: c.textSubtle),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.category,
    required this.count,
    required this.collapsed,
    required this.planned,
    required this.onTap,
  });

  final ToolCategory category;
  final int count;
  final bool collapsed;
  final bool planned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.control),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 8, 6),
        child: Row(
          children: [
            Text(
              category.labelKey.tr().toUpperCase(),
              style: TextStyles.overline.copyWith(color: c.textSubtle),
            ),
            const SizedBox(width: 6),
            Text(
              planned ? 'home.soon'.tr() : '$count',
              style: TextStyles.caption.copyWith(color: c.textSubtle.withValues(alpha: 0.7), fontSize: 10.5),
            ),
            const Spacer(),
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: Motion.fast,
              child: Icon(Icons.expand_more_rounded, size: 15, color: c.textSubtle),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.compact,
    this.iconColor,
    this.badge,
    this.busy = false,
    this.dense = false,
    this.disabled = false,
  });

  final IconData icon;
  final Color? iconColor;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;
  final String? badge;
  final bool busy;
  final bool dense;
  final bool disabled;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = widget.disabled
        ? c.textSubtle.withValues(alpha: 0.7)
        : widget.selected
        ? c.text
        : c.textMuted;
    final iconColor = widget.disabled
        ? fg
        : widget.selected
        ? (widget.iconColor ?? c.accent)
        : (widget.iconColor?.withValues(alpha: 0.85) ?? fg);
    final icon = widget.busy
        ? SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: c.accent))
        : Icon(widget.icon, size: 17, color: iconColor);

    final badge = widget.badge == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(10)),
            child: Text(
              widget.badge!,
              style: TextStyles.caption.copyWith(color: c.onAccent, fontWeight: FontWeight.w600),
            ),
          );

    final row = AnimatedContainer(
      duration: Motion.fast,
      height: widget.dense ? 31 : 34,
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? 0 : 10),
      decoration: BoxDecoration(
        color: widget.selected
            ? (c.isDark ? c.elevated : c.surface)
            : (_hover ? c.hover.withValues(alpha: 0.7) : Colors.transparent),
        borderRadius: BorderRadius.circular(Radii.control),
        boxShadow: widget.selected ? c.cardShadow : null,
        border: widget.selected ? Border.all(color: c.border) : null,
      ),
      child: widget.compact
          ? Center(
              child: Badge(isLabelVisible: widget.badge != null, label: Text(widget.badge ?? ''), child: icon),
            )
          : Row(
              children: [
                SizedBox(width: 18, child: Center(child: icon)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.body.copyWith(
                      color: fg,
                      fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                ?badge,
              ],
            ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Tooltip(
        message: widget.compact ? widget.label : '',
        waitDuration: const Duration(milliseconds: 300),
        child: Semantics(
          button: true,
          selected: widget.selected,
          label: widget.label,
          excludeSemantics: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(onTap: widget.onTap, child: row),
          ),
        ),
      ),
    );
  }
}

class _EngineStatus extends ConsumerWidget {
  const _EngineStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final caps = ref.watch(ffmpegCapabilitiesProvider);
    final (color, text) = switch (caps) {
      AsyncData(:final value) => (
        c.success,
        'FFmpeg ${value.version} · ${'settings.source_${value.binaries.source.name}'.tr()}${value.hasGpu ? ' · GPU' : ''}',
      ),
      AsyncError() => (c.danger, 'nav.engine_missing'.tr()),
      _ => (c.warning, 'nav.engine_detecting'.tr()),
    };
    return InkWell(
      onTap: () => context.go('/settings'),
      borderRadius: BorderRadius.circular(Radii.control),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyles.caption.copyWith(color: c.textSubtle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
