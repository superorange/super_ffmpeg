import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/format.dart';
import '../../../ui/theme/tokens.dart';
import '../engine/media_info.dart';
import '../widgets/media_file_tile.dart';
import 'studio_state.dart';

/// Large preview of the active file at the playhead. Frames decode
/// in-process; updates are throttled so scrubbing stays smooth.
class StudioStage extends ConsumerStatefulWidget {
  const StudioStage({super.key, required this.info, this.showPreview = false});
  final MediaInfo info;

  /// Apply the active tool's [StagePreview] (transform tab only).
  final bool showPreview;

  @override
  ConsumerState<StudioStage> createState() => _StudioStageState();
}

class _StudioStageState extends ConsumerState<StudioStage> {
  int? _shownMs;
  Timer? _throttle;
  int? _pendingMs;

  void _request(int ms) {
    if (_shownMs == null) {
      _shownMs = ms;
      return;
    }
    if (ms == _shownMs) return;
    _pendingMs = ms;
    _throttle ??= Timer(const Duration(milliseconds: 70), () {
      _throttle = null;
      if (mounted && _pendingMs != null) setState(() => _shownMs = _pendingMs);
    });
  }

  @override
  void didUpdateWidget(StudioStage old) {
    super.didUpdateWidget(old);
    if (old.info.path != widget.info.path) _shownMs = null;
  }

  @override
  void dispose() {
    _throttle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final info = widget.info;
    final playhead = ref.watch(studioProvider.select((s) => s.playhead(info.path)));
    final preview = widget.showPreview ? ref.watch(stagePreviewProvider) : StagePreview.none;
    final totalMs = info.duration.inMilliseconds;
    // Seeking exactly to the end yields no frame; stay just before it.
    final int ms = totalMs <= 0 ? 0 : playhead.inMilliseconds.clamp(0, math.max(0, totalMs - 50)).toInt();
    _request(ms);
    final visual = info.hasVideo || info.hasCoverArt;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.stage,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.isDark ? c.border : Colors.transparent),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (visual)
            LayoutBuilder(
              builder: (context, box) {
                Widget frame = MediaThumbnail(
                  path: info.path,
                  width: box.maxWidth,
                  height: box.maxHeight,
                  atMs: info.hasVideo ? (_shownMs ?? ms) : null,
                  fit: BoxFit.contain,
                  background: c.stage,
                  radius: 0,
                );
                if (preview.quarterTurns != 0 || preview.flipH || preview.flipV) {
                  frame = Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.diagonal3Values(preview.flipH ? -1 : 1, preview.flipV ? -1 : 1, 1),
                    child: RotatedBox(quarterTurns: preview.quarterTurns, child: frame),
                  );
                }
                return frame;
              },
            )
          else
            _AudioArt(info: info),
          if (preview.aspect != null) _AspectGuide(aspect: preview.aspect!),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 28, 14, 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xB3000000)],
                ),
              ),
              child: Row(
                children: [
                  Text(
                    Fmt.timecode(playhead),
                    style: TextStyles.mono.copyWith(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '  /  ${Fmt.timecode(info.duration)}',
                    style: TextStyles.mono.copyWith(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                  ),
                  const Spacer(),
                  if (info.video case final v?) ...[
                    _StageBadge('${v.displayWidth}×${v.displayHeight}'),
                    if (v.frameRate != null) _StageBadge('${_fps(v.frameRate!)} fps'),
                    if (v.isHdr) const _StageBadge('HDR', color: Color(0xFFFBBF24)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fps(double f) => f.toStringAsFixed(f % 1 == 0 ? 0 : 2);
}

class _StageBadge extends StatelessWidget {
  const _StageBadge(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyles.caption.copyWith(color: color ?? Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Dims everything outside the target output frame (e.g. 9:16 reframing).
class _AspectGuide extends StatelessWidget {
  const _AspectGuide({required this.aspect});
  final double aspect;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: AspectRatio(
          aspectRatio: aspect,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), spreadRadius: 2000)],
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioArt extends StatelessWidget {
  const _AudioArt({required this.info});
  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final a = info.audio;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 64,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Decorative equaliser bars.
                for (var i = 0; i < 28; i++)
                  Container(
                    width: 4,
                    height: 12 + 48 * (0.5 + 0.5 * math.sin(i * 0.9) * math.cos(i * 0.37)).abs(),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: const LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xFFF43F5E), Color(0xFFFB923C)],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.lg),
          Text(
            p.basename(info.path),
            style: TextStyles.heading.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            a == null ? 'studio.audio_only'.tr() : '${a.codec.toUpperCase()} · ${a.sampleRate} Hz · ${a.channels} ch',
            style: TextStyles.caption.copyWith(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
