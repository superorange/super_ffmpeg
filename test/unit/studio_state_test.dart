import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_ffmpeg/modules/media/builders/range.dart';
import 'package:super_ffmpeg/modules/media/engine/command_plan.dart';
import 'package:super_ffmpeg/modules/media/engine/media_info.dart';
import 'package:super_ffmpeg/modules/media/studio/studio_state.dart';
import 'package:super_ffmpeg/modules/media/tools/gif_page.dart' show gifSegment;

void main() {
  group('StudioNotifier', () {
    late ProviderContainer c;
    StudioNotifier n() => c.read(studioProvider.notifier);
    StudioState s() => c.read(studioProvider);

    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    test('adding activates the first new file and ignores duplicates', () {
      n().add(['/a.mp4', '/b.mp4']);
      expect(s().files, ['/a.mp4', '/b.mp4']);
      expect(s().active, '/a.mp4');
      n().add(['/b.mp4', '/c.mp4']);
      expect(s().files, ['/a.mp4', '/b.mp4', '/c.mp4']);
      expect(s().active, '/c.mp4');
      n().add(['/a.mp4']);
      expect(s().active, '/a.mp4', reason: 're-adding selects it');
    });

    test('playhead and range are per file', () {
      n().add(['/a.mp4', '/b.mp4']);
      n().setPlayhead(const Duration(seconds: 3));
      n().setRange(const Duration(seconds: 9), const Duration(seconds: 2));
      expect(s().range(), const ClipRange(Duration(seconds: 2), Duration(seconds: 9)), reason: 'normalized');
      n().select('/b.mp4');
      expect(s().playhead(), Duration.zero);
      expect(s().range(), isNull);
      expect(s().playhead('/a.mp4'), const Duration(seconds: 3));
    });

    test('mark in / out keep the other edge when valid', () {
      const total = Duration(seconds: 60);
      n().add(['/a.mp4']);
      n().setPlayhead(const Duration(seconds: 10));
      n().markIn(total);
      expect(s().range(), const ClipRange(Duration(seconds: 10), total));
      n().setPlayhead(const Duration(seconds: 25));
      n().markOut(total);
      expect(s().range(), const ClipRange(Duration(seconds: 10), Duration(seconds: 25)));
      n().setPlayhead(const Duration(seconds: 5));
      n().markOut(total);
      expect(s().range(), const ClipRange(Duration.zero, Duration(seconds: 5)), reason: 'in after out resets in');
    });

    test('removing the active file activates its neighbour and drops state', () {
      n().add(['/a.mp4', '/b.mp4', '/c.mp4']);
      n().select('/b.mp4');
      n().setRange(Duration.zero, const Duration(seconds: 1));
      n().setBatch(true);
      n().remove('/b.mp4');
      expect(s().active, '/c.mp4');
      expect(s().ranges, isEmpty);
      n().remove('/c.mp4');
      expect(s().batch, isFalse, reason: 'batch needs 2+ files');
      n().move(0, 0);
      n().remove('/a.mp4');
      expect(s().active, isNull);
    });

    test('isPartialOf', () {
      const total = Duration(seconds: 10);
      expect(const ClipRange(Duration.zero, total).isPartialOf(total), isFalse);
      expect(const ClipRange(Duration(seconds: 1), total).isPartialOf(total), isTrue);
      expect(const ClipRange(Duration.zero, Duration(seconds: 9)).isPartialOf(total), isTrue);
    });
  });

  group('applyClipRange', () {
    test('inserts input seeking before the matching -i in every step', () {
      const plan = CommandPlan(
        steps: [
          FfmpegStep(['-y', '-i', '/in.mp4', '-pass', '1', '-f', 'null', '-']),
          FfmpegStep(['-i', '/other.mp4', '-i', '/in.mp4', '-n', '/out.mp4']),
        ],
        outputs: ['/out.mp4'],
        expectedDuration: Duration(seconds: 60),
      );
      final clipped = applyClipRange(
        plan,
        input: '/in.mp4',
        start: const Duration(milliseconds: 1500),
        length: const Duration(seconds: 4),
      );
      expect(clipped.steps[0].args, ['-y', '-ss', '1.5', '-t', '4', '-i', '/in.mp4', '-pass', '1', '-f', 'null', '-']);
      expect(clipped.steps[1].args, ['-i', '/other.mp4', '-ss', '1.5', '-t', '4', '-i', '/in.mp4', '-n', '/out.mp4']);
      expect(clipped.expectedDuration, const Duration(seconds: 4));
      expect(clipped.outputs, plan.outputs);
    });

    test('rejects empty ranges', () {
      const plan = CommandPlan(steps: [], outputs: []);
      expect(
        () => applyClipRange(plan, input: 'x', start: Duration.zero, length: Duration.zero),
        throwsA(isA<PlanException>()),
      );
    });

    test('clipped info scales size with duration', () {
      const info = MediaInfo(path: '/a', duration: Duration(seconds: 100), sizeBytes: 1000);
      final c = info.clipped(const Duration(seconds: 25));
      expect(c.duration, const Duration(seconds: 25));
      expect(c.sizeBytes, 250);
    });
  });

  test('GIF segment defaults to 5 s from the playhead, clamped to the end', () {
    const info = MediaInfo(path: '/a', duration: Duration(seconds: 12));
    expect(
      gifSegment(info, null, const Duration(seconds: 2)),
      const ClipRange(Duration(seconds: 2), Duration(seconds: 7)),
    );
    expect(
      gifSegment(info, null, const Duration(seconds: 10)),
      const ClipRange(Duration(seconds: 7), Duration(seconds: 12)),
    );
    const sel = ClipRange(Duration(seconds: 1), Duration(seconds: 3));
    expect(gifSegment(info, sel, Duration.zero), sel);
  });
}
