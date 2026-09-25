import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/toolbox/tool.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/platform_actions.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/feedback.dart';
import '../engine/media_info.dart';
import '../media_module.dart';
import '../providers.dart';
import '../widgets/drop_zone.dart';
import '../widgets/engine_missing.dart';
import '../widgets/media_file_tile.dart';
import 'stage.dart';
import 'studio_state.dart';
import 'timeline.dart';

/// The media workspace: drop a file once, then every media tool works on it
/// from the tab bar below the preview (docs/DESIGN.md §4).
class MediaStudioPage extends ConsumerStatefulWidget {
  const MediaStudioPage({super.key, required this.tab});

  /// Active tool id (one of [mediaTools]).
  final String tab;

  @override
  ConsumerState<MediaStudioPage> createState() => _MediaStudioPageState();
}

class _MediaStudioPageState extends ConsumerState<MediaStudioPage> {
  bool _dragging = false;
  final _focus = FocusNode(debugLabel: 'studio');

  /// Tabs opened so far — kept alive so their options survive switching.
  final _visited = <String>{};

  StudioNotifier get _studio => ref.read(studioProvider.notifier);

  void _add(List<String> paths) {
    final accepted = paths.where(MediaAccept.media.accepts).toList();
    final ignored = paths.length - accepted.length;
    if (accepted.isNotEmpty) _studio.add(accepted);
    if (ignored > 0 && mounted) {
      showToast(context, 'media.ignored_files'.tr(namedArgs: {'n': '$ignored'}));
    }
  }

