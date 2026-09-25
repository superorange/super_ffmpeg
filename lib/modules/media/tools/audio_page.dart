import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/widgets/feedback.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/layout.dart';
import '../builders/audio.dart';
import '../studio/tool_panel.dart';

class AudioTool extends ConsumerStatefulWidget {
  const AudioTool({super.key});

  @override
  ConsumerState<AudioTool> createState() => _AudioToolState();
}

class _AudioToolState extends ConsumerState<AudioTool> {
  var _o = const AudioOptions();

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final passthrough = o.format == AudioFormat.original;

    final fields = <Widget>[
      OptionField(
        label: 'media.audio.format'.tr(),
        child: ChoiceChips<AudioFormat>(
          value: o.format,
          onChanged: (v) => setState(() => _o = o.copyWith(format: v)),
          items: [
            const ChoiceItem(AudioFormat.mp3, 'MP3'),
            const ChoiceItem(AudioFormat.aac, 'AAC'),
            const ChoiceItem(AudioFormat.opus, 'Opus'),
            ChoiceItem(AudioFormat.flac, 'FLAC', hint: 'media.audio.lossless'.tr()),
            ChoiceItem(AudioFormat.wav, 'WAV', hint: 'media.audio.lossless'.tr()),
            ChoiceItem(AudioFormat.original, 'media.audio.original'.tr(), hint: 'media.audio.original_hint'.tr()),
          ],
        ),
      ),
      if (passthrough)
        Notice(message: 'media.audio.original_hint'.tr())
      else ...[
        if (o.format.lossy)
          OptionField(
            label: 'media.audio.bitrate'.tr(),
            child: Segmented<int>(
              value: o.bitrateKbps,
              onChanged: (v) => setState(() => _o = o.copyWith(bitrateKbps: v)),
              items: [
                for (final k in const [96, 128, 192, 256, 320]) ChoiceItem(k, '$k'),
              ],
            ),
          ),
        OptionField(
          label: 'media.audio.sample_rate'.tr(),
          child: Segmented<int?>(
            value: o.sampleRate,
            onChanged: (v) => setState(() => _o = o.copyWith(sampleRate: () => v)),
            items: [
              ChoiceItem(null, 'media.original'.tr()),
              const ChoiceItem(44100, '44.1 kHz'),
              const ChoiceItem(48000, '48 kHz'),
            ],
          ),
        ),
        OptionField(
          label: 'media.audio.channels'.tr(),
          child: Segmented<int?>(
            value: o.channels,
            onChanged: (v) => setState(() => _o = o.copyWith(channels: () => v)),
            items: [
              ChoiceItem(null, 'media.original'.tr()),
              ChoiceItem(1, 'media.audio.mono'.tr()),
              ChoiceItem(2, 'media.audio.stereo'.tr()),
            ],
          ),
        ),
        OptionRow(
          label: 'media.audio.normalize'.tr(),
          hint: 'media.audio.normalize_hint'.tr(),
          control: AppSwitch(
            value: o.normalize,
            onChanged: (v) => setState(() => _o = o.copyWith(normalize: v)),
          ),
        ),
        OptionField(
          label: 'media.audio.gain'.tr(),
          child: LabeledSlider(
            value: o.gainDb,
            min: -12,
            max: 12,
            divisions: 24,
            format: (v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(0)} dB',
            onChanged: (v) => setState(() => _o = o.copyWith(gainDb: v.roundToDouble())),
          ),
        ),
      ],
    ];

    return StudioToolView(
      toolId: 'audio',
      actionKey: 'media.audio.action',
      fields: fields,
      planner: (r) => [
        for (final input in r.inputs)
          PlannedJob(
            inputs: [input],
            plan: buildAudio(
              input: input,
              output: r.out.file(input, extension: audioExtension(o, r.infos[input])),
              options: o,
              info: r.infos[input],
            ),
          ),
      ],
    );
  }
}
