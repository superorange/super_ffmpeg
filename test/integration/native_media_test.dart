// In-process FFmpeg bridge (FFI) against the bundled build. Skipped when
// vendor/ffmpeg has not been built (scripts/build_ffmpeg.sh).
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:super_ffmpeg/modules/media/engine/ffmpeg_locator.dart';
import 'package:super_ffmpeg/modules/media/engine/native_media.dart';
import 'package:super_ffmpeg/modules/media/engine/probe.dart';

void main() {
  final lib = NativeMedia.libraryPath;
  final bin = FfmpegLocator.locate(includeSystem: false);
  if (lib == null || bin == null) {
    test('bundled FFmpeg not built — native tests skipped', () {}, skip: true);
    return;
  }

  late Directory tmp;
  late String clip, rotated, cover, junk;

  Future<void> ff(List<String> args) async {
    final r = await Process.run(bin.ffmpeg, ['-v', 'error', '-y', ...args]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
  }

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('super_toolbox_native_');
    clip = p.join(tmp.path, "clip 'q' 中文.mp4");
    rotated = p.join(tmp.path, 'rotated.mp4');
    cover = p.join(tmp.path, 'song.mp3');
    junk = p.join(tmp.path, 'notes.mp4');
    await ff([
      '-f',
      'lavfi',
      '-i',
      'testsrc2=size=1280x720:rate=30:duration=4',
      '-f',
      'lavfi',
      '-i',
      'sine=duration=4',
      '-c:v',
      'libx264',
      '-g',
      '30',
      '-c:a',
      'aac',
      '-shortest',
      '-metadata',
      'title=Demo "quoted"',
      clip,
    ]);
    // Phone-style portrait: stored landscape + display matrix.
    await ff(['-display_rotation', '90', '-i', clip, '-c', 'copy', rotated]);
    final art = p.join(tmp.path, 'art.png');
    await ff(['-f', 'lavfi', '-i', 'color=c=red:size=300x300', '-frames:v', '1', art]);
    await ff([
      '-f',
      'lavfi',
      '-i',
      'sine=duration=2',
      '-i',
      art,
      '-map',
      '0',
      '-map',
      '1',
      '-c:a',
      'libmp3lame',
      '-c:v',
      'mjpeg',
      '-disposition:v',
      'attached_pic',
      cover,
    ]);
    File(junk).writeAsStringSync('definitely not a video');
  });

  tearDownAll(() => tmp.delete(recursive: true));

  test('links the bundled FFmpeg 9', () {
    expect(NativeMedia.version, startsWith('9.'));
    expect(bin.source, FfmpegSource.bundled);
  });

  test('in-process probe matches ffprobe', () async {
    final native = await NativeMedia.probe(clip);
    final process = await MediaProbe.probe(bin, clip);
    expect(native.duration.inMilliseconds, closeTo(process.duration.inMilliseconds, 5));
    expect(native.sizeBytes, process.sizeBytes);
    expect(native.video!.codec, process.video!.codec);
    expect([native.video!.width, native.video!.height], [1280, 720]);
    expect(native.video!.frameRate, closeTo(30, 0.01));
    expect(native.video!.pixelFormat, process.video!.pixelFormat);
    expect(native.audio!.codec, process.audio!.codec);
    expect(native.audio!.sampleRate, process.audio!.sampleRate);
    expect(native.audio!.channels, process.audio!.channels);
    expect(native.tags['title'], 'Demo "quoted"', reason: 'JSON escaping');
  });

  test('rotation is reported and applied to decoded frames', () async {
    final info = await NativeMedia.probe(rotated);
    expect(info.video!.isRotatedSideways, isTrue);
    expect([info.video!.displayWidth, info.video!.displayHeight], [720, 1280]);

    final frame = await NativeMedia.decodeFrame(rotated, maxWidth: 320, maxHeight: 320);
    expect(frame.height, 320);
    expect(frame.width, 180);
    expect(frame.rgba.length, 180 * 320 * 4);
  });

  test('decodes different frames at different times', () async {
    final a = await NativeMedia.decodeFrame(clip, maxWidth: 160);
    final b = await NativeMedia.decodeFrame(clip, at: const Duration(seconds: 3), maxWidth: 160);
    expect([a.width, a.height], [160, 90]);
    var diff = 0;
    for (var i = 0; i < a.rgba.length; i++) {
      if (a.rgba[i] != b.rgba[i]) diff++;
    }
    expect(diff, greaterThan(a.rgba.length ~/ 20), reason: 'testsrc2 animates');
  });

  test('audio files expose cover art as a frame', () async {
    final info = await NativeMedia.probe(cover);
    expect(info.hasVideo, isFalse);
    expect(info.hasCoverArt, isTrue);
    final frame = await NativeMedia.decodeFrame(cover, maxWidth: 100, maxHeight: 100);
    expect([frame.width, frame.height], [100, 100]);
    // Red cover art.
    expect(frame.rgba[0], greaterThan(200));
    expect(frame.rgba[1], lessThan(60));
  });

  test('unreadable files fail cleanly', () async {
    await expectLater(NativeMedia.probe(junk), throwsA(isA<ProbeException>()));
    await expectLater(NativeMedia.decodeFrame(junk), throwsA(isA<ProbeException>()));
    await expectLater(NativeMedia.probe('/nope/missing.mp4'), throwsA(isA<ProbeException>()));
  });

  test('in-process is much faster than spawning ffprobe/ffmpeg', () async {
    const n = 20;
    final sw = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      NativeMedia.probeSync(lib, clip);
    }
    final nativeProbe = sw.elapsedMicroseconds / n;
    sw.reset();
    for (var i = 0; i < n; i++) {
      await MediaProbe.probe(bin, clip);
    }
    final processProbe = sw.elapsedMicroseconds / n;
    sw.reset();
    for (var i = 0; i < n; i++) {
      NativeMedia.decodeFrameSync(lib, clip, at: const Duration(seconds: 2), maxWidth: 360);
    }
    final nativeFrame = sw.elapsedMicroseconds / n;

    // ignore: avoid_print
    print(
      'probe: in-process ${(nativeProbe / 1000).toStringAsFixed(2)} ms vs ffprobe '
      '${(processProbe / 1000).toStringAsFixed(2)} ms; frame decode ${(nativeFrame / 1000).toStringAsFixed(2)} ms',
    );
    expect(nativeProbe * 3, lessThan(processProbe));
  });
}
