import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/format.dart';
import '../../../ui/widgets/feedback.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/layout.dart';
import '../builders/gif.dart';
import '../engine/media_info.dart';
import '../providers.dart';
import '../studio/studio_state.dart';
import '../studio/tool_panel.dart';

/// Segment a GIF is made from: the selection, or [fallback] from the playhead.
ClipRange gifSegment(
  MediaInfo info,
  ClipRange? selection,
  Duration playhead, {
  Duration fallback = const Duration(seconds: 5),
}) {
  if (selection != null) return selection;
  final total = info.duration;
  var start = playhead;
  if (total > Duration.zero && start + fallback > total) {
    start = total - fallback < Duration.zero ? Duration.zero : total - fallback;
  }
  final end = total > Duration.zero && start + fallback > total ? total : start + fallback;
  return ClipRange(start, end);
}

class GifTool extends ConsumerStatefulWidget {
  const GifTool({super.key});

  @override
  ConsumerState<GifTool> createState() => _GifToolState();
}

class _GifToolState extends ConsumerState<GifTool> {
  var _o = const GifOptions();

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final studio = ref.watch(studioProvider);
    final info = studio.active == null ? null : ref.watch(probeProvider(studio.active!)).value;
    final selection = studio.range();
    final partial = info != null && selection != null && selection.isPartialOf(info.duration);
    final segment = info == null ? null : gifSegment(info, partial ? selection : null, studio.playhead());

    final fields = <Widget>[
      OptionField(
        label: 'media.gif.segment'.tr(),
        child: Notice(
          tone: segment != null && segment.length > const Duration(seconds: 30) ? NoticeTone.warning : NoticeTone.info,
          message: segment == null
              ? 'studio.range_hint'.tr()
              : '${Fmt.shortTime(segment.start)} – ${Fmt.shortTime(segment.end)}  ·  ${Fmt.shortTime(segment.length)}\n'
                    '${(partial ? 'media.gif.segment_selection' : 'media.gif.segment_playhead').tr()}',
        ),
      ),
      OptionField(
        label: 'media.gif.fps'.tr(),
        hint: 'media.gif.fps_hint'.tr(),
        child: Segmented<int>(
          value: o.fps,
          onChanged: (v) => setState(() => _o = o.copyWith(fps: v)),
          items: [
            for (final f in const [10, 15, 20, 25, 30]) ChoiceItem(f, '$f'),
          ],
        ),
      ),
      OptionField(
        label: 'media.gif.width'.tr(),
        child: ChoiceChips<int?>(
          value: o.width,
          onChanged: (v) => setState(() => _o = o.copyWith(width: () => v)),
          items: [
            for (final w in const [320, 480, 640, 800]) ChoiceItem(w, '$w px'),
            ChoiceItem(null, 'media.original'.tr()),
          ],
        ),
      ),
      OptionField(
        label: 'media.gif.dither'.tr(),
        hint: 'media.gif.dither_hint'.tr(),
        child: Segmented<GifDither>(
          value: o.dither,
          onChanged: (v) => setState(() => _o = o.copyWith(dither: v)),
          items: [
            ChoiceItem(GifDither.sierra, 'media.gif.dither_smooth'.tr()),
            ChoiceItem(GifDither.bayer, 'media.gif.dither_pattern'.tr()),
            ChoiceItem(GifDither.floyd, 'media.gif.dither_diffuse'.tr()),
            ChoiceItem(GifDither.none, 'media.gif.dither_none'.tr()),
          ],
        ),
      ),
      OptionRow(
        label: 'media.gif.loop'.tr(),
        control: AppSwitch(
          value: o.loop,
          onChanged: (v) => setState(() => _o = o.copyWith(loop: v)),
        ),
      ),
    ];

    return StudioToolView(
      toolId: 'gif',
      actionKey: 'media.gif.action',
      fields: fields,
      range: RangeUsage.native,
      planner: (r) => [
        for (final input in r.inputs)
          PlannedJob(
            inputs: [input],
            plan: () {
              final info = r.infos[input]!;
              // Batch: each file from its own start; single: the timeline segment.
              final seg = r.inputs.length == 1
                  ? gifSegment(info, r.range, r.playhead)
                  : gifSegment(info, null, Duration.zero);
              return buildGif(
                input: input,
                output: r.out.file(input, extension: 'gif'),
                options: o.copyWith(start: seg.start, duration: () => seg.length),
                info: info,
              );
            }(),
          ),
      ],
    );
  }
}
