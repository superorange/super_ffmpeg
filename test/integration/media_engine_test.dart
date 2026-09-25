// Runs every builder against the local ffmpeg. Skipped when ffmpeg is absent.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:super_ffmpeg/core/jobs/job.dart';
import 'package:super_ffmpeg/modules/media/builders/audio.dart';
import 'package:super_ffmpeg/modules/media/builders/codecs.dart';
import 'package:super_ffmpeg/modules/media/builders/compress.dart';
import 'package:super_ffmpeg/modules/media/builders/concat.dart';
import 'package:super_ffmpeg/modules/media/builders/convert.dart';
import 'package:super_ffmpeg/modules/media/builders/frames.dart';
import 'package:super_ffmpeg/modules/media/builders/range.dart';
import 'package:super_ffmpeg/modules/image/logic/image_convert.dart';
import 'package:super_ffmpeg/modules/media/builders/gif.dart';
import 'package:super_ffmpeg/modules/media/builders/transform.dart';
import 'package:super_ffmpeg/modules/media/builders/trim.dart';
import 'package:super_ffmpeg/modules/media/engine/capabilities.dart';
import 'package:super_ffmpeg/modules/media/engine/command_plan.dart';
import 'package:super_ffmpeg/modules/media/engine/ffmpeg_locator.dart';
import 'package:super_ffmpeg/modules/media/engine/media_info.dart';
import 'package:super_ffmpeg/modules/media/engine/media_job.dart';
import 'package:super_ffmpeg/modules/media/engine/probe.dart';