  Future<void> _pick() async => _add(await MediaAccept.media.pick(multiple: true));

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event, MediaInfo? info) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (info == null) return KeyEventResult.ignored;
    // Leave typing alone.
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && focused.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    final s = ref.read(studioProvider);
    final fps = info.video?.frameRate ?? 30;
    final frame = Duration(microseconds: (1000000 / (fps <= 0 ? 30 : fps)).round());
    final shift = HardwareKeyboard.instance.isShiftPressed;
    Duration clamp(Duration d) => d < Duration.zero ? Duration.zero : (d > info.duration ? info.duration : d);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _studio.setPlayhead(clamp(s.playhead() - (shift ? const Duration(seconds: 1) : frame)));
      case LogicalKeyboardKey.arrowRight:
        _studio.setPlayhead(clamp(s.playhead() + (shift ? const Duration(seconds: 1) : frame)));
      case LogicalKeyboardKey.home:
        _studio.setPlayhead(Duration.zero);
      case LogicalKeyboardKey.end:
        _studio.setPlayhead(info.duration);
      case LogicalKeyboardKey.keyI:
        _studio.markIn(info.duration);
      case LogicalKeyboardKey.keyO:
        _studio.markOut(info.duration);
      case LogicalKeyboardKey.escape:
        _studio.clearRange();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (ref.watch(ffmpegCapabilitiesProvider).error is EngineMissingException) {
      return const EngineMissingView();
    }
    final studio = ref.watch(studioProvider);
    final tab = mediaTools.any((t) => t.id == widget.tab) ? widget.tab : mediaTools.first.id;
    _visited.add(tab);
    final active = studio.active;
    final probe = active == null ? null : ref.watch(probeProvider(active));
    final info = probe?.value;

    Widget body;
    if (studio.files.isEmpty) {
      body = _StudioEmpty(dragging: _dragging, onPick: _pick, tab: tab);
    } else {
      body = LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 1040;
          final stageHeight = (box.maxHeight * 0.4).clamp(170.0, 440.0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LibraryBar(files: studio.files, active: active, onAdd: _pick),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xxl, Space.md, Space.xxl, 0),
                child: SizedBox(
                  height: stageHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: switch (probe) {
                          AsyncData(:final value) => StudioStage(info: value, showPreview: tab == 'transform'),
                          AsyncError(:final error) => _StageMessage(
                            icon: Icons.error_outline_rounded,
                            text: '${'media.unreadable'.tr()} · $error',
                            danger: true,
                          ),
                          _ => const _StageMessage(icon: null, text: ''),
                        },
                      ),
                      if (wide && info != null) ...[
                        const SizedBox(width: Space.md),
                        SizedBox(width: 290, child: _FactsPanel(info: info)),
                      ],
                    ],
                  ),
                ),
              ),
              if (info != null && info.duration > Duration.zero)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.xxl, Space.md, Space.xxl, 0),
                  child: StudioTimeline(info: info),
                ),
              const SizedBox(height: Space.sm),
              _TabBar(tab: tab),
              Expanded(
                child: Container(
                  color: c.bg,
                  child: IndexedStack(
                    index: mediaTools.indexWhere((t) => t.id == tab),
                    children: [
                      for (final t in mediaTools)
                        _visited.contains(t.id)
                            ? KeyedSubtree(key: ValueKey(t.id), child: t.builder!(context))
                            : const SizedBox(),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) {
        setState(() => _dragging = false);
        _add([for (final f in d.files) f.path]);
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (node, event) => _onKey(node, event, info),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _focus.requestFocus(),
          child: Scaffold(
            backgroundColor: c.bg,
            body: Stack(
              children: [
                Positioned.fill(child: body),
                if (_dragging && studio.files.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        margin: const EdgeInsets.all(Space.md),
                        decoration: BoxDecoration(
                          color: c.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(Radii.panel),
                          border: Border.all(color: c.accent, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            'studio.drop_add'.tr(),
                            style: TextStyles.title.copyWith(color: c.accent),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StageMessage extends StatelessWidget {
  const _StageMessage({required this.icon, required this.text, this.danger = false});
  final IconData? icon;
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(color: c.stage, borderRadius: BorderRadius.circular(Radii.card)),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(Space.xxl),
      child: icon == null
          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: danger ? c.danger : Colors.white54, size: 28),
                const SizedBox(height: Space.sm),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.body.copyWith(color: Colors.white70),
                ),
              ],
            ),
    );
  }
}

/// Horizontal strip of loaded files; the highlighted one is active.
class _LibraryBar extends ConsumerWidget {
  const _LibraryBar({required this.files, required this.active, required this.onAdd});
  final List<String> files;
  final String? active;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final notifier = ref.read(studioProvider.notifier);
    return Container(
      height: 58,
      padding: const EdgeInsets.fromLTRB(Space.xxl, 12, Space.lg, 0),
      child: Row(
        children: [
          ToolIcon(
            icon: ToolCategory.media.icon,
            color: ToolCategory.media.color,
            color2: ToolCategory.media.color2,
            size: 30,
          ),
          const SizedBox(width: 10),
          Text('studio.title'.tr(), style: TextStyles.heading.copyWith(color: c.text, fontSize: 15)),
          const SizedBox(width: Space.lg),
          Container(width: 1, height: 22, color: c.border),
          const SizedBox(width: Space.md),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: files.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) => Center(
                child: _FileChip(
                  path: files[i],
                  active: files[i] == active,
                  onTap: () => notifier.select(files[i]),
                  onRemove: () => notifier.remove(files[i]),
                ),
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          AppButton(label: 'media.add_files'.tr(), icon: Icons.add_rounded, size: ButtonSize.sm, onPressed: onAdd),
          const SizedBox(width: 4),
          if (active != null)
            AppIconButton(
              icon: Icons.folder_open_rounded,
              tooltip: 'common.reveal'.tr(),
              onPressed: () => PlatformActions.reveal(active!),
            ),
          AppIconButton(
            icon: Icons.clear_all_rounded,
            tooltip: 'studio.close_all'.tr(),
            onPressed: notifier.clear,
          ),
        ],
      ),
    );
  }
}

class _FileChip extends StatefulWidget {
  const _FileChip({required this.path, required this.active, required this.onTap, required this.onRemove});
  final String path;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_FileChip> createState() => _FileChipState();
}

class _FileChipState extends State<_FileChip> {
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
          height: 34,
          padding: const EdgeInsets.only(left: 4, right: 4),
          decoration: BoxDecoration(
            color: widget.active ? c.accentSoft : (_hover ? c.hover : c.surface),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: widget.active ? c.accent.withValues(alpha: 0.6) : c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MediaThumbnail(path: widget.path, width: 42, height: 26, radius: 6),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  p.basename(widget.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.label.copyWith(
                    color: widget.active ? c.text : c.textMuted,
                    fontWeight: widget.active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              AnimatedOpacity(
                duration: Motion.fast,
                opacity: _hover || widget.active ? 1 : 0,
                child: AppIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'common.remove'.tr(),
                  size: 22,
                  onPressed: widget.onRemove,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Container label: FFmpeg reports families like `mov,mp4,m4a`; prefer the
/// member matching the file extension.
String _container(MediaInfo info) {
  final names = info.formatName.split(',');
  final ext = p.extension(info.path).replaceFirst('.', '').toLowerCase();
  return (names.contains(ext) ? ext : names.first).toUpperCase();
}

/// Key facts about the active file, next to the stage.
class _FactsPanel extends StatelessWidget {
  const _FactsPanel({required this.info});
  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = info.video;
    final a = info.audio;
    final facts = <(IconData, String, String)>[
      (Icons.schedule_rounded, 'media.inspect.duration'.tr(), Fmt.duration(info.duration)),
      (Icons.sd_storage_rounded, 'media.inspect.size'.tr(), Fmt.bytes(info.sizeBytes)),
      if (v != null)
        (Icons.aspect_ratio_rounded, 'media.inspect.resolution'.tr(), '${v.displayWidth}×${v.displayHeight}'),
      if (v?.frameRate != null)
        (Icons.speed_rounded, 'media.inspect.fps'.tr(), v!.frameRate!.toStringAsFixed(v.frameRate! % 1 == 0 ? 0 : 2)),
      if (v != null) (Icons.movie_outlined, 'media.inspect.video'.tr(), v.codec.toUpperCase()),
      if (a != null)
        (Icons.graphic_eq_rounded, 'media.inspect.audio'.tr(), '${a.codec.toUpperCase()} · ${a.channels}ch'),
      (Icons.insights_rounded, 'media.inspect.bitrate'.tr(), Fmt.bitrate(info.bitrate)),
      (Icons.inventory_2_outlined, 'media.inspect.container'.tr(), _container(info)),
    ];
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.border),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            p.basename(info.path),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyles.heading.copyWith(color: c.text),
          ),
          const SizedBox(height: 2),
          Text(
            p.dirname(info.path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyles.caption.copyWith(color: c.textSubtle),
          ),
          const SizedBox(height: Space.md),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final itemW = (box.maxWidth - Space.sm) / 2;
                return SingleChildScrollView(
                  child: Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      for (final (icon, label, value) in facts)
                        Container(
                          width: itemW,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: c.surfaceAlt,
                            borderRadius: BorderRadius.circular(Radii.control),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(icon, size: 12, color: c.textSubtle),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyles.caption.copyWith(color: c.textSubtle),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyles.label.copyWith(color: c.text, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.tab});
  final String tab;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final t in mediaTools) _TabItem(tool: t, selected: t.id == tab, onTap: () => context.go(t.route)),
        ],
      ),
    );
  }
}

class _TabItem extends StatefulWidget {
  const _TabItem({required this.tool, required this.selected, required this.onTap});
  final ToolDefinition tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selected = widget.selected;
    final fg = selected ? c.text : (_hover ? c.text : c.textMuted);
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: selected ? c.accent : Colors.transparent, width: 2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.tool.icon, size: 16, color: selected ? c.accent : fg),
                const SizedBox(width: 6),
                Text(
                  'studio.tabs.${widget.tool.id}'.tr(),
                  style: TextStyles.body.copyWith(
                    color: fg,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// First-run state: one big drop target and a preview of what the studio does.
class _StudioEmpty extends StatefulWidget {
  const _StudioEmpty({required this.dragging, required this.onPick, required this.tab});
  final bool dragging;
  final VoidCallback onPick;
  final String tab;

  @override
  State<_StudioEmpty> createState() => _StudioEmptyState();
}

class _StudioEmptyState extends State<_StudioEmpty> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = widget.dragging || _hover;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.xxxl, 40, Space.xxxl, Space.xxxl),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ToolIcon(
                      icon: ToolCategory.media.icon,
                      color: ToolCategory.media.color,
                      color2: ToolCategory.media.color2,
                      size: 44,
                    ),
                    const SizedBox(width: Space.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('studio.title'.tr(), style: TextStyles.display.copyWith(color: c.text, fontSize: 24)),
                          const SizedBox(height: 2),
                          Text('studio.subtitle'.tr(), style: TextStyles.body.copyWith(color: c.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.xxl),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _hover = true),
                  onExit: (_) => setState(() => _hover = false),
                  child: GestureDetector(
                    onTap: widget.onPick,
                    child: AnimatedContainer(
                      duration: Motion.normal,
                      height: 300,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            ToolCategory.media.color.withValues(alpha: active ? 0.2 : 0.1),
                            c.accent.withValues(alpha: active ? 0.2 : 0.08),
                          ],
                        ),
                        border: Border.all(
                          color: active ? c.accent : c.borderStrong,
                          width: active ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedScale(
                            duration: Motion.normal,
                            scale: active ? 1.08 : 1,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: ToolCategory.media.gradient,
                                boxShadow: [
                                  BoxShadow(
                                    color: ToolCategory.media.color.withValues(alpha: 0.4),
                                    blurRadius: 24,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Icon(
                                widget.dragging ? Icons.file_download_rounded : Icons.video_library_rounded,
                                size: 32,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: Space.xl),
                          Text(
                            widget.dragging ? 'media.drop.release'.tr() : 'studio.drop_title'.tr(),
                            style: TextStyles.title.copyWith(color: c.text),
                          ),
                          const SizedBox(height: 6),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: 'media.drop.or'.tr()),
                                TextSpan(
                                  text: 'media.drop.browse'.tr(),
                                  style: TextStyle(color: c.accent, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            style: TextStyles.body.copyWith(color: c.textMuted),
                          ),
                          const SizedBox(height: Space.md),
                          Text(
                            'media.accept.media'.tr(),
                            style: TextStyles.caption.copyWith(color: c.textSubtle),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Space.xxl),
                Text('studio.capabilities'.tr(), style: TextStyles.heading.copyWith(color: c.textMuted)),
                const SizedBox(height: Space.md),
                LayoutBuilder(
                  builder: (context, box) {
                    final cols = (box.maxWidth / 230).floor().clamp(2, 5);
                    final w = (box.maxWidth - Space.md * (cols - 1)) / cols;
                    return Wrap(
                      spacing: Space.md,
                      runSpacing: Space.md,
                      children: [
                        for (final t in mediaTools)
                          SizedBox(
                            width: w,
                            child: _Capability(
                              tool: t,
                              highlighted: t.id == widget.tab,
                              onTap: () {
                                context.go(t.route);
                                widget.onPick();
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Capability extends StatefulWidget {
  const _Capability({required this.tool, required this.highlighted, required this.onTap});
  final ToolDefinition tool;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  State<_Capability> createState() => _CapabilityState();
}

class _CapabilityState extends State<_Capability> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tool = widget.tool;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: _hover ? c.hover.withValues(alpha: 0.6) : c.surface,
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(
              color: widget.highlighted || _hover ? ToolCategory.media.color.withValues(alpha: 0.5) : c.border,
            ),
          ),
          child: Row(
            children: [
              ToolIcon(icon: tool.icon, color: ToolCategory.media.color, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.nameKey.tr(),
                      style: TextStyles.label.copyWith(color: c.text, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      tool.descKey.tr(),
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
    );
  }
}
