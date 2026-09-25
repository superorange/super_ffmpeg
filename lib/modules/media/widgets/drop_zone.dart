import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../ui/theme/tokens.dart';

enum MediaAccept {
  video,
  audio,
  media,
  any;

  static const videoExts = {
    'mp4',
    'mov',
    'mkv',
    'avi',
    'webm',
    'm4v',
    'flv',
    'wmv',
    'ts',
    'mts',
    'm2ts',
    '3gp',
    'mpg',
    'mpeg',
    'ogv',
    'vob',
    'gif',
    'hevc',
    'mxf',
  };
  static const audioExts = {
    'mp3',
    'm4a',
    'aac',
    'wav',
    'flac',
    'ogg',
    'opus',
    'wma',
    'aiff',
    'aif',
    'alac',
    'ac3',
    'eac3',
    'dts',
    'amr',
    'mka',
    'caf',
  };

  Set<String>? get extensions => switch (this) {
    video => videoExts,
    audio => audioExts,
    media => {...videoExts, ...audioExts},
    any => null,
  };

  bool accepts(String path) {
    final exts = extensions;
    if (exts == null) return true;
    return exts.contains(p.extension(path).replaceFirst('.', '').toLowerCase());
  }

  String get hintKey => 'media.accept.$name';

  Future<List<String>> pick({required bool multiple}) async {
    final exts = extensions;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: multiple,
      type: exts == null ? FileType.any : FileType.custom,
      allowedExtensions: exts?.toList(),
    );
    return [for (final f in result?.files ?? const <PlatformFile>[]) ?f.path];
  }
}

/// Large empty-state drop target.
class DropZone extends StatefulWidget {
  const DropZone({
    super.key,
    required this.accept,
    required this.dragging,
    required this.onPick,
    required this.multiple,
  });

  final MediaAccept accept;
  final bool dragging;
  final bool multiple;
  final VoidCallback onPick;

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = widget.dragging || _hover;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPick,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 280,
          decoration: BoxDecoration(
            color: widget.dragging ? c.accentSoft : (_hover ? c.surfaceAlt : c.surface),
            borderRadius: BorderRadius.circular(Radii.panel),
          ),
          child: CustomPaint(
            painter: _DashedBorder(color: active ? c.accent : c.borderStrong, radius: Radii.panel),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: active ? c.accent : c.surfaceAlt,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: active ? c.accent : c.border),
                    ),
                    child: Icon(
                      widget.dragging ? Icons.file_download_rounded : Icons.add_rounded,
                      size: 26,
                      color: active ? c.onAccent : c.textMuted,
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  Text(
                    widget.dragging
                        ? 'media.drop.release'.tr()
                        : (widget.multiple ? 'media.drop.title_multi' : 'media.drop.title').tr(),
                    style: TextStyles.heading.copyWith(color: c.text),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'media.drop.or'.tr()),
                        TextSpan(
                          text: 'media.drop.browse'.tr(),
                          style: TextStyle(color: c.accent, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    style: TextStyles.body.copyWith(color: c.textMuted),
                  ),
                  const SizedBox(height: Space.md),
                  Text(widget.accept.hintKey.tr(), style: TextStyles.caption.copyWith(color: c.textSubtle)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.7),
      );
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
