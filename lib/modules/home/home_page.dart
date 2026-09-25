import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/shell/command_palette.dart';
import '../../app/tool_registry.dart';
import '../../core/jobs/job.dart';
import '../../core/jobs/job_queue.dart';
import '../../core/settings/settings.dart';
import '../../core/toolbox/file_intake.dart';
import '../../core/toolbox/tool.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/feedback.dart';
import '../media/media_module.dart';
import '../media/providers.dart';
import '../media/studio/studio_state.dart';
import '../media/widgets/drop_zone.dart';

/// Opens [paths] in the most fitting tool: media → studio, known text
/// formats → their tool, anything else → checksum.
void openFiles(BuildContext context, WidgetRef ref, List<String> paths) =>
    openPaths(GoRouter.of(context), ref.read(studioProvider.notifier), paths);

void openPaths(GoRouter router, StudioNotifier studio, List<String> paths) {
  if (paths.isEmpty) return;
  final media = paths.where(MediaAccept.media.accepts).toList();
  if (media.isNotEmpty) {
    studio.add(media);
    router.go('/media');
    return;
  }
  final tool = toolForFile(paths.first) ?? toolById('hash')!;
  FileIntake.instance.offer(tool.id, paths);
  router.go(tool.route);
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _dragging = false;

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (r == null || !mounted) return;
    openFiles(context, ref, [for (final f in r.files) ?f.path]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final recent = [
      for (final id in ref.watch(settingsProvider.select((s) => s.recentTools)))
        if (toolById(id) case final t? when t.isAvailable) t,
    ];
    final available = toolRegistry.where((t) => t.isAvailable).length;
    final sections = toolsByCategory().entries.where((e) => e.key != ToolCategory.media);

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) {
        setState(() => _dragging = false);
        openFiles(context, ref, [for (final f in d.files) f.path]);
      },
      child: Scaffold(
        backgroundColor: c.bg,
        body: Stack(
          children: [
            // Soft brand glow behind the hero.
            Positioned(
              top: -220,
              left: -120,
              right: -120,
              height: 520,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.3, -0.2),
                      radius: 1.1,
                      colors: [
                        c.accent.withValues(alpha: c.isDark ? 0.18 : 0.12),
                        c.bg.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(Space.xxxl, 48, Space.xxxl, 48),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('home.title'.tr(), style: TextStyles.display.copyWith(color: c.text, fontSize: 32)),
                        const SizedBox(height: 8),
                        Text(
                          'home.subtitle'.tr(namedArgs: {'n': '$available'}),
                          style: TextStyles.body.copyWith(color: c.textMuted, fontSize: 14.5),
                        ),
                        const SizedBox(height: Space.xxl),
                        const _SearchHero(),
                        const SizedBox(height: Space.lg),
                        LayoutBuilder(
                          builder: (context, box) {
                            final wide = box.maxWidth > 860;
                            final drop = _DropCard(dragging: _dragging, onTap: _pick);
                            final studio = const _StudioCard();
                            if (!wide) {
                              return Column(
                                children: [
                                  studio,
                                  const SizedBox(height: Space.lg),
                                  drop,
                                ],
                              );
                            }
                            return IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(flex: 3, child: studio),
                                  const SizedBox(width: Space.lg),
                                  Expanded(flex: 2, child: drop),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: Space.lg),
                        const _StatusStrip(),
                        if (recent.isNotEmpty) ...[
                          const SizedBox(height: 36),
                          _SectionTitle(icon: Icons.history_rounded, title: 'home.recent'.tr()),
                          const SizedBox(height: Space.md),
                          Wrap(
                            spacing: Space.sm,
                            runSpacing: Space.sm,
                            children: [for (final t in recent) _RecentChip(tool: t)],
                          ),
                        ],
                        for (final entry in sections) ...[
                          const SizedBox(height: 36),
                          _CategorySection(category: entry.key, tools: entry.value),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchHero extends StatefulWidget {
  const _SearchHero();

  @override
  State<_SearchHero> createState() => _SearchHeroState();
}

class _SearchHeroState extends State<_SearchHero> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => CommandPalette.show(context),
        child: AnimatedContainer(
          duration: Motion.fast,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.card + 2),
            border: Border.all(color: _hover ? c.accent.withValues(alpha: 0.6) : c.border),
            boxShadow: [
              ...c.cardShadow,
              if (_hover) BoxShadow(color: c.accent.withValues(alpha: 0.15), blurRadius: 16),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 20, color: _hover ? c.accent : c.textSubtle),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text('home.search'.tr(), style: TextStyles.body.copyWith(color: c.textSubtle, fontSize: 14)),
              ),
              Tag(Platform.isMacOS ? '⌘ K' : 'Ctrl K'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Feature card for the media workspace with a chip per capability.
class _StudioCard extends ConsumerWidget {
  const _StudioCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final files = ref.watch(studioProvider.select((s) => s.files.length));
    return _Hoverable(
      onTap: () => context.go('/media'),
      builder: (hover) => AnimatedContainer(
        duration: Motion.normal,
        padding: const EdgeInsets.all(Space.xl),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.panel + 4),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: c.isDark
                ? [const Color(0xFF2A1420), const Color(0xFF1A1426)]
                : [const Color(0xFFFFF1F2), const Color(0xFFF5F3FF)],
          ),
          border: Border.all(
            color: hover
                ? ToolCategory.media.color.withValues(alpha: 0.6)
                : ToolCategory.media.color.withValues(alpha: 0.2),
          ),
          boxShadow: hover
              ? [
                  BoxShadow(
                    color: ToolCategory.media.color.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ]
              : c.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ToolIcon(
                  icon: Icons.movie_filter_rounded,
                  color: ToolCategory.media.color,
                  color2: ToolCategory.media.color2,
                  size: 46,
                ),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('studio.title'.tr(), style: TextStyles.title.copyWith(color: c.text, fontSize: 20)),
                      const SizedBox(height: 2),
                      Text(
                        files > 0 ? 'studio.files_loaded'.tr(namedArgs: {'n': '$files'}) : 'studio.subtitle'.tr(),
                        style: TextStyles.body.copyWith(color: c.textMuted),
                      ),
                    ],
                  ),
                ),
                AnimatedSlide(
                  duration: Motion.normal,
                  offset: Offset(hover ? 0.15 : 0, 0),
                  child: Icon(Icons.arrow_forward_rounded, color: ToolCategory.media.color),
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in mediaTools)
                  _MiniChip(
                    icon: t.icon,
                    label: 'studio.tabs.${t.id}'.tr(),
                    color: ToolCategory.media.color,
                    onTap: () => context.go(t.route),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatefulWidget {
  const _MiniChip({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_MiniChip> createState() => _MiniChipState();
}

class _MiniChipState extends State<_MiniChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: _hover ? widget.color.withValues(alpha: 0.16) : c.surface.withValues(alpha: c.isDark ? 0.5 : 0.8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _hover ? widget.color.withValues(alpha: 0.5) : c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 13, color: widget.color),
              const SizedBox(width: 5),
              Text(widget.label, style: TextStyles.label.copyWith(color: c.text)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropCard extends StatefulWidget {
  const _DropCard({required this.dragging, required this.onTap});
  final bool dragging;
  final VoidCallback onTap;

  @override
  State<_DropCard> createState() => _DropCardState();
}

class _DropCardState extends State<_DropCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = widget.dragging || _hover;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.normal,
          constraints: const BoxConstraints(minHeight: 150),
          padding: const EdgeInsets.all(Space.xl),
          decoration: BoxDecoration(
            color: widget.dragging ? c.accentSoft : c.surface,
            borderRadius: BorderRadius.circular(Radii.panel + 4),
            border: Border.all(color: active ? c.accent : c.borderStrong, width: widget.dragging ? 2 : 1),
            boxShadow: c.cardShadow,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: Motion.normal,
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: active ? c.brandGradient : null,
                  color: active ? null : c.surfaceAlt,
                  border: active ? null : Border.all(color: c.border),
                ),
                child: Icon(
                  widget.dragging ? Icons.file_download_rounded : Icons.upload_rounded,
                  color: active ? Colors.white : c.textMuted,
                ),
              ),
              const SizedBox(height: Space.md),
              Text(
                widget.dragging ? 'media.drop.release'.tr() : 'home.drop_title'.tr(),
                textAlign: TextAlign.center,
                style: TextStyles.heading.copyWith(color: c.text),
              ),
              const SizedBox(height: 4),
              Text(
                'home.drop_hint'.tr(),
                textAlign: TextAlign.center,
                style: TextStyles.caption.copyWith(color: c.textSubtle, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusStrip extends ConsumerWidget {
  const _StatusStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final caps = ref.watch(ffmpegCapabilitiesProvider);
    final jobs = ref.watch(jobQueueProvider);
    final active = jobs.where((j) => j.status.isActive).length;
    final done = jobs.where((j) => j.status == JobStatus.completed).length;

    final (engineColor, engineValue) = switch (caps) {
      AsyncData(:final value) => (c.success, 'FFmpeg ${value.version}'),
      AsyncError() => (c.danger, 'home.engine_missing'.tr()),
      _ => (c.warning, 'nav.engine_detecting'.tr()),
    };
    final gpu = caps.value?.gpuEncoders ?? const [];
    final gpuLabel = gpu.any((e) => e.contains('videotoolbox'))
        ? 'VideoToolbox'
        : gpu.any((e) => e.contains('nvenc'))
        ? 'NVENC'
        : gpu.any((e) => e.contains('qsv'))
        ? 'Quick Sync'
        : gpu.isEmpty
        ? 'home.gpu_none'.tr()
        : gpu.first;

    Widget item(IconData icon, String label, String value, Color dot, {VoidCallback? onTap}) => Expanded(
      child: _Hoverable(
        onTap: onTap,
        builder: (hover) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: hover && onTap != null ? c.hover.withValues(alpha: 0.5) : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: c.textSubtle),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyles.caption.copyWith(color: c.textSubtle)),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyles.label.copyWith(color: c.text),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.border),
        boxShadow: c.cardShadow,
      ),
      child: Row(
        children: [
          item(
            Icons.memory_rounded,
            'home.engine'.tr(),
            engineValue,
            engineColor,
            onTap: () => context.go('/settings'),
          ),
          Container(width: 1, height: 28, color: c.border),
          item(Icons.bolt_rounded, 'home.gpu'.tr(), gpuLabel, gpu.isEmpty ? c.textSubtle : c.success),
          Container(width: 1, height: 28, color: c.border),
          item(
            Icons.layers_rounded,
            'home.tasks'.tr(),
            'home.tasks_value'.tr(namedArgs: {'active': '$active', 'done': '$done'}),
            active > 0 ? c.accent : c.textSubtle,
            onTap: () => context.go('/tasks'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Icon(icon, size: 16, color: c.textSubtle),
        const SizedBox(width: 8),
        Text(title, style: TextStyles.heading.copyWith(color: c.text)),
      ],
    );
  }
}

class _RecentChip extends StatelessWidget {
  const _RecentChip({required this.tool});
  final ToolDefinition tool;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _Hoverable(
      onTap: () => context.go(tool.route),
      builder: (hover) => AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        decoration: BoxDecoration(
          color: hover ? c.hover : c.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ToolIcon.of(tool, size: 26),
            const SizedBox(width: 9),
            Text(tool.nameKey.tr(), style: TextStyles.label.copyWith(color: c.text)),
          ],
        ),
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.category, required this.tools});
  final ToolCategory category;
  final List<ToolDefinition> tools;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final planned = tools.every((t) => !t.isAvailable);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ToolIcon(icon: category.icon, color: category.color, color2: category.color2, size: 24),
            const SizedBox(width: 10),
            Text(category.labelKey.tr(), style: TextStyles.heading.copyWith(color: c.text, fontSize: 15)),
            const SizedBox(width: 8),
            planned
                ? Tag('home.soon'.tr())
                : Text('${tools.length}', style: TextStyles.label.copyWith(color: c.textSubtle)),
            const SizedBox(width: Space.md),
            Expanded(child: Container(height: 1, color: c.border)),
          ],
        ),
        const SizedBox(height: Space.md),
        LayoutBuilder(
          builder: (context, box) {
            final cols = (box.maxWidth / 250).floor().clamp(1, 4);
            final w = (box.maxWidth - Space.md * (cols - 1)) / cols;
            return Wrap(
              spacing: Space.md,
              runSpacing: Space.md,
              children: [
                for (final t in tools)
                  SizedBox(
                    width: w,
                    child: ToolCard(tool: t),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class ToolCard extends StatelessWidget {
  const ToolCard({super.key, required this.tool});
  final ToolDefinition tool;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = tool.isAvailable;
    return _Hoverable(
      onTap: () => enabled ? context.go(tool.route) : showToast(context, 'home.coming_soon_toast'.tr()),
      builder: (hover) => AnimatedContainer(
        duration: Motion.normal,
        curve: Motion.curve,
        transform: Matrix4.translationValues(0, hover && enabled ? -2 : 0, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.card + 2),
          border: Border.all(
            color: hover && enabled ? tool.category.color.withValues(alpha: 0.45) : c.border,
          ),
          boxShadow: hover && enabled
              ? [
                  BoxShadow(
                    color: tool.category.color.withValues(alpha: 0.14),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : c.cardShadow,
        ),
        child: Row(
          children: [
            ToolIcon.of(tool, size: 38, muted: !enabled),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          tool.nameKey.tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyles.body.copyWith(
                            color: enabled ? c.text : c.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!enabled) ...[const SizedBox(width: 6), Tag('home.soon'.tr())],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tool.descKey.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.caption.copyWith(color: c.textSubtle, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hoverable extends StatefulWidget {
  const _Hoverable({required this.builder, this.onTap});
  final Widget Function(bool hover) builder;
  final VoidCallback? onTap;

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: widget.builder(_hover)),
    );
  }
}
