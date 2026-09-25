import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/jobs/job_queue.dart';
import '../../../core/settings/settings.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/platform_actions.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/feedback.dart';
import '../builders/range.dart';
import '../engine/capabilities.dart';
import '../engine/command_plan.dart';
import '../engine/media_info.dart';
import '../engine/media_job.dart';
import '../providers.dart';
import '../widgets/output_planner.dart';
import 'studio_state.dart';

/// Everything a tool's planner needs to turn options into commands.
class PlanRequest {
  const PlanRequest({
    required this.inputs,
    required this.infos,
    required this.caps,
    required this.out,
    required this.preferGpu,
    this.range,
    this.playhead = Duration.zero,
  });

  /// Inputs that probed successfully, in order.
  final List<String> inputs;
  final Map<String, MediaInfo> infos;
  final FfmpegCapabilities caps;
  final OutputPlanner out;
  final bool preferGpu;

  /// Timeline selection of the active file (only for [RangeUsage.native]).
  final ClipRange? range;

  /// Playhead of the active file.
  final Duration playhead;

  Set<String> get encoders => caps.encoders;
}

class PlannedJob {
  const PlannedJob({required this.inputs, required this.plan});
  final List<String> inputs;
  final CommandPlan plan;
}

typedef MediaPlanner = List<PlannedJob> Function(PlanRequest request);

/// How a tool uses the timeline selection.
enum RangeUsage {
  /// Ignores it (inspect, merge).
  none,

  /// Offers "only the selection" — the panel clips the plan itself.
  optional,

  /// The tool's own semantics are range-based (trim, GIF) — gets [PlanRequest.range].
  native,
}

enum InputScope {
  /// The active file only (optionally the whole library in batch mode).
  active,

  /// Every file in the library, in order (merge).
  library,

  /// Works without input (free-form CLI) but uses the active file if any.
  optional,
}

/// Options + run bar for one studio tab (docs/DESIGN.md §4).
class StudioToolView extends ConsumerStatefulWidget {
  const StudioToolView({
    super.key,
    required this.toolId,
    required this.fields,
    required this.planner,
    required this.actionKey,
    this.header,
    this.batchable = true,
    this.range = RangeUsage.optional,
    this.scope = InputScope.active,
  });

  final String toolId;

  /// Option fields laid out in a responsive grid.
  final List<Widget> fields;

  /// Full-width content above the grid.
  final Widget? header;
  final MediaPlanner planner;

  /// Translation key for the primary button; receives `{n}` = job count.
  final String actionKey;
  final bool batchable;
  final RangeUsage range;
  final InputScope scope;

  @override
  ConsumerState<StudioToolView> createState() => _StudioToolViewState();
}

class _StudioToolViewState extends ConsumerState<StudioToolView> {
  bool _showCommand = false;
  bool _useRange = true;

  List<String> _inputs(StudioState s) {
    if (widget.scope == InputScope.library) return s.files;
    if (s.active == null) return const [];
    if (widget.batchable && s.batch && s.files.length > 1) return s.files;
    return [s.active!];
  }

  bool _batchMode(StudioState s) =>
      widget.scope != InputScope.library && widget.batchable && s.batch && s.files.length > 1;

  ({List<PlannedJob> jobs, String? error, bool pending, ClipRange? clip}) _plan({
    required StudioState studio,
    required FfmpegCapabilities? caps,
    required AppSettings settings,
    bool watch = true,
  }) {
    if (caps == null) return (jobs: const [], error: null, pending: true, clip: null);
    final inputs = _inputs(studio);
    final infos = <String, MediaInfo>{};
    var pending = false;
    for (final path in inputs) {
      final probe = watch ? ref.watch(probeProvider(path)) : ref.read(probeProvider(path));
      if (probe.value case final info?) {
        infos[path] = info;
      } else if (probe.isLoading) {
        pending = true;
      }
    }
    if (pending) return (jobs: const [], error: null, pending: true, clip: null);
    final valid = [
      for (final i in inputs)
        if (infos.containsKey(i)) i,
    ];
    if (valid.isEmpty && widget.scope != InputScope.optional) {
      return (jobs: const [], error: null, pending: false, clip: null);
    }

    final active = studio.active;
    final activeInfo = active == null ? null : infos[active];
    final selection = studio.range();
    final partial = activeInfo != null && selection != null && selection.isPartialOf(activeInfo.duration);
    final clip = widget.range == RangeUsage.optional && partial && _useRange && !_batchMode(studio) ? selection : null;

    try {
      final planned = widget.planner(
        PlanRequest(
          inputs: valid,
          infos: clip == null ? infos : {...infos, active!: activeInfo!.clipped(clip.length)},
          caps: caps,
          out: OutputPlanner(outputDir: settings.outputDir),
          preferGpu: settings.preferGpu,
          range: widget.range == RangeUsage.native && partial ? selection : null,
          playhead: studio.playhead(),
        ),
      );
      final jobs = clip == null
          ? planned
          : [
              for (final j in planned)
                j.inputs.length == 1 && j.inputs.single == active
                    ? PlannedJob(
                        inputs: j.inputs,
                        plan: applyClipRange(j.plan, input: active!, start: clip.start, length: clip.length),
                      )
                    : j,
            ];
      return (jobs: jobs, error: null, pending: false, clip: clip);
    } on PlanException catch (e) {
      return (jobs: const [], error: e.messageKey.tr(namedArgs: e.args), pending: false, clip: clip);
    }
  }

