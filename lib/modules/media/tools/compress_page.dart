import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/format.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/feedback.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/layout.dart';
import '../builders/codecs.dart';
import '../builders/compress.dart';
import '../engine/command_plan.dart';
import '../engine/media_info.dart';
import '../providers.dart';
import '../studio/studio_state.dart';
import '../studio/tool_panel.dart';
import 'convert_page.dart' show resolutionItems;

class CompressTool extends ConsumerStatefulWidget {
  const CompressTool({super.key});

  @override
  ConsumerState<CompressTool> createState() => _CompressToolState();
}

class _CompressToolState extends ConsumerState<CompressTool> {
  var _o = const CompressOptions();
  final _customMb = TextEditingController();

  static const presetsMb = [8.0, 10.0, 25.0, 50.0, 100.0];

  @override
  void dispose() {
    _customMb.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final encoders = ref.watch(ffmpegCapabilitiesProvider).value?.encoders ?? const <String>{};
    final studio = ref.watch(studioProvider);
    final activeInfo = studio.active == null ? null : ref.watch(probeProvider(studio.active!)).value;
    final selection = studio.range();
    // Budget preview follows what will actually be encoded: the selection
    // when one is set, otherwise the whole file.
    final single = activeInfo == null || studio.batch && studio.files.length > 1
        ? null
        : selection != null && selection.isPartialOf(activeInfo.duration)
        ? activeInfo.clipped(selection.length)
        : activeInfo;
    final o = _o;
    final isTarget = o.mode == CompressMode.targetSize;

    final fields = <Widget>[
      OptionField(
        label: 'media.compress.mode'.tr(),
        child: Segmented<CompressMode>(
          value: o.mode,
          onChanged: (v) => setState(() => _o = o.copyWith(mode: v)),
          items: [
            ChoiceItem(CompressMode.quality, 'media.compress.by_quality'.tr(), icon: Icons.tune_rounded),
            ChoiceItem(CompressMode.targetSize, 'media.compress.by_size'.tr(), icon: Icons.straighten_rounded),
          ],
        ),
      ),
      if (!isTarget) ...[
        OptionField(
          label: 'media.compress.level'.tr(),
          hint: 'media.compress.level_hint'.tr(),
          child: Segmented<CompressLevel>(
            value: o.level,
            onChanged: (v) => setState(() => _o = o.copyWith(level: v)),
            items: [
              ChoiceItem(CompressLevel.light, 'media.compress.light'.tr()),
              ChoiceItem(CompressLevel.standard, 'media.compress.standard'.tr()),
              ChoiceItem(CompressLevel.strong, 'media.compress.strong'.tr()),
            ],
          ),
        ),
        OptionField(
          label: 'media.compress.codec'.tr(),
          child: Segmented<bool>(
            value: o.useHevc && encoders.contains('libx265'),
            onChanged: (v) => setState(() => _o = o.copyWith(useHevc: v)),
            items: [
              ChoiceItem(false, 'media.compress.h264'.tr()),
              ChoiceItem(true, 'media.compress.hevc'.tr(), enabled: encoders.contains('libx265')),
            ],
          ),
        ),
      ] else ...[
        OptionField(
          label: 'media.compress.target'.tr(),
          hint: 'media.compress.target_hint'.tr(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final mb in presetsMb)
                    SelectableChip(
                      label: '${mb.toStringAsFixed(0)} MB',
                      selected: o.targetMb == mb,
                      onTap: () {
                        _customMb.clear();
                        setState(() => _o = o.copyWith(targetMb: mb));
                      },
                    ),
                ],
              ),
              const SizedBox(height: Space.sm),
              TextField(
                controller: _customMb,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(
                  hintText: 'media.compress.custom_mb'.tr(),
                  suffixText: 'MB',
                ),
                onChanged: (v) {
                  final mb = double.tryParse(v);
                  if (mb != null && mb > 0) setState(() => _o = o.copyWith(targetMb: mb));
                },
              ),
            ],
          ),
        ),
        if (single != null) _BudgetPreview(info: single, targetMb: o.targetMb),
      ],
      OptionField(
        label: 'media.resolution.label'.tr(),
        hint: isTarget ? 'media.compress.auto_res_hint'.tr() : null,
        child: ChoiceChips<Resolution>(
          value: o.resolution,
          onChanged: (v) => setState(() => _o = o.copyWith(resolution: v)),
          items: resolutionItems(originalLabel: isTarget ? 'media.auto'.tr() : null)
              .where((i) => i.value != Resolution.p2160 && i.value != Resolution.p1440)
              .toList(),
        ),
      ),
      if (!isTarget && single != null && single.sizeBytes > 0)
        Text(
          'media.compress.source_size'.tr(namedArgs: {'size': Fmt.bytes(single.sizeBytes)}),
          style: TextStyles.caption.copyWith(color: c.textSubtle),
        ),
    ];

    return StudioToolView(
      toolId: 'compress',
      actionKey: 'media.compress.action',
      fields: fields,
      planner: (r) => [
        for (final input in r.inputs)
          PlannedJob(
            inputs: [input],
            plan: buildCompress(
              input: input,
              output: r.out.file(input, extension: 'mp4', suffix: 'compressed'),
              options: o,
              encoders: r.encoders,
              info: r.infos[input],
              passLogPrefix: r.out.temp('2pass'),
            ),
          ),
      ],
    );
  }
}

class _BudgetPreview extends StatelessWidget {
  const _BudgetPreview({required this.info, required this.targetMb});
  final MediaInfo info;
  final double targetMb;

  @override
  Widget build(BuildContext context) {
    try {
      final b = SizeBudget.compute(targetMb: targetMb, duration: info.duration, hasAudio: info.hasAudio);
      final short = autoShortSideForBudget(b.videoKbps, info.video);
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.lg),
        child: Notice(
          message: [
            'media.compress.budget'.tr(namedArgs: {'video': '${b.videoKbps}', 'audio': '${b.audioKbps}'}),
            if (short != null) 'media.compress.will_downscale'.tr(namedArgs: {'res': '${short}p'}),
          ].join(' · '),
        ),
      );
    } on PlanException catch (e) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.lg),
        child: Notice(
          tone: NoticeTone.warning,
          message: e.messageKey.tr(namedArgs: e.args),
        ),
      );
    }
  }
}
