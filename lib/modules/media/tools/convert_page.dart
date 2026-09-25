import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/feedback.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/layout.dart';
import '../builders/codecs.dart';
import '../builders/convert.dart';
import '../providers.dart';
import '../studio/tool_panel.dart';

class ConvertTool extends ConsumerStatefulWidget {
  const ConvertTool({super.key});

  @override
  ConsumerState<ConvertTool> createState() => _ConvertToolState();
}

class _ConvertToolState extends ConsumerState<ConvertTool> {
  var _o = const ConvertOptions();
  bool? _gpuOverride;

  static const codecLabels = {
    VideoCodec.h264: 'H.264',
    VideoCodec.hevc: 'HEVC',
    VideoCodec.av1: 'AV1',
    VideoCodec.vp9: 'VP9',
    VideoCodec.prores: 'ProRes',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final encoders = ref.watch(ffmpegCapabilitiesProvider).value?.encoders ?? const <String>{};
    final settingsGpu = ref.watch(settingsProvider.select((s) => s.preferGpu));
    final preferGpu = _gpuOverride ?? settingsGpu;
    final o = _o.copyWith(preferGpu: preferGpu);
    final choice = Encoders.pick(o.codec, encoders, preferGpu: preferGpu);
    final isCopy = o.codec == VideoCodec.copy;

    final fields = <Widget>[
      OptionField(
        label: 'media.convert.container'.tr(),
        child: Segmented<MediaContainer>(
          value: o.container,
          onChanged: (v) => setState(() => _o = _o.withContainer(v, encoders)),
          items: [for (final m in MediaContainer.values) ChoiceItem(m, m.name.toUpperCase())],
        ),
      ),
      OptionField(
        label: 'media.convert.codec'.tr(),
        trailing: choice == null || isCopy
            ? null
            : Tag(
                choice.encoder,
                color: choice.hardware ? c.success : null,
                icon: choice.hardware ? Icons.bolt_rounded : null,
              ),
        child: ChoiceChips<VideoCodec>(
          value: o.codec,
          onChanged: (v) => setState(() => _o = _o.withCodec(v)),
          items: [
            for (final entry in codecLabels.entries)
              ChoiceItem(
                entry.key,
                entry.value,
                enabled: entry.key.isAvailable(encoders),
                hint: entry.key.isAvailable(encoders) ? null : 'media.convert.codec_unavailable'.tr(),
              ),
            ChoiceItem(VideoCodec.copy, 'media.convert.copy'.tr(), hint: 'media.convert.copy_hint'.tr()),
          ],
        ),
      ),
      OptionField(
        label: 'media.convert.audio'.tr(),
        child: Segmented<AudioMode>(
          value: o.audio,
          onChanged: (v) => setState(() => _o = _o.copyWith(audio: v)),
          items: [
            ChoiceItem(AudioMode.auto, 'media.convert.audio_auto'.tr()),
            ChoiceItem(AudioMode.copy, 'media.convert.audio_copy'.tr()),
            ChoiceItem(AudioMode.remove, 'media.convert.audio_remove'.tr()),
          ],
        ),
      ),
      if (!isCopy) ...[
        OptionField(
          label: 'media.quality.label'.tr(),
          child: Segmented<QualityLevel>(
            value: o.quality,
            onChanged: (v) => setState(() => _o = _o.copyWith(quality: v)),
            items: [
              ChoiceItem(QualityLevel.high, 'media.quality.high'.tr()),
              ChoiceItem(QualityLevel.balanced, 'media.quality.balanced'.tr()),
              ChoiceItem(QualityLevel.small, 'media.quality.small'.tr()),
            ],
          ),
        ),
        OptionField(
          label: 'media.resolution.label'.tr(),
          hint: 'media.resolution.hint'.tr(),
          child: ChoiceChips<Resolution>(
            value: o.resolution,
            onChanged: (v) => setState(() => _o = _o.copyWith(resolution: v)),
            items: resolutionItems(),
          ),
        ),
        OptionField(
          label: 'media.convert.fps'.tr(),
          child: Segmented<FrameRateOption>(
            value: o.frameRate,
            onChanged: (v) => setState(() => _o = _o.copyWith(frameRate: v)),
            items: [
              for (final f in FrameRateOption.values) ChoiceItem(f, f.fps == null ? 'media.original'.tr() : '${f.fps}'),
            ],
          ),
        ),
        OptionField(
          label: 'media.convert.speed'.tr(),
          hint: 'media.convert.speed_hint'.tr(),
          child: Segmented<EncodeSpeed>(
            value: o.speed,
            onChanged: (v) => setState(() => _o = _o.copyWith(speed: v)),
            items: [
              ChoiceItem(EncodeSpeed.fast, 'media.convert.speed_fast'.tr()),
              ChoiceItem(EncodeSpeed.medium, 'media.convert.speed_medium'.tr()),
              ChoiceItem(EncodeSpeed.slow, 'media.convert.speed_slow'.tr()),
            ],
          ),
        ),
        OptionRow(
          label: 'media.gpu.label'.tr(),
          hint: 'media.gpu.hint'.tr(),
          control: AppSwitch(value: preferGpu, onChanged: (v) => setState(() => _gpuOverride = v)),
        ),
      ],
    ];

    return StudioToolView(
      toolId: 'convert',
      actionKey: 'media.convert.action',
      fields: fields,
      planner: (r) => [
        for (final input in r.inputs)
          PlannedJob(
            inputs: [input],
            plan: buildConvert(
              input: input,
              output: r.out.file(input, extension: o.container.extension, suffix: o.codec.name),
              options: o,
              encoders: r.encoders,
              info: r.infos[input],
            ),
          ),
      ],
    );
  }
}

List<ChoiceItem<Resolution>> resolutionItems({bool includeOriginal = true, String? originalLabel}) => [
  if (includeOriginal) ChoiceItem(Resolution.original, originalLabel ?? 'media.original'.tr()),
  const ChoiceItem(Resolution.p2160, '4K'),
  const ChoiceItem(Resolution.p1440, '1440p'),
  const ChoiceItem(Resolution.p1080, '1080p'),
  const ChoiceItem(Resolution.p720, '720p'),
  const ChoiceItem(Resolution.p480, '480p'),
];
