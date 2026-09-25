import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/tool_registry.dart';
import '../../core/jobs/job.dart';
import '../../core/jobs/job_queue.dart';
import '../../core/toolbox/tool.dart';
import '../../core/utils/format.dart';
import '../../core/utils/platform_actions.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/feedback.dart';
import '../../ui/widgets/inputs.dart';
import '../../ui/widgets/layout.dart';

enum _Filter { all, active, completed, failed }

class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  var _filter = _Filter.all;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Ticks once a second while jobs run so elapsed/ETA stay live.
  void _syncTicker(bool anyRunning) {
    if (anyRunning && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    } else if (!anyRunning && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final jobs = ref.watch(jobQueueProvider);
    final queue = ref.read(jobQueueProvider.notifier);
    final active = jobs.where((j) => j.status.isActive).length;
    final completed = jobs.where((j) => j.status == JobStatus.completed).length;
    final failed = jobs.where((j) => j.status == JobStatus.failed).length;
    _syncTicker(jobs.any((j) => j.status == JobStatus.running));

    final visible = [
      for (final j in jobs)
        if (switch (_filter) {
          _Filter.all => true,
          _Filter.active => j.status.isActive,
          _Filter.completed => j.status == JobStatus.completed,
          _Filter.failed => j.status == JobStatus.failed || j.status == JobStatus.cancelled,
        })
          j,
    ];

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'tasks.title'.tr(),
            subtitle: 'tasks.subtitle'.tr(),
            actions: [
              if (active > 0)
                AppButton(
                  label: 'tasks.cancel_all'.tr(),
                  size: ButtonSize.sm,
                  onPressed: queue.cancelAll,
                ),
              if (jobs.length > active)
                AppButton.ghost(
                  label: 'tasks.clear_finished'.tr(),
                  icon: Icons.clear_all_rounded,
                  size: ButtonSize.sm,
                  onPressed: queue.clearFinished,
                ),
            ],
          ),
          if (jobs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xxxl, 0, Space.xxxl, Space.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 440,
                  child: Segmented<_Filter>(
                    value: _filter,
                    onChanged: (v) => setState(() => _filter = v),
                    items: [
                      ChoiceItem(_Filter.all, '${'tasks.all'.tr()} ${jobs.length}'),
                      ChoiceItem(_Filter.active, '${'tasks.active'.tr()} $active'),
                      ChoiceItem(_Filter.completed, '${'tasks.completed'.tr()} $completed'),
                      ChoiceItem(_Filter.failed, '${'tasks.failed'.tr()} $failed'),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: visible.isEmpty
                ? EmptyState(
                    icon: Icons.layers_outlined,
                    title: jobs.isEmpty ? 'tasks.empty_title'.tr() : 'tasks.empty_filter'.tr(),
                    message: jobs.isEmpty ? 'tasks.empty_message'.tr() : null,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(Space.xxxl, 0, Space.xxxl, Space.xxxl),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                    itemBuilder: (_, i) => JobCard(key: ValueKey(visible[i].id), job: visible[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class JobCard extends ConsumerStatefulWidget {
  const JobCard({super.key, required this.job});
  final Job job;

  @override
  ConsumerState<JobCard> createState() => _JobCardState();
}

class _JobCardState extends ConsumerState<JobCard> {
  bool _showLog = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final job = widget.job;
    final queue = ref.read(jobQueueProvider.notifier);
    final tool = toolById(job.spec.toolId);
    final output = job.spec.outputs.firstOrNull;
    final outputExists = output != null && FileSystemEntity.typeSync(output) != FileSystemEntityType.notFound;

    final (statusColor, statusIcon) = switch (job.status) {
      JobStatus.queued => (c.textSubtle, Icons.schedule_rounded),
      JobStatus.running => (c.accent, Icons.sync_rounded),
      JobStatus.completed => (c.success, Icons.check_circle_rounded),
      JobStatus.failed => (c.danger, Icons.error_rounded),
      JobStatus.cancelled => (c.textSubtle, Icons.block_rounded),
    };

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(
          color: job.status == JobStatus.failed ? c.danger.withValues(alpha: 0.35) : c.border,
        ),
      ),
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ToolIcon(
                icon: tool?.icon ?? Icons.work_outline_rounded,
                color: tool?.category.color ?? ToolCategory.media.color,
                size: 34,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.spec.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyles.body.copyWith(color: c.text, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      output == null ? '—' : '→ ${p.basename(output)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyles.caption.copyWith(color: c.textSubtle, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.md),
              _StatusPill(color: statusColor, icon: statusIcon, label: 'tasks.status.${job.status.name}'.tr()),
              const SizedBox(width: Space.sm),
              ..._actions(queue, job, output, outputExists),
            ],
          ),
          if (job.status == JobStatus.running || job.status == JobStatus.completed) ...[
            const SizedBox(height: Space.md),
            _ProgressRow(job: job),
          ],
          if (job.status == JobStatus.failed) ...[
            const SizedBox(height: Space.md),
            Notice(
              tone: NoticeTone.danger,
              message: job.errorKey != null ? job.errorKey!.tr(namedArgs: job.errorArgs) : (job.error ?? '—'),
            ),
          ],
          if (_showLog) ...[
            const SizedBox(height: Space.md),
            _LogView(log: queue.logOf(job.id), command: job.spec.commandLine),
          ],
        ],
      ),
    );
  }

  List<Widget> _actions(JobQueue queue, Job job, String? output, bool outputExists) {
    return [
      if (job.status.isActive)
        AppIconButton(icon: Icons.stop_rounded, tooltip: 'common.cancel'.tr(), onPressed: () => queue.cancel(job.id)),
      if (job.status == JobStatus.failed || job.status == JobStatus.cancelled)
        AppIconButton(icon: Icons.refresh_rounded, tooltip: 'tasks.retry'.tr(), onPressed: () => queue.retry(job.id)),
      if (job.status == JobStatus.completed && outputExists) ...[
        AppIconButton(
          icon: Icons.open_in_new_rounded,
          tooltip: 'common.open'.tr(),
          onPressed: () => PlatformActions.open(output!),
        ),
        AppIconButton(
          icon: Icons.folder_open_rounded,
          tooltip: 'common.reveal'.tr(),
          onPressed: () => PlatformActions.reveal(output!),
        ),
      ],
      AppIconButton(
        icon: _showLog ? Icons.expand_less_rounded : Icons.notes_rounded,
        tooltip: 'tasks.log'.tr(),
        onPressed: () => setState(() => _showLog = !_showLog),
      ),
      if (job.status.isFinished)
        AppIconButton(icon: Icons.close_rounded, tooltip: 'common.remove'.tr(), onPressed: () => queue.remove(job.id)),
    ];
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.color, required this.icon, required this.label});
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pr = job.progress;
    final fraction = pr.fraction;
    final done = job.status == JobStatus.completed;
    final stats = <String>[
      if (fraction != null) '${(fraction * 100).toStringAsFixed(done ? 0 : 1)}%',
      if (pr.stepLabel != null && !done) 'tasks.step'.tr(namedArgs: {'step': pr.stepLabel!}),
      if (pr.speed != null && pr.speed! > 0) '${pr.speed!.toStringAsFixed(2)}×',
      if (pr.fps != null && pr.fps! > 0 && !done) '${pr.fps!.round()} fps',
      if (job.elapsed != null) 'tasks.elapsed'.tr(namedArgs: {'t': Fmt.eta(job.elapsed!)}),
      if (job.eta != null) 'tasks.eta'.tr(namedArgs: {'t': Fmt.eta(job.eta!)}),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: done ? 1 : fraction,
            minHeight: 5,
            color: done ? c.success : c.accent,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          stats.join('  ·  '),
          style: TextStyles.caption.copyWith(color: c.textMuted, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}

class _LogView extends StatefulWidget {
  const _LogView({required this.log, this.command});
  final JobLog log;
  final String? command;

  @override
  State<_LogView> createState() => _LogViewState();
}

class _LogViewState extends State<_LogView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.command != null) ...[
          CommandPreview(command: widget.command!, maxHeight: 100),
          const SizedBox(height: Space.sm),
        ],
        ListenableBuilder(
          listenable: widget.log,
          builder: (context, _) {
            final lines = widget.log.lines;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
            });
            return Stack(
              children: [
                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: c.bg,
                    borderRadius: BorderRadius.circular(Radii.control + 2),
                    border: Border.all(color: c.border),
                  ),
                  child: lines.isEmpty
                      ? Center(
                          child: Text('tasks.log_empty'.tr(), style: TextStyles.caption.copyWith(color: c.textSubtle)),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(Space.md),
                          itemCount: lines.length,
                          itemBuilder: (_, i) => Text(
                            lines[i],
                            style: TextStyles.mono.copyWith(
                              fontSize: 11.5,
                              color: _isError(lines[i]) ? c.danger : c.textMuted,
                            ),
                          ),
                        ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: AppIconButton(
                    icon: Icons.copy_rounded,
                    tooltip: 'common.copy'.tr(),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.log.toString()));
                      showToast(context, 'common.copied'.tr());
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  static final _errorPattern = RegExp(r'error|invalid|failed|no such', caseSensitive: false);
  bool _isError(String line) => _errorPattern.hasMatch(line);
}
