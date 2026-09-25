import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/format.dart';
import '../../../ui/widgets/feedback.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/layout.dart';
import '../builders/codecs.dart' show fmtNum;
import '../builders/frames.dart';
import '../studio/studio_state.dart';
import '../studio/tool_panel.dart';

class FramesTool extends ConsumerStatefulWidget {
  const FramesTool({super.key});

  @override
  ConsumerState<FramesTool> createState() => _FramesToolState();
}

class _FramesToolState extends ConsumerState<FramesTool> {
  var _o = const FramesOptions();

  static const grids = [(3, 3), (4, 3), (4, 4), (5, 5), (6, 6)];

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final playhead = ref.watch(studioProvider.select((s) => s.playhead()));
    final single = o.mode == FramesMode.single;

    final fields = <Widget>[
      OptionField(
        label: 'media.frames.mode'.tr(),
        child: Segmented<FramesMode>(
          value: o.mode,
          onChanged: (v) => setState(() => _o = o.copyWith(mode: v, width: () => null)),
          items: [
            ChoiceItem(FramesMode.single, 'media.frames.single'.tr()),
            ChoiceItem(FramesMode.interval, 'media.frames.interval'.tr()),
            ChoiceItem(FramesMode.contactSheet, 'media.frames.sheet'.tr()),
          ],
        ),
      ),
      switch (o.mode) {
        FramesMode.single => OptionField(
          label: 'media.frames.at'.tr(),
          child: Notice(
            message: '${Fmt.timecode(playhead)}  ·  ${'studio.frame_at_playhead'.tr()}',
          ),
        ),
        FramesMode.interval => OptionField(
          label: 'media.frames.every'.tr(),
          child: ChoiceChips<double>(
            value: o.everySeconds,
            onChanged: (v) => setState(() => _o = o.copyWith(everySeconds: v)),
            items: [
              for (final s in const [0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0])
                ChoiceItem(s, 'media.frames.every_n'.tr(namedArgs: {'n': fmtNum(s)})),
            ],
          ),
        ),
        FramesMode.contactSheet => OptionField(
          label: 'media.frames.grid'.tr(),
          child: ChoiceChips<(int, int)>(
            value: (o.columns, o.rows),
            onChanged: (v) => setState(() => _o = o.copyWith(columns: v.$1, rows: v.$2)),
            items: [for (final g in grids) ChoiceItem(g, '${g.$1} × ${g.$2}')],
          ),
        ),
      },
      OptionField(
        label: o.mode == FramesMode.contactSheet ? 'media.frames.tile_width'.tr() : 'media.frames.width'.tr(),
        child: ChoiceChips<int?>(
          value: o.width,
          onChanged: (v) => setState(() => _o = o.copyWith(width: () => v)),
          items: o.mode == FramesMode.contactSheet
              ? [
                  ChoiceItem(null, 'media.auto'.tr()),
                  for (final w in const [240, 480, 640]) ChoiceItem(w, '$w px'),
                ]
              : [
                  ChoiceItem(null, 'media.original'.tr()),
                  for (final w in const [1920, 1280, 640, 320]) ChoiceItem(w, '$w px'),
                ],
        ),
      ),
      OptionField(
        label: 'media.frames.format'.tr(),
        child: Segmented<ImageFormat>(
          value: o.format,
          onChanged: (v) => setState(() => _o = o.copyWith(format: v)),
          items: const [ChoiceItem(ImageFormat.jpg, 'JPG'), ChoiceItem(ImageFormat.png, 'PNG')],
        ),
      ),
    ];

    return StudioToolView(
      toolId: 'frames',
      actionKey: 'media.frames.action',
      fields: fields,
      // A single snapshot is positioned by the playhead, not a selection.
      range: single ? RangeUsage.none : RangeUsage.optional,
      planner: (r) {
        final opts = o.copyWith(at: r.playhead);
        return [
          for (final input in r.inputs)
            PlannedJob(
              inputs: [input],
              plan: buildFrames(
                input: input,
                output: switch (o.mode) {
                  FramesMode.interval => r.out.folder(input, suffix: 'frames'),
                  FramesMode.single => r.out.file(
                    input,
                    extension: o.format.extension,
                    suffix: 'frame_${Fmt.seconds(r.playhead).replaceAll('.', '_')}s',
                  ),
                  FramesMode.contactSheet => r.out.file(input, extension: o.format.extension, suffix: 'sheet'),
                },
                options: opts,
                info: r.infos[input],
              ),
            ),
        ];
      },
    );
  }
}
