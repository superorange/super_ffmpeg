import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/format.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/feedback.dart';
import '../engine/media_info.dart';
import '../providers.dart';

/// One selected input: thumbnail, name and key facts.
class MediaFileTile extends ConsumerWidget {
  const MediaFileTile({
    super.key,
    required this.path,
    this.onRemove,
    this.index,
    this.dragHandle,
  });

  final String path;
  final VoidCallback? onRemove;
  final int? index;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final info = ref.watch(probeProvider(path));

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: info.hasError ? c.danger.withValues(alpha: 0.5) : c.border),
      ),
      child: Row(
        children: [
          ?dragHandle,
          if (index != null)
            SizedBox(
              width: 22,
              child: Text(
                '${index! + 1}',
                style: TextStyles.label.copyWith(color: c.textSubtle),
                textAlign: TextAlign.center,
              ),
            ),
          MediaThumbnail(path: path, width: 112, height: 63),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.basename(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.body.copyWith(color: c.text, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                switch (info) {
                  AsyncData(:final value) => MediaFacts(info: value),
                  AsyncError(:final error) => Text(
                    '${'media.unreadable'.tr()} · $error',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.caption.copyWith(color: c.danger),
                  ),
                  _ => Text('media.probing'.tr(), style: TextStyles.caption.copyWith(color: c.textSubtle)),
                },
              ],
            ),
          ),
          if (onRemove != null)
            AppIconButton(icon: Icons.close_rounded, tooltip: 'common.remove'.tr(), onPressed: onRemove),
        ],
      ),
    );
  }
}

class MediaFacts extends StatelessWidget {
  const MediaFacts({super.key, required this.info});
  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = info.video;
    final a = info.audio;
    return Wrap(
      spacing: 5,
      runSpacing: 4,
      children: [
        if (info.duration > Duration.zero) Tag(Fmt.duration(info.duration), icon: Icons.schedule_rounded),
        if (v != null) Tag('${v.displayWidth}×${v.displayHeight}'),
        if (v != null) Tag(v.codec.toUpperCase()),
        if (v?.frameRate != null) Tag('${v!.frameRate!.toStringAsFixed(v.frameRate! % 1 == 0 ? 0 : 2)} fps'),
        if (v?.isHdr ?? false) Tag('HDR', color: c.warning),
        if (a != null)
          Tag(
            '${a.codec.toUpperCase()} ${a.channels == 1
                ? 'mono'
                : a.channels == 2
                ? 'stereo'
                : '${a.channels}ch'}',
          ),
        if (info.sizeBytes > 0) Tag(Fmt.bytes(info.sizeBytes)),
      ],
    );
  }
}

class MediaThumbnail extends ConsumerStatefulWidget {
  const MediaThumbnail({
    super.key,
    required this.path,
    this.width = 112,
    this.height = 63,
    this.atMs,
    this.fit,
    this.background,
    this.radius,
  });
  final String path;
  final double width;
  final double height;
  final Color? background;
  final double? radius;

  /// Specific frame; null = representative thumbnail.
  final int? atMs;
  final BoxFit? fit;

  @override
  ConsumerState<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends ConsumerState<MediaThumbnail> {
  /// Our own handle on the last frame, so the previous frame stays visible
  /// while the next one decodes (providers dispose theirs independently).
  ui.Image? _shown;
  ui.Image? _source;
  String? _shownPath;

  void _show(ui.Image? image) {
    if (image == null || identical(image, _source)) return;
    _shown?.dispose();
    _shown = image.clone();
    _source = image;
    _shownPath = widget.path;
  }

  @override
  void dispose() {
    _shown?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final thumb = widget.atMs == null
        ? ref.watch(thumbnailProvider(widget.path))
        : ref.watch(framePreviewProvider((path: widget.path, ms: widget.atMs!)));
    _show(thumb.value);
    final info = ref.watch(probeProvider(widget.path)).value;
    final isAudio = info != null && !info.hasVideo && !info.hasCoverArt;
    final image = _shownPath == widget.path ? _shown : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius ?? Radii.control),
      child: Container(
        width: widget.width,
        height: widget.height,
        color: widget.background ?? c.stage,
        child: image != null
            ? RawImage(image: image, fit: widget.fit ?? BoxFit.cover, filterQuality: FilterQuality.medium)
            : Center(
                child: thumb.isLoading
                    ? SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: c.textSubtle),
                      )
                    : Icon(
                        isAudio ? Icons.graphic_eq_rounded : Icons.movie_outlined,
                        size: widget.height * 0.38,
                        color: c.textSubtle,
                      ),
              ),
      ),
    );
  }
}
