import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings.dart';
import '../../../core/utils/format.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/feedback.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/layout.dart';
import '../builders/concat.dart';
import '../engine/command_plan.dart';
import '../providers.dart';
import '../studio/studio_state.dart';
import '../studio/tool_panel.dart';
import '../widgets/media_file_tile.dart';

/// Joins every file in the studio library, in library order.
class ConcatTool extends ConsumerStatefulWidget {
  const ConcatTool({super.key});

  @override
  ConsumerState<ConcatTool> createState() => _ConcatToolState();
}

class _ConcatToolState extends ConsumerState<ConcatTool> {
  var _mode = ConcatMode.compatible;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final preferGpu = ref.watch(settingsProvider.select((s) => s.preferGpu));
    final studio = ref.watch(studioProvider);
    final notifier = ref.read(studioProvider.notifier);
    final files = studio.files;
    final total = files.fold<Duration>(
      Duration.zero,
      (sum, i) => sum + (ref.watch(probeProvider(i)).value?.duration ?? Duration.zero),
    );

    final order = Panel(
      title: 'media.concat.order'.tr(),
      trailing: Text(
        '${'media.concat.clips'.tr()} ${files.length}  ·  ${'media.concat.total'.tr()} ${Fmt.duration(total)}',
        style: TextStyles.caption.copyWith(color: c.textSubtle),
      ),
      child: files.length < 2
          ? Notice(message: 'media.concat.need_two'.tr())
          : ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: files.length,
              onReorderItem: notifier.move,
              proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
              itemBuilder: (_, i) => Padding(
                key: ValueKey(files[i]),
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: MediaFileTile(
                  path: files[i],
                  index: i,
                  onRemove: () => notifier.remove(files[i]),
                  dragHandle: ReorderableDragStartListener(
                    index: i,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.drag_indicator_rounded, size: 18, color: c.textSubtle),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );

    final fields = <Widget>[
      OptionField(
        label: 'media.concat.mode'.tr(),
        child: Segmented<ConcatMode>(
          value: _mode,
          onChanged: (v) => setState(() => _mode = v),
          items: [
            ChoiceItem(ConcatMode.compatible, 'media.concat.compatible'.tr()),
            ChoiceItem(ConcatMode.fast, 'media.concat.fast'.tr(), icon: Icons.bolt_rounded),
          ],
        ),
      ),
      Notice(
        tone: _mode == ConcatMode.fast ? NoticeTone.warning : NoticeTone.info,
        message: (_mode == ConcatMode.fast ? 'media.concat.fast_hint' : 'media.concat.compatible_hint').tr(),
      ),
    ];

    return StudioToolView(
      toolId: 'concat',
      actionKey: 'media.concat.action',
      header: order,
      fields: fields,
      scope: InputScope.library,
      batchable: false,
      range: RangeUsage.none,
      planner: (r) {
        if (r.inputs.length < 2) throw const PlanException('media.concat.need_two');
        final first = r.inputs.first;
        return [
          PlannedJob(
            inputs: r.inputs,
            plan: buildConcat(
              inputs: r.inputs,
              output: r.out.file(first, extension: concatExtension(r.inputs, _mode), suffix: 'merged'),
              options: ConcatOptions(mode: _mode, preferGpu: preferGpu),
              encoders: r.encoders,
              infos: [for (final i in r.inputs) r.infos[i]],
              listPath: r.out.temp('concat.txt'),
            ),
          ),
        ];
      },
    );
  }
}