  void _start(FfmpegCapabilities caps, List<PlannedJob> jobs) {
    final toolName = 'tools.${widget.toolId}.name'.tr();
    final specs = [
      for (final j in jobs)
        MediaJobSpec(
          title: j.inputs.isEmpty
              ? toolName
              : '$toolName · ${p.basename(j.inputs.first)}${j.inputs.length > 1 ? ' +${j.inputs.length - 1}' : ''}',
          toolId: widget.toolId,
          inputs: j.inputs,
          plan: j.plan,
          ffmpeg: caps.binaries.ffmpeg,
        ),
    ];
    ref.read(jobQueueProvider.notifier).enqueueAll(specs);
    ref.read(settingsProvider.notifier).markToolUsed(widget.toolId);
    showToast(
      context,
      'media.queued'.tr(namedArgs: {'n': '${specs.length}'}),
      actionLabel: 'media.view_tasks'.tr(),
      onAction: () => context.go('/tasks'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final studio = ref.watch(studioProvider);
    final caps = ref.watch(ffmpegCapabilitiesProvider).value;
    final settings = ref.watch(settingsProvider);
    final plan = _plan(studio: studio, caps: caps, settings: settings);
    final activeInfo = studio.active == null ? null : ref.watch(probeProvider(studio.active!)).value;
    final selection = studio.range();
    final hasPartial = activeInfo != null && selection != null && selection.isPartialOf(activeInfo.duration);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Space.xxl, Space.lg, Space.xxl, Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.header != null) ...[widget.header!, const SizedBox(height: Space.lg)],
                OptionsGrid(children: widget.fields),
              ],
            ),
          ),
        ),
        RunBar(
          actionLabel: widget.actionKey.tr(namedArgs: {'n': '${plan.jobs.length}'}),
          error: plan.error,
          pending: plan.pending && (studio.files.isNotEmpty || widget.scope == InputScope.optional),
          jobs: plan.jobs,
          showCommand: _showCommand,
          onToggleCommand: () => setState(() => _showCommand = !_showCommand),
          scope: widget.scope != InputScope.library && widget.batchable && studio.files.length > 1
              ? _ScopeSwitch(
                  batch: studio.batch,
                  count: studio.files.length,
                  onChanged: ref.read(studioProvider.notifier).setBatch,
                )
              : null,
          rangeChip: widget.range == RangeUsage.optional && hasPartial && !_batchMode(studio)
              ? _RangeChip(
                  range: selection,
                  enabled: _useRange,
                  onToggle: () => setState(() => _useRange = !_useRange),
                )
              : null,
          onStart: plan.jobs.isEmpty || caps == null
              ? null
              : () {
                  // Re-plan so scratch paths and names are fresh.
                  final fresh = _plan(studio: ref.read(studioProvider), caps: caps, settings: settings, watch: false);
                  if (fresh.jobs.isNotEmpty) _start(caps, fresh.jobs);
                },
        ),
      ],
    );
  }
}