void main() {
  final bin = FfmpegLocator.locate();
  if (bin == null) {
    test('ffmpeg not installed — integration tests skipped', () {}, skip: true);
    return;
  }

  late Directory tmp;
  late FfmpegCapabilities caps;
  late String clip; // 1280x720, 30fps, 6s, with stereo audio
  late String portrait; // 360x640, 3s, no audio
  late MediaInfo clipInfo;

  // A name exercising shell-hostile characters.
  const hostile = "clip 'quoted' \$HOME \"x\" 中文";

  Future<List<double>> run(CommandPlan plan) async {
    final progress = <double>[];
    final logs = <String>[];
    final ctx = JobContext(
      log: logs.add,
      onProgress: (p) {
        if (p.fraction != null) progress.add(p.fraction!);
      },
    );
    final job = MediaJobSpec(title: 't', toolId: 't', inputs: const [], plan: plan, ffmpeg: bin.ffmpeg);
    try {
      await job.run(ctx);
    } on JobFailure catch (e) {
      fail('ffmpeg failed: ${e.message}\n${plan.commandLine()}\n${logs.join('\n')}');
    }
    return progress;
  }

  Future<MediaInfo> probe(String path) => MediaProbe.probe(bin, path);

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('super_toolbox_it_');
    caps = await FfmpegCapabilities.detect(bin);
    clip = p.join(tmp.path, '$hostile.mp4');
    portrait = p.join(tmp.path, 'portrait.mp4');
    final a = await Process.run(bin.ffmpeg, [
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'testsrc2=size=1280x720:rate=30:duration=6',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:sample_rate=44100:duration=6',
      '-ac',
      '2',
      '-c:v',
      'libx264',
      '-g',
      '30',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-shortest',
      clip,
    ]);
    expect(a.exitCode, 0, reason: '${a.stderr}');
    final b = await Process.run(bin.ffmpeg, [
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'testsrc=size=360x640:rate=25:duration=3',
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      portrait,
    ]);
    expect(b.exitCode, 0, reason: '${b.stderr}');
    clipInfo = await probe(clip);
  });

  tearDownAll(() => tmp.delete(recursive: true));

  String out(String name) => p.join(tmp.path, name);

  test('capabilities are detected', () {
    expect(caps.version, isNot('unknown'));
    expect(caps.encoders, containsAll(['libx264', 'aac']));
  });

  test('probe reads streams from a shell-hostile path', () {
    expect(clipInfo.video!.width, 1280);
    expect(clipInfo.video!.height, 720);
    expect(clipInfo.video!.frameRate, closeTo(30, 0.01));
    expect(clipInfo.audio!.channels, 2);
    expect(clipInfo.duration.inMilliseconds, closeTo(6000, 100));
  });

  test('thumbnail is extracted', () async {
    final thumb = await MediaProbe.thumbnail(bin, clipInfo);
    expect(thumb, isNotNull);
    expect(File(thumb!).lengthSync(), greaterThan(1000));
  });

  test('convert: 720p HEVC MKV with monotonically increasing progress', () async {
    final o = out('convert.mkv');
    final progress = await run(
      buildConvert(
        input: clip,
        output: o,
        encoders: caps.encoders,
        info: clipInfo,
        options: const ConvertOptions(
          container: MediaContainer.mkv,
          codec: VideoCodec.hevc,
          resolution: Resolution.p480,
          frameRate: FrameRateOption.fps24,
          quality: QualityLevel.small,
          speed: EncodeSpeed.fast,
        ),
      ),
    );
    final info = await probe(o);
    expect(info.video!.codec, 'hevc');
    expect(info.video!.height, 480);
    expect(info.video!.frameRate, closeTo(24, 0.01));
    expect(progress, isNotEmpty);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
  });

  test('compress: target size is never exceeded', () async {
    // Grainy source so the budget actually binds.
    final noisy = out('noisy.mp4');
    await Process.run(bin.ffmpeg, [
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'testsrc2=size=1280x720:rate=30:duration=8,noise=alls=20:allf=t',
      '-f',
      'lavfi',
      '-i',
      'anoisesrc=duration=8',
      '-c:v',
      'libx264',
      '-crf',
      '14',
      '-c:a',
      'aac',
      '-shortest',
      noisy,
    ]);
    final info = await probe(noisy);
    final o = out('compressed.mp4');
    await run(
      buildCompress(
        input: noisy,
        output: o,
        encoders: caps.encoders,
        info: info,
        passLogPrefix: p.join(tmp.path, 'pass'),
        options: const CompressOptions(mode: CompressMode.targetSize, targetMb: 1),
      ),
    );
    expect(File(o).lengthSync(), lessThanOrEqualTo(1024 * 1024));
    expect(
      tmp.listSync().where((f) => p.basename(f.path).startsWith('pass')),
      isEmpty,
      reason: 'two-pass logs are cleaned up',
    );
  });

  test('compress: incompressible content fails instead of overshooting', () async {
    final noise = out('pure_noise.mp4');
    await Process.run(bin.ffmpeg, [
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'nullsrc=size=640x360:rate=30:duration=4,geq=random(1)*255:128:128',
      '-c:v',
      'libx264',
      '-crf',
      '0',
      noise,
    ]);
    final info = await probe(noise);
    final o = out('noise_small.mp4');
    final plan = buildCompress(
      input: noise,
      output: o,
      encoders: caps.encoders,
      info: info,
      passLogPrefix: p.join(tmp.path, 'npass'),
      options: const CompressOptions(mode: CompressMode.targetSize, targetMb: 0.1),
    );
    final job = MediaJobSpec(title: 't', toolId: 't', inputs: const [], plan: plan, ffmpeg: bin.ffmpeg);
    try {
      await job.run(JobContext(log: (_) {}, onProgress: (_) {}));
      expect(File(o).lengthSync(), lessThanOrEqualTo(plan.maxOutputBytes!));
    } on JobFailure catch (e) {
      expect(e.key, 'media.errors.size_exceeded');
      expect(File(o).existsSync(), isFalse);
    }
  });

  test('compress: quality mode shrinks the file', () async {
    final o = out('compressed_q.mp4');
    await run(
      buildCompress(
        input: clip,
        output: o,
        encoders: caps.encoders,
        info: clipInfo,
        options: const CompressOptions(level: CompressLevel.strong, resolution: Resolution.p480),
      ),
    );
    expect((await probe(o)).video!.height, 480);
  });

  test('trim: fast and precise produce the requested length', () async {
    for (final precise in [false, true]) {
      final o = out('trim_$precise.mp4');
      await run(
        buildTrim(
          input: clip,
          output: o,
          info: clipInfo,
          options: TrimOptions(
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 4),
            precise: precise,
          ),
        ),
      );
      expect((await probe(o)).duration.inMilliseconds, closeTo(3000, precise ? 100 : 1100));
    }
  });

  test('audio: normalized MP3 keeps a sane sample rate; original copies codec', () async {
    final mp3 = out('audio.mp3');
    await run(
      buildAudio(
        input: clip,
        output: mp3,
        info: clipInfo,
        options: const AudioOptions(format: AudioFormat.mp3, normalize: true, gainDb: 3),
      ),
    );
    final mp3Info = await probe(mp3);
    expect(mp3Info.audio!.codec, 'mp3');
    expect(mp3Info.audio!.sampleRate, 44100);
    expect(mp3Info.hasVideo, isFalse);

    final copy = out('audio.${audioExtension(const AudioOptions(format: AudioFormat.original), clipInfo)}');
    await run(
      buildAudio(
        input: clip,
        output: copy,
        info: clipInfo,
        options: const AudioOptions(format: AudioFormat.original),
      ),
    );
    expect(p.extension(copy), '.m4a');
    expect((await probe(copy)).audio!.codec, 'aac');
  });

  test('gif: palette GIF at requested width', () async {
    final o = out('anim.gif');
    await run(
      buildGif(
        input: clip,
        output: o,
        info: clipInfo,
        options: const GifOptions(start: Duration(seconds: 1), duration: Duration(seconds: 2), width: 320),
      ),
    );
    final info = await probe(o);
    expect(info.video!.codec, 'gif');
    expect(info.video!.width, 320);
  });

  test('transform: 2x speed + 9:16 blurred framing', () async {
    final o = out('vertical.mp4');
    await run(
      buildTransform(
        input: clip,
        output: o,
        encoders: caps.encoders,
        info: clipInfo,
        options: const TransformOptions(speed: 2, framing: Framing.vertical916, preferGpu: false),
      ),
    );
    final info = await probe(o);
    expect(info.video!.width, 1080);
    expect(info.video!.height, 1920);
    expect(info.duration.inMilliseconds, closeTo(3000, 150));
    expect(info.hasAudio, isTrue);
  });

  test('transform: rotate 90° swaps dimensions', () async {
    final o = out('rotated.mp4');
    await run(
      buildTransform(
        input: portrait,
        output: o,
        encoders: caps.encoders,
        info: await probe(portrait),
        options: const TransformOptions(rotation: Rotation.cw90, preferGpu: false),
      ),
    );
    final info = await probe(o);
    expect([info.video!.width, info.video!.height], [640, 360]);
  });

  test('concat: compatible mode joins different sizes, fills missing audio', () async {
    final o = out('joined.mp4');
    final infos = [clipInfo, await probe(portrait)];
    await run(
      buildConcat(
        inputs: [clip, portrait],
        output: o,
        encoders: caps.encoders,
        infos: infos,
        listPath: out('list.txt'),
        options: const ConcatOptions(preferGpu: false),
      ),
    );
    final info = await probe(o);
    expect(info.video!.width, 1280);
    expect(info.hasAudio, isTrue);
    expect(info.duration.inMilliseconds, closeTo(9000, 200));
  });

  test('concat: fast mode stream-copies identical clips', () async {
    final o = out('joined_fast.mp4');
    final listPath = out('fast_list.txt');
    await run(
      buildConcat(
        inputs: [clip, clip],
        output: o,
        encoders: caps.encoders,
        infos: [clipInfo, clipInfo],
        listPath: listPath,
        options: const ConcatOptions(mode: ConcatMode.fast),
      ),
    );
    expect((await probe(o)).duration.inMilliseconds, closeTo(12000, 200));
    expect(File(listPath).existsSync(), isFalse, reason: 'aux list removed');
  });

  test('frames: single, interval folder, contact sheet', () async {
    final single = out('frame.jpg');
    await run(buildFrames(input: clip, output: single, info: clipInfo, options: const FramesOptions()));
    expect(File(single).existsSync(), isTrue);

    final folder = out('frames');
    await run(
      buildFrames(
        input: clip,
        output: folder,
        info: clipInfo,
        options: const FramesOptions(mode: FramesMode.interval, everySeconds: 2, format: ImageFormat.png),
      ),
    );
    expect(Directory(folder).listSync().length, inInclusiveRange(3, 4));

    final sheet = out('sheet.jpg');
    await run(
      buildFrames(
        input: clip,
        output: sheet,
        info: clipInfo,
        options: const FramesOptions(mode: FramesMode.contactSheet, columns: 3, rows: 2, width: 200),
      ),
    );
    final info = await probe(sheet);
    expect(info.video!.width, 3 * 200 + 6 * 4);
  });

  test('cancel terminates ffmpeg and removes the partial output', () async {
    final o = out('cancelled.mkv');
    final plan = buildConvert(
      input: clip,
      output: o,
      encoders: caps.encoders,
      info: clipInfo,
      options: const ConvertOptions(
        container: MediaContainer.mkv,
        codec: VideoCodec.hevc,
        speed: EncodeSpeed.slow,
        preferGpu: false,
      ),
    );
    final ctx = JobContext(log: (_) {}, onProgress: (_) {});
    final job = MediaJobSpec(title: 't', toolId: 't', inputs: const [], plan: plan, ffmpeg: bin.ffmpeg);
    final running = job.run(ctx);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final sw = Stopwatch()..start();
    ctx.cancel();
    await expectLater(running, throwsA(isA<JobCancelled>()));
    expect(sw.elapsed, lessThan(const Duration(seconds: 4)));
    expect(File(o).existsSync(), isFalse);
  });

  test('failures surface ffmpeg\'s error line', () async {
    final plan = CommandPlan.single(['-i', out('missing.mp4'), '-n', out('x.mp4')], output: out('x.mp4'));
    final job = MediaJobSpec(title: 't', toolId: 't', inputs: const [], plan: plan, ffmpeg: bin.ffmpeg);
    await expectLater(
      job.run(JobContext(log: (_) {}, onProgress: (_) {})),
      throwsA(isA<JobFailure>().having((e) => e.message, 'message', contains('No such file'))),
    );
  });

  group('timeline selection (studio "selection only")', () {
    const start = Duration(seconds: 1);
    const length = Duration(milliseconds: 2500);

    test('convert of a selection lasts exactly the selection', () async {
      final path = out('range_convert.mp4');
      final plan = applyClipRange(
        buildConvert(
          input: clip,
          output: path,
          options: const ConvertOptions(preferGpu: false),
          encoders: caps.encoders,
          info: clipInfo.clipped(length),
        ),
        input: clip,
        start: start,
        length: length,
      );
      final progress = await run(plan);
      final info = await probe(path);
      expect(info.duration.inMilliseconds, closeTo(2500, 120));
      expect(progress.last, closeTo(1, 0.05));
    });

    test('two-pass target size respects the selection budget', () async {
      final path = out('range_compress.mp4');
      final plan = applyClipRange(
        buildCompress(
          input: clip,
          output: path,
          options: const CompressOptions(mode: CompressMode.targetSize, targetMb: 0.3),
          encoders: caps.encoders,
          info: clipInfo.clipped(length),
          passLogPrefix: p.join(tmp.path, 'range2pass'),
        ),
        input: clip,
        start: start,
        length: length,
      );
      expect(plan.steps, hasLength(2));
      await run(plan);
      final info = await probe(path);
      expect(info.duration.inMilliseconds, closeTo(2500, 120));
      expect(await File(path).length(), lessThanOrEqualTo((0.3 * 1024 * 1024).round()));
    });
  });

  group('image convert', () {
    late String png;
    setUpAll(() async {
      png = out('photo source.png');
      final r = await Process.run(bin.ffmpeg, [
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'testsrc2=size=1600x1000',
        '-frames:v',
        '1',
        png,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    });

    for (final f in [PictureFormat.jpg, PictureFormat.avif, PictureFormat.png, PictureFormat.tiff]) {
      test('PNG → ${f.name} with resize', () async {
        final path = out('photo.${f.extension}');
        await run(
          buildImageConvert(
            input: png,
            output: path,
            format: f,
            options: const ImageOptions(quality: 70, maxSide: 800),
            info: await probe(png),
          ),
        );
        final info = await probe(path);
        expect(info.video!.width, 800);
        expect(info.video!.height, 500);
      });
    }

    test('lossy output is much smaller than the PNG source', () async {
      final path = out('small.jpg');
      await run(
        buildImageConvert(
          input: png,
          output: path,
          format: PictureFormat.jpg,
          options: const ImageOptions(quality: 60),
        ),
      );
      expect(await File(path).length(), lessThan(await File(png).length() ~/ 2));
    });

    test('HEIC (macOS sips) decodes at full size', () async {
      final heic = out('iphone.heic');
      final s = await Process.run('sips', ['-s', 'format', 'heic', png, '--out', heic]);
      if (s.exitCode != 0 || !File(heic).existsSync()) {
        markTestSkipped('sips cannot write HEIC here');
        return;
      }
      final path = out('iphone.jpg');
      final heicInfo = await probe(heic);
      await run(
        buildImageConvert(
          input: heic,
          output: path,
          format: PictureFormat.jpg,
          options: const ImageOptions(),
          info: heicInfo,
        ),
      );
      expect((await probe(path)).video!.width, 1600);
      // Resizing a tile grid goes through the stream group.
      final small = out('iphone_small.avif');
      await run(
        buildImageConvert(
          input: heic,
          output: small,
          format: PictureFormat.avif,
          options: const ImageOptions(maxSide: 800),
          info: heicInfo,
        ),
      );
      expect((await probe(small)).video!.width, 800);
      final thumb = await MediaProbe.thumbnail(bin, heicInfo, width: 320);
      expect((await probe(thumb!)).video!.width, 320);
      expect((await probe(thumb)).video!.height, 200, reason: 'whole 3:2 grid, not a square tile');
    });
  });
}
