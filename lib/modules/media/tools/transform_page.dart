import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/layout.dart';
import '../builders/codecs.dart';
import '../builders/transform.dart';
import '../studio/studio_state.dart';
import '../studio/tool_panel.dart';

class TransformTool extends ConsumerStatefulWidget {
  const TransformTool({super.key});

  @override
  ConsumerState<TransformTool> createState() => _TransformToolState();
}

class _TransformToolState extends ConsumerState<TransformTool> {
  var _o = const TransformOptions();

  static const speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0];

  StagePreview? _lastPreview;

  /// Mirror rotation / flip / reframing on the studio stage.
  void _syncStage(TransformOptions o) {
    final preview = StagePreview(
      quarterTurns: switch (o.rotation) {
        Rotation.none => 0,
        Rotation.cw90 => 1,
        Rotation.ccw90 => 3,
        Rotation.r180 => 2,
      },
      flipH: o.flipH,
      flipV: o.flipV,
      aspect: switch (o.framing) {
        Framing.original => null,
        Framing.vertical916 => 9 / 16,
        Framing.square11 => 1,
        Framing.landscape169 => 16 / 9,
      },
    );
    if (_lastPreview != null &&
        _lastPreview!.quarterTurns == preview.quarterTurns &&
        _lastPreview!.flipH == preview.flipH &&
        _lastPreview!.flipV == preview.flipV &&
        _lastPreview!.aspect == preview.aspect) {
      return;
    }
    _lastPreview = preview;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(stagePreviewProvider.notifier).set(preview);
    });
  }

  @override
  Widget build(BuildContext context) {
    final o = _o.copyWith(preferGpu: ref.watch(settingsProvider.select((s) => s.preferGpu)));

    _syncStage(o);
    final fields = <Widget>[
      OptionField(
        label: 'media.transform.speed'.tr(),
        hint: 'media.transform.speed_hint'.tr(),
        child: ChoiceChips<double>(
          value: o.speed,
          onChanged: (v) => setState(() => _o = _o.copyWith(speed: v)),
          items: [for (final s in speeds) ChoiceItem(s, '${fmtNum(s)}×')],
        ),
      ),
      OptionField(
        label: 'media.transform.rotate'.tr(),
        child: Segmented<Rotation>(
          value: o.rotation,
          onChanged: (v) => setState(() => _o = _o.copyWith(rotation: v)),
          items: [
            ChoiceItem(Rotation.none, 'media.transform.rotate_none'.tr()),
            const ChoiceItem(Rotation.cw90, '90°', icon: Icons.rotate_right_rounded),
            const ChoiceItem(Rotation.ccw90, '90°', icon: Icons.rotate_left_rounded),
            const ChoiceItem(Rotation.r180, '180°'),
          ],
        ),
      ),
      OptionField(
        label: 'media.transform.flip'.tr(),
        child: Wrap(
          spacing: 6,
          children: [
            SelectableChip(
              label: 'media.transform.flip_h'.tr(),
              icon: Icons.flip_rounded,
              selected: o.flipH,
              onTap: () => setState(() => _o = _o.copyWith(flipH: !o.flipH)),
            ),
            SelectableChip(
              label: 'media.transform.flip_v'.tr(),
              icon: Icons.flip_rounded,
              selected: o.flipV,
              onTap: () => setState(() => _o = _o.copyWith(flipV: !o.flipV)),
            ),
          ],
        ),
      ),
      OptionField(
        label: 'media.transform.framing'.tr(),
        hint: 'media.transform.framing_hint'.tr(),
        child: ChoiceChips<Framing>(
          value: o.framing,
          onChanged: (v) => setState(() => _o = _o.copyWith(framing: v)),
          items: [
            ChoiceItem(Framing.original, 'media.original'.tr()),
            ChoiceItem(
              Framing.vertical916,
              'media.transform.vertical'.tr(),
              icon: Icons.stay_current_portrait_rounded,
            ),
            ChoiceItem(Framing.square11, 'media.transform.square'.tr(), icon: Icons.crop_square_rounded),
            ChoiceItem(
              Framing.landscape169,
              'media.transform.landscape'.tr(),
              icon: Icons.stay_current_landscape_rounded,
            ),
          ],
        ),
      ),
      OptionRow(
        label: 'media.transform.mute'.tr(),
        control: AppSwitch(
          value: o.mute,
          onChanged: (v) => setState(() => _o = _o.copyWith(mute: v)),
        ),
      ),
    ];

    return StudioToolView(
      toolId: 'transform',
      actionKey: 'media.transform.action',
      fields: fields,
      planner: (r) => [
        for (final input in r.inputs)
          PlannedJob(
            inputs: [input],
            plan: buildTransform(
              input: input,
              output: r.out.file(input, extension: 'mp4', suffix: 'edited'),
              options: o,
              encoders: r.encoders,
              info: r.infos[input],
            ),
          ),
      ],
    );
  }
}