/// Lays option fields out in 1–3 columns depending on width.
class OptionsGrid extends StatelessWidget {
  const OptionsGrid({super.key, required this.children, this.minColumnWidth = 300, this.maxColumns = 3});
  final List<Widget> children;
  final double minColumnWidth;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final cols = (box.maxWidth / minColumnWidth)
            .floor()
            .clamp(1, maxColumns)
            .clamp(1, children.length.clamp(1, 99));
        if (cols == 1) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var col = 0; col < cols; col++) ...[
              if (col > 0) const SizedBox(width: Space.xxl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = col; i < children.length; i += cols) children[i],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ScopeSwitch extends StatelessWidget {
  const _ScopeSwitch({required this.batch, required this.count, required this.onChanged});
  final bool batch;
  final int count;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget item(bool value, String label) {
      final selected = batch == value;
      return GestureDetector(
        onTap: () => onChanged(value),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: Motion.fast,
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? c.elevated : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: selected ? Border.all(color: c.borderStrong) : null,
            ),
            child: Text(
              label,
              style: TextStyles.label.copyWith(color: selected ? c.text : c.textMuted),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          item(false, 'studio.scope_current'.tr()),
          item(true, 'studio.scope_all'.tr(namedArgs: {'n': '$count'})),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({required this.range, required this.enabled, required this.onToggle});
  final ClipRange range;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = enabled ? c.accent : c.textMuted;
    return Tooltip(
      message: 'studio.range_only_hint'.tr(),
      child: GestureDetector(
        onTap: onToggle,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: Motion.fast,
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: enabled ? c.accentSoft : c.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: enabled ? c.accent.withValues(alpha: 0.5) : c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(enabled ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 15, color: fg),
                const SizedBox(width: 6),
                Text(
                  'studio.range_only'.tr(
                    namedArgs: {'from': Fmt.shortTime(range.start), 'to': Fmt.shortTime(range.end)},
                  ),
                  style: TextStyles.label.copyWith(color: fg, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom bar: output folder · planned output · command · start button.
class RunBar extends ConsumerWidget {
  const RunBar({
    super.key,
    required this.actionLabel,
    required this.error,
    required this.pending,
    required this.jobs,
    required this.showCommand,
    required this.onToggleCommand,
    required this.onStart,
    this.scope,
    this.rangeChip,
  });

  final String actionLabel;
  final String? error;
  final bool pending;
  final List<PlannedJob> jobs;
  final bool showCommand;
  final VoidCallback onToggleCommand;
  final VoidCallback? onStart;
  final Widget? scope;
  final Widget? rangeChip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final outputDir = ref.watch(settingsProvider.select((s) => s.outputDir));
    final command = jobs.isEmpty ? null : jobs.first.plan.commandLine();
    final outputs = [
      for (final j in jobs)
        if (j.plan.outputs.isNotEmpty) j.plan.outputs.first,
    ];

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: Motion.normal,
            curve: Motion.curve,
            child: showCommand && command != null
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(Space.xxl, Space.md, Space.xxl, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CommandPreview(command: command),
                        if (jobs.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'media.more_commands'.tr(namedArgs: {'n': '${jobs.length - 1}'}),
                              style: TextStyles.caption.copyWith(color: c.textSubtle),
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xxl, vertical: 10),
            child: Row(
              children: [
                if (scope != null) ...[scope!, const SizedBox(width: Space.sm)],
                if (rangeChip != null) ...[rangeChip!, const SizedBox(width: Space.sm)],
                Expanded(
                  child: Row(
                    children: [
                      const SizedBox(width: 4),
                      _OutputMenu(outputDir: outputDir),
                      if (outputs.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(Icons.chevron_right_rounded, size: 15, color: c.textSubtle),
                        ),
                        Flexible(
                          child: Tooltip(
                            message: outputs.first,
                            child: Text(
                              outputs.length > 1
                                  ? '${p.basename(outputs.first)}  +${outputs.length - 1}'
                                  : p.basename(outputs.first),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyles.body.copyWith(color: c.text, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: Space.sm),
                      AppIconButton(
                        icon: showCommand ? Icons.expand_more_rounded : Icons.code_rounded,
                        tooltip: 'media.command'.tr(),
                        onPressed: command == null ? null : onToggleCommand,
                      ),
                    ],
                  ),
                ),
                if (error != null)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: Space.md),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 15, color: c.danger),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              error!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyles.label.copyWith(color: c.danger),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                AppButton.primary(
                  label: actionLabel,
                  icon: Icons.play_arrow_rounded,
                  size: ButtonSize.lg,
                  loading: pending,
                  onPressed: onStart,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OutputMenu extends ConsumerWidget {
  const _OutputMenu({required this.outputDir});
  final String? outputDir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final label = outputDir == null ? 'media.output_next_to_source'.tr() : p.basename(outputDir!);
    return PopupMenuButton<String>(
      tooltip: outputDir ?? 'media.output_to'.tr(),
      position: PopupMenuPosition.over,
      onSelected: (v) async {
        final settings = ref.read(settingsProvider.notifier);
        switch (v) {
          case 'source':
            settings.setOutputDir(null);
          case 'choose':
            final dir = await FilePicker.platform.getDirectoryPath();
            if (dir != null) settings.setOutputDir(dir);
          case 'reveal':
            if (outputDir != null) await PlatformActions.open(outputDir!);
        }
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: 'source',
          checked: outputDir == null,
          child: Text('media.output_next_to_source'.tr()),
        ),
        CheckedPopupMenuItem(
          value: 'choose',
          checked: outputDir != null,
          child: Text('media.output_choose'.tr()),
        ),
        if (outputDir != null) PopupMenuItem(value: 'reveal', child: Text('common.open_folder'.tr())),
      ],
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_rounded, size: 15, color: c.textSubtle),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyles.label.copyWith(color: c.textMuted),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.unfold_more_rounded, size: 14, color: c.textSubtle),
          ],
        ),
      ),
    );
  }
}
