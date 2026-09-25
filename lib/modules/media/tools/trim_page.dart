import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../ui/widgets/feedback.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/layout.dart';
import '../builders/trim.dart';
import '../engine/command_plan.dart';
import '../providers.dart';
import '../studio/studio_state.dart';
import '../studio/tool_panel.dart';
import '../widgets/time_field.dart';

/// Cuts the timeline selection out of the active file.
class TrimTool extends ConsumerStatefulWidget {
  const TrimTool({super.key});

  @override
  ConsumerState<TrimTool> createState() => _TrimToolState();
}

class _TrimToolState extends ConsumerState<TrimTool> {
  bool _precise = false;

  @override
  Widget build(BuildContext context) {
    final studio = ref.watch(studioProvider);
    final notifier = ref.read(studioProvider.notifier);
    final info = studio.active == null ? null : ref.watch(probeProvider(studio.active!)).value;
    final total = info?.duration ?? Duration.zero;
    final range = studio.range() ?? ClipRange(Duration.zero, total);

    final fields = <Widget>[
      OptionField(
        label: 'media.trim.range'.tr(),
        hint: 'studio.range_hint'.tr(),
        child: Row(
          children: [
            Expanded(
              child: TimecodeField(
                label: 'studio.in'.tr(),
                value: range.start,
                max: total,
                onChanged: (v) {
                  notifier.setRange(v, range.end < v ? total : range.end);
                  notifier.setPlayhead(v);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TimecodeField(
                label: 'studio.out'.tr(),
                value: range.end,
                max: total,
                onChanged: (v) {
                  notifier.setRange(range.start > v ? Duration.zero : range.start, v);
                  notifier.setPlayhead(v);
                },
              ),
            ),
          ],
        ),
      ),
      OptionField(
        label: 'media.trim.mode'.tr(),
        child: Segmented<bool>(
          value: _precise,
          onChanged: (v) => setState(() => _precise = v),
          items: [
            ChoiceItem(false, 'media.trim.fast'.tr(), icon: Icons.bolt_rounded),
            ChoiceItem(true, 'media.trim.precise'.tr(), icon: Icons.center_focus_strong_rounded),
          ],
        ),
      ),
      Notice(message: (_precise ? 'media.trim.precise_hint' : 'media.trim.fast_hint').tr()),
    ];

    return StudioToolView(
      toolId: 'trim',
      actionKey: 'media.trim.action',
      fields: fields,
      batchable: false,
      range: RangeUsage.native,
      planner: (r) {
        final input = r.inputs.single;
        final info = r.infos[input]!;
        final range = r.range ?? (throw const PlanException('studio.errors.need_range'));
        final ext = trimExtension(p.extension(input), precise: _precise, hasVideo: info.hasVideo);
        return [
          PlannedJob(
            inputs: [input],
            plan: buildTrim(
              input: input,
              output: r.out.file(input, extension: ext, suffix: 'trim'),
              info: info,
              options: TrimOptions(start: range.start, end: range.end, precise: _precise),
            ),
          ),
        ];
      },
    );
  }
}
