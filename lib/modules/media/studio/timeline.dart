import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/format.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../engine/media_info.dart';
import '../providers.dart';
import 'studio_state.dart';

/// Filmstrip track with playhead and in/out handles, shared by every tab.
///
/// Click or drag on the track to scrub; drag the edge handles to select a
/// segment; `I` / `O` set in/out at the playhead.
class StudioTimeline extends ConsumerStatefulWidget {
  const StudioTimeline({super.key, required this.info});
  final MediaInfo info;

  static const trackHeight = 54.0;
  static const filmstripFrames = 16;

  @override
  ConsumerState<StudioTimeline> createState() => _StudioTimelineState();
}

enum _Drag { playhead, start, end }

class _StudioTimelineState extends ConsumerState<StudioTimeline> {
  _Drag? _drag;

  Duration get _total => widget.info.duration;

  Duration _at(double x, double width) {
    final f = (x / width).clamp(0.0, 1.0);
    return Duration(milliseconds: (_total.inMilliseconds * f).round());
  }

  void _update(double x, double width) {
    final n = ref.read(studioProvider.notifier);
    final s = ref.read(studioProvider);
    final at = _at(x, width);
    final range = s.range() ?? ClipRange(Duration.zero, _total);
    const minLen = Duration(milliseconds: 100);
    switch (_drag) {
      case _Drag.start:
        final start = at > range.end - minLen ? range.end - minLen : at;
        n.setRange(start, range.end);
        n.setPlayhead(start);
      case _Drag.end:
        final end = at < range.start + minLen ? range.start + minLen : at;
        n.setRange(range.start, end);
        n.setPlayhead(end);
      case _Drag.playhead || null:
        n.setPlayhead(at);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final info = widget.info;
    final studio = ref.watch(studioProvider);
    final notifier = ref.read(studioProvider.notifier);
    final playhead = studio.playhead(info.path);
    final selection = studio.range(info.path);
    final range = selection ?? ClipRange(Duration.zero, _total);
    final partial = selection != null && selection.isPartialOf(_total);
    final totalMs = _total.inMilliseconds;
    final frames = ref.watch(
      filmstripProvider((path: info.path, count: StudioTimeline.filmstripFrames)),
    );

    if (totalMs <= 0) {
      return const SizedBox(height: StudioTimeline.trackHeight);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            double x(Duration d) => (d.inMilliseconds / totalMs).clamp(0.0, 1.0) * w;
            final startX = x(range.start);
            final endX = x(range.end);
            final headX = x(playhead);

            Widget handle(_Drag which, double left, bool isStart) => Positioned(
              left: left - (isStart ? 0 : 12),
              top: 0,
              bottom: 0,
              width: 12,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) => setState(() => _drag = which),
                  onHorizontalDragUpdate: (d) => _update(left + d.localPosition.dx - (isStart ? 0 : 12), w),
                  onHorizontalDragEnd: (_) => setState(() => _drag = null),
                  child: Container(
                    decoration: BoxDecoration(
                      color: partial || _drag == which ? c.warning : Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(isStart ? 7 : 0),
                        right: Radius.circular(isStart ? 0 : 7),
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 2,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );

            return SizedBox(
              height: StudioTimeline.trackHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) {
                  _drag = _Drag.playhead;
                  _update(d.localPosition.dx, w);
                },
                onHorizontalDragStart: (d) {
                  _drag = _Drag.playhead;
                  _update(d.localPosition.dx, w);
                },
                onHorizontalDragUpdate: (d) => _update(d.localPosition.dx, w),
                onHorizontalDragEnd: (_) => _drag = null,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Filmstrip.
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          color: c.stage,
                          child: _Filmstrip(frames: frames.value ?? const []),
                        ),
                      ),
                    ),
                    // Dim outside the selection.
                    if (startX > 0)
                      Positioned(
                        left: 0,
                        width: startX,
                        top: 0,
                        bottom: 0,
                        child: _Dim(left: true),
                      ),
                    if (endX < w)
                      Positioned(
                        left: endX,
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: _Dim(left: false),
                      ),
                    // Selection frame.
                    Positioned(
                      left: startX,
                      width: (endX - startX).clamp(0, w),
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.symmetric(
                              horizontal: BorderSide(
                                color: partial ? c.warning : Colors.white.withValues(alpha: 0.85),
                                width: 2.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    handle(_Drag.start, startX, true),
                    handle(_Drag.end, endX, false),
                    // Playhead.
                    Positioned(
                      left: headX - 1,
                      top: -5,
                      bottom: -5,
                      child: IgnorePointer(
                        child: Column(
                          children: [
                            Container(
                              width: 2,
                              height: 5,
                              color: Colors.transparent,
                            ),
                            Expanded(
                              child: Container(
                                width: 2,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 3)],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: headX - 6,
                      top: -7,
                      child: IgnorePointer(
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.accent, width: 2.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: Space.lg,
                runSpacing: 4,
                children: [
                  _TimeLabel(label: 'studio.in'.tr(), value: range.start, active: partial),
                  _TimeLabel(label: 'studio.out'.tr(), value: range.end, active: partial),
                  _TimeLabel(label: 'studio.length'.tr(), value: range.length, active: partial, strong: true),
                ],
              ),
            ),
            AppButton.ghost(
              label: 'studio.mark_in'.tr(),
              icon: Icons.first_page_rounded,
              size: ButtonSize.sm,
              onPressed: () => notifier.markIn(_total),
            ),
            AppButton.ghost(
              label: 'studio.mark_out'.tr(),
              icon: Icons.last_page_rounded,
              size: ButtonSize.sm,
              onPressed: () => notifier.markOut(_total),
            ),
            AppButton.ghost(
              label: 'studio.clear_range'.tr(),
              icon: Icons.select_all_rounded,
              size: ButtonSize.sm,
              onPressed: partial ? notifier.clearRange : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _Filmstrip extends StatelessWidget {
  const _Filmstrip({required this.frames});
  final List<ui.Image> frames;

  @override
  Widget build(BuildContext context) {
    if (frames.isEmpty) {
      return CustomPaint(painter: _TrackPattern(color: Colors.white.withValues(alpha: 0.05)));
    }
    return Row(
      children: [
        for (final f in frames)
          Expanded(
            child: RawImage(image: f, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
          ),
      ],
    );
  }
}

class _TrackPattern extends CustomPainter {
  _TrackPattern({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += 6) {
      final h = size.height * (0.25 + 0.5 * ((x * 7919) % 97) / 97);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, (size.height - h) / 2, 3, h), const Radius.circular(1.5)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TrackPattern old) => old.color != color;
}

class _Dim extends StatelessWidget {
  const _Dim({required this.left});
  final bool left;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(left ? 8 : 0),
            right: Radius.circular(left ? 0 : 8),
          ),
        ),
      ),
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.label, required this.value, this.active = false, this.strong = false});
  final String label;
  final Duration value;
  final bool active;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyles.caption.copyWith(color: c.textSubtle)),
        const SizedBox(width: 6),
        Text(
          Fmt.timecode(value),
          style: TextStyles.mono.copyWith(
            fontSize: 12,
            color: active ? (strong ? c.warning : c.text) : c.textMuted,
            fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
