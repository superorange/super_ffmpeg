import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/format.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/feedback.dart';
import '../../../ui/widgets/layout.dart';
import '../engine/media_info.dart';
import '../providers.dart';
import '../studio/studio_state.dart';
import '../widgets/media_file_tile.dart';

/// Full container and stream report for the active file.
class InspectTool extends ConsumerWidget {
  const InspectTool({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final path = ref.watch(studioProvider.select((s) => s.active));
    final info = path == null ? null : ref.watch(probeProvider(path));
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.xxl, Space.lg, Space.xxl, Space.xxxl),
      children: [
        switch (info) {
          null => const SizedBox(),
          AsyncData(:final value) => _Report(info: value),
          AsyncError(:final error) => Notice(tone: NoticeTone.danger, message: '$error'),
          _ => Padding(
            padding: const EdgeInsets.all(Space.xxxl),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
          ),
        },
      ],
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.info});
  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final streams = info.streams;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.basename(info.path), style: TextStyles.heading.copyWith(color: c.text)),
                    const SizedBox(height: Space.sm),
                    MediaFacts(info: info),
                    const SizedBox(height: Space.md),
                    KeyValueList(
                      entries: [
                        (
                          'media.inspect.container'.tr(),
                          info.formatLongName.isEmpty ? info.formatName : info.formatLongName,
                        ),
                        ('media.inspect.duration'.tr(), Fmt.timecode(info.duration)),
                        (
                          'media.inspect.size'.tr(),
                          '${Fmt.bytes(info.sizeBytes)}  (${NumberFormat.decimalPattern().format(info.sizeBytes)} B)',
                        ),
                        ('media.inspect.bitrate'.tr(), Fmt.bitrate(info.bitrate)),
                        ('media.inspect.path'.tr(), info.path),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        LayoutBuilder(
          builder: (context, box) {
            final cols = box.maxWidth > 900 ? 2 : 1;
            final width = (box.maxWidth - Space.lg * (cols - 1)) / cols;
            return Wrap(
              spacing: Space.lg,
              runSpacing: Space.lg,
              children: [
                for (final s in streams)
                  SizedBox(
                    width: width,
                    child: _StreamCard(stream: s),
                  ),
              ],
            );
          },
        ),
        if (info.tags.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          Panel(
            title: 'media.inspect.tags'.tr(),
            child: KeyValueList(entries: [for (final e in info.tags.entries) (e.key, e.value)], keyWidth: 160),
          ),
        ],
        const SizedBox(height: Space.lg),
        Panel(
          title: 'media.inspect.raw'.tr(),
          trailing: AppButton.ghost(
            label: 'common.copy'.tr(),
            icon: Icons.copy_rounded,
            size: ButtonSize.sm,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: info.rawJson));
              showToast(context, 'common.copied'.tr());
            },
          ),
          child: Disclosure(
            title: 'media.inspect.show_json'.tr(),
            child: CommandPreview(command: info.rawJson, maxHeight: 420),
          ),
        ),
      ],
    );
  }
}

class _StreamCard extends StatelessWidget {
  const _StreamCard({required this.stream});
  final MediaStream stream;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = stream;
    final (icon, kindLabel) = switch (s.kind) {
      StreamKind.video => (Icons.movie_outlined, s.isAttachedPicture ? 'media.inspect.cover' : 'media.inspect.video'),
      StreamKind.audio => (Icons.graphic_eq_rounded, 'media.inspect.audio'),
      StreamKind.subtitle => (Icons.subtitles_outlined, 'media.inspect.subtitle'),
      _ => (Icons.data_object_rounded, 'media.inspect.data'),
    };
    final entries = <(String, String)>[
      ('media.inspect.codec'.tr(), s.codecLong.isEmpty ? s.codec : '${s.codec} · ${s.codecLong}'),
      if (s.profile != null) ('Profile', s.profile!),
      if (s.kind == StreamKind.video) ...[
        ('media.inspect.resolution'.tr(), '${s.width}×${s.height}${s.rotation != 0 ? '  (${s.rotation}°)' : ''}'),
        if (s.frameRate != null)
          ('media.inspect.fps'.tr(), s.frameRate!.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '')),
        if (s.pixelFormat != null) ('media.inspect.pixfmt'.tr(), s.pixelFormat!),
        if (s.colorTransfer != null) ('media.inspect.transfer'.tr(), s.colorTransfer!),
      ],
      if (s.kind == StreamKind.audio) ...[
        ('media.inspect.sample_rate'.tr(), '${s.sampleRate} Hz'),
        ('media.inspect.channels'.tr(), '${s.channels}${s.channelLayout != null ? ' (${s.channelLayout})' : ''}'),
      ],
      if (s.bitrate > 0) ('media.inspect.bitrate'.tr(), Fmt.bitrate(s.bitrate)),
      if (s.language != null) ('media.inspect.language'.tr(), s.language!),
      if (s.title != null) ('media.inspect.title'.tr(), s.title!),
    ];
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: c.textMuted),
              const SizedBox(width: 6),
              Text('#${s.index} · ${kindLabel.tr()}', style: TextStyles.heading.copyWith(color: c.text)),
              const Spacer(),
              if (s.isHdr) Tag('HDR', color: c.warning),
              if (s.isDefault) ...[const SizedBox(width: 4), Tag('media.inspect.default'.tr())],
            ],
          ),
          const SizedBox(height: Space.md),
          KeyValueList(entries: entries),
        ],
      ),
    );
  }
}
