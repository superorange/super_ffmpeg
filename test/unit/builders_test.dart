import 'package:flutter_test/flutter_test.dart';
import 'package:super_ffmpeg/modules/media/builders/audio.dart';
import 'package:super_ffmpeg/modules/media/builders/cli.dart';
import 'package:super_ffmpeg/modules/media/builders/codecs.dart';
import 'package:super_ffmpeg/modules/media/builders/compress.dart';
import 'package:super_ffmpeg/modules/media/builders/concat.dart';
import 'package:super_ffmpeg/modules/media/builders/convert.dart';
import 'package:super_ffmpeg/modules/media/builders/frames.dart';
import 'package:super_ffmpeg/modules/media/builders/gif.dart';
import 'package:super_ffmpeg/modules/media/builders/transform.dart';
import 'package:super_ffmpeg/modules/media/builders/trim.dart';
import 'package:super_ffmpeg/modules/media/engine/command_plan.dart';
import 'package:super_ffmpeg/modules/media/engine/media_info.dart';

const _mac = {
  'libx264',
  'libx265',
  'libsvtav1',
  'libvpx-vp9',
  'h264_videotoolbox',
  'hevc_videotoolbox',
  'prores_videotoolbox',
  'prores_ks',
  'aac',
  'libopus',
  'libmp3lame',
  'flac',
  'pcm_s16le',
};
const _cpuOnly = {'libx264', 'aac'};

MediaInfo _video({
  int w = 1920,
  int h = 1080,
  double fps = 30,
  int seconds = 60,
  bool audio = true,
  int rotation = 0,
  String audioCodec = 'aac',
  int channels = 2,
  int sampleRate = 44100,
}) {
  return MediaInfo(
    path: '/v/in.mp4',
    duration: Duration(seconds: seconds),
    streams: [
      MediaStream(
        index: 0,
        kind: StreamKind.video,
        codec: 'h264',
        width: w,
        height: h,
        frameRate: fps,
        rotation: rotation,
      ),
      if (audio)
        MediaStream(index: 1, kind: StreamKind.audio, codec: audioCodec, channels: channels, sampleRate: sampleRate),
    ],
  );
}

List<String> _args(CommandPlan p, [int step = 0]) => p.steps[step].args;

/// Value following [flag] in [args].
String? _opt(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return i < 0 || i + 1 >= args.length ? null : args[i + 1];
}

void main() {
  group('Encoders', () {
    test('prefers GPU when asked and available, else CPU', () {
      expect(Encoders.pick(VideoCodec.h264, _mac)!.encoder, 'h264_videotoolbox');
      expect(Encoders.pick(VideoCodec.h264, _mac, preferGpu: false)!.encoder, 'libx264');
      expect(Encoders.pick(VideoCodec.h264, _cpuOnly)!.encoder, 'libx264');
      expect(Encoders.pick(VideoCodec.hevc, _cpuOnly), isNull);
      expect(Encoders.pick(VideoCodec.copy, const {})!.encoder, 'copy');
    });

    test('quality args per encoder family', () {
      expect(Encoders.quality('libx264', QualityLevel.high), containsAllInOrder(['-crf', '18']));
      expect(Encoders.quality('hevc_videotoolbox', QualityLevel.balanced), ['-q:v', '60']);
      expect(Encoders.quality('libvpx-vp9', QualityLevel.small), containsAll(['-b:v', '0', '38']));
      expect(Encoders.quality('prores_videotoolbox', QualityLevel.high), ['-profile:v', 'hq']);
      expect(Encoders.quality('h264_nvenc', QualityLevel.high), containsAllInOrder(['-cq', '19']));
    });

    test('scaleFilter works on the short side and never upscales', () {
      final landscape = _video().video;
      final portrait = _video(w: 1080, h: 1920).video;
      final rotated = _video(rotation: 90).video; // displayed as 1080x1920
      expect(scaleFilter(Resolution.p720, landscape), 'scale=-2:720');
      expect(scaleFilter(Resolution.p720, portrait), 'scale=720:-2');
      expect(scaleFilter(Resolution.p720, rotated), 'scale=720:-2');
      expect(scaleFilter(Resolution.p2160, landscape), isNull);
      expect(scaleFilter(Resolution.original, landscape), isNull);
      expect(scaleFilter(Resolution.p480, null), 'scale=-2:480');
    });

    test('atempoChain splits factors outside 0.5–2', () {
      expect(atempoChain(1.5), 'atempo=1.5');
      expect(atempoChain(4), 'atempo=2.0,atempo=2.0');
      expect(atempoChain(3), 'atempo=2.0,atempo=1.5');
      expect(atempoChain(0.25), 'atempo=0.5,atempo=0.5');
    });
  });

  group('convert', () {
    test('HEVC in MP4 gets hvc1 tag, faststart and never overwrites', () {
      final plan = buildConvert(
        input: '/v/in.mov',
        output: '/v/out.mp4',
        encoders: _mac,
        info: _video(),
        options: const ConvertOptions(codec: VideoCodec.hevc, preferGpu: false),
      );
      final a = _args(plan);
      expect(_opt(a, '-c:v'), 'libx265');
      expect(_opt(a, '-tag:v'), 'hvc1');
      expect(_opt(a, '-movflags'), '+faststart');
      expect(a.sublist(a.length - 2), ['-n', '/v/out.mp4']);
      expect(plan.expectedDuration, const Duration(seconds: 60));
    });

    test('fps filter only when it lowers the frame rate', () {
      final lower = buildConvert(
        input: 'i',
        output: 'o',
        encoders: _mac,
        info: _video(fps: 60),
        options: const ConvertOptions(frameRate: FrameRateOption.fps30, resolution: Resolution.p720),
      );
      expect(_opt(_args(lower), '-vf'), 'scale=-2:720,fps=30');
      final same = buildConvert(
        input: 'i',
        output: 'o',
        encoders: _mac,
        info: _video(fps: 24),
        options: const ConvertOptions(frameRate: FrameRateOption.fps30),
      );
      expect(_args(same), isNot(contains('-vf')));
    });

    test('stream copy skips encoders and filters; webm uses opus', () {
      final copy = buildConvert(
        input: 'i',
        output: 'o',
        encoders: _mac,
        info: _video(),
        options: const ConvertOptions(codec: VideoCodec.copy, resolution: Resolution.p480, audio: AudioMode.copy),
      );
      expect(_opt(_args(copy), '-c:v'), 'copy');
      expect(_opt(_args(copy), '-c:a'), 'copy');
      expect(_args(copy), isNot(contains('-vf')));

      final webm = buildConvert(
        input: 'i',
        output: 'o',
        encoders: _mac,
        info: _video(),
        options: const ConvertOptions(container: MediaContainer.webm, codec: VideoCodec.vp9),
      );
      expect(_opt(_args(webm), '-c:a'), 'libopus');
    });

    test('missing encoder is a plan error, not a runtime failure', () {
      expect(
        () => buildConvert(
          input: 'i',
          output: 'o',
          encoders: _cpuOnly,
          options: const ConvertOptions(codec: VideoCodec.av1),
        ),
        throwsA(isA<PlanException>().having((e) => e.messageKey, 'key', 'media.errors.encoder_missing')),
      );
    });

    test('codec/container choices stay compatible', () {
      const o = ConvertOptions();
      expect(MediaContainer.mp4.supports(o.withCodec(VideoCodec.prores).codec), isFalse);
      expect(o.withCodec(VideoCodec.prores).container.supports(VideoCodec.prores), isTrue);
      final webm = o.withContainer(MediaContainer.webm, _mac);
      expect(webm.container.supports(webm.codec), isTrue);
      expect(webm.codec, isNot(VideoCodec.copy));
    });
  });

  group('compress', () {
    test('size budget reserves audio and headroom', () {
      final b = SizeBudget.compute(targetMb: 8, duration: const Duration(seconds: 60), hasAudio: true);
      // 8 MiB * 0.96 over 60 s ≈ 1073 kbps total.
      expect(b.audioKbps, 128);
      expect(b.videoKbps, inInclusiveRange(930, 950));
      final silent = SizeBudget.compute(targetMb: 8, duration: const Duration(seconds: 60), hasAudio: false);
      expect(silent.audioKbps, 0);
    });

    test('impossible targets report the minimum size', () {
      expect(
        () => SizeBudget.compute(targetMb: 1, duration: const Duration(minutes: 10), hasAudio: true),
        throwsA(
          isA<PlanException>()
              .having((e) => e.messageKey, 'key', 'media.errors.target_too_small')
              .having((e) => double.parse(e.args['min']!), 'min', greaterThan(1)),
        ),
      );
    });

    test('target size is two-pass x264 with shared passlog and a hard size cap', () {
      final plan = buildCompress(
        input: 'i',
        output: 'o.mp4',
        encoders: _mac,
        info: _video(seconds: 120),
        passLogPrefix: '/tmp/p',
        nullSink: '/dev/null',
        options: const CompressOptions(mode: CompressMode.targetSize, targetMb: 25),
      );
      expect(plan.steps, hasLength(2));
      final p1 = _args(plan, 0), p2 = _args(plan, 1);
      expect(_opt(p1, '-pass'), '1');
      expect(p1.last, '/dev/null');
      expect(p1, contains('-an'));
      expect(_opt(p2, '-pass'), '2');
      expect(_opt(p1, '-b:v'), _opt(p2, '-b:v'));
      expect(_opt(p2, '-passlogfile'), '/tmp/p');
      expect(plan.scratchPrefixes, ['/tmp/p']);
      expect(plan.maxOutputBytes, 25 * 1024 * 1024);
    });

    test('thin budgets auto-downscale; explicit resolution is respected', () {
      // 4K 60fps for 10 minutes into 50 MB → far too few bits for 4K.
      final info = _video(w: 3840, h: 2160, fps: 60, seconds: 600);
      final auto = buildCompress(
        input: 'i',
        output: 'o',
        encoders: _mac,
        info: info,
        options: const CompressOptions(mode: CompressMode.targetSize, targetMb: 50),
      );
      final vf = _opt(_args(auto, 1), '-vf');
      expect(vf, startsWith('scale=-2:'));
      expect(int.parse(vf!.split(':').last), lessThan(2160));

      final fixed = buildCompress(
        input: 'i',
        output: 'o',
        encoders: _mac,
        info: info,
        options: const CompressOptions(mode: CompressMode.targetSize, targetMb: 50, resolution: Resolution.p1080),
      );
      expect(_opt(_args(fixed, 1), '-vf'), 'scale=-2:1080');
    });

    test('quality mode maps level to CRF per codec', () {
      String crf(CompressOptions o) =>
          _opt(_args(buildCompress(input: 'i', output: 'o', encoders: _mac, info: _video(), options: o)), '-crf')!;
      expect(crf(const CompressOptions(level: CompressLevel.light)), '23');
      expect(crf(const CompressOptions(level: CompressLevel.strong, useHevc: true)), '32');
    });
  });

  group('trim', () {
    test('fast mode stream-copies with input seeking', () {
      final plan = buildTrim(
        input: 'i.mkv',
        output: 'o.mkv',
        info: _video(),
        options: const TrimOptions(start: Duration(seconds: 10), end: Duration(seconds: 25, milliseconds: 500)),
      );
      final a = _args(plan);
      expect(a.indexOf('-ss'), lessThan(a.indexOf('-i')));
      expect(_opt(a, '-ss'), '10');
      expect(_opt(a, '-t'), '15.5');
      expect(_opt(a, '-c'), 'copy');
      expect(plan.expectedDuration, const Duration(seconds: 15, milliseconds: 500));
    });

    test('precise mode re-encodes video; extension rules', () {
      final a = _args(
        buildTrim(
          input: 'i',
          output: 'o',
          info: _video(),
          options: const TrimOptions(start: Duration.zero, end: Duration(seconds: 5), precise: true),
        ),
      );
      expect(_opt(a, '-c:v'), 'libx264');
      expect(trimExtension('.MKV', precise: false, hasVideo: true), 'mkv');
      expect(trimExtension('.mkv', precise: true, hasVideo: true), 'mp4');
      expect(trimExtension('.flac', precise: true, hasVideo: false), 'flac');
    });

    test('rejects empty and out-of-bounds ranges', () {
      for (final o in [
        const TrimOptions(start: Duration(seconds: 5), end: Duration(seconds: 5)),
        const TrimOptions(start: Duration(seconds: 70), end: Duration(seconds: 80)),
      ]) {
        expect(() => buildTrim(input: 'i', output: 'o', info: _video(), options: o), throwsA(isA<PlanException>()));
      }
    });
  });

  group('audio', () {
    test('original format copies the stream into the matching container', () {
      final plan = buildAudio(
        input: 'i',
        output: 'o',
        info: _video(),
        options: const AudioOptions(format: AudioFormat.original),
      );
      expect(_opt(_args(plan), '-c:a'), 'copy');
      expect(audioExtension(const AudioOptions(format: AudioFormat.original), _video()), 'm4a');
      expect(extensionForAudioCodec('pcm_s24le'), 'wav');
      expect(extensionForAudioCodec('truehd'), 'mka');
    });

    test('loudnorm pins sample rate; mp3 downmixes surround', () {
      final a = _args(
        buildAudio(
          input: 'i',
          output: 'o',
          info: _video(channels: 6, sampleRate: 48000),
          options: const AudioOptions(format: AudioFormat.mp3, normalize: true, gainDb: -3),
        ),
      );
      expect(_opt(a, '-af'), 'volume=-3.0dB,loudnorm=I=-16:TP=-1.5:LRA=11');
      expect(_opt(a, '-ar'), '48000');
      expect(_opt(a, '-ac'), '2');
      expect(_opt(a, '-b:a'), '192k');
      expect(a, containsAll(['-vn', '-sn', '-dn']));
    });

    test('lossless formats have no bitrate; no-audio inputs are rejected', () {
      final a = _args(
        buildAudio(
          input: 'i',
          output: 'o',
          info: _video(),
          options: const AudioOptions(format: AudioFormat.flac),
        ),
      );
      expect(a, isNot(contains('-b:a')));
      expect(
        () => buildAudio(input: 'i', output: 'o', info: _video(audio: false), options: const AudioOptions()),
        throwsA(isA<PlanException>()),
      );
    });
  });

  group('gif', () {
    test('palette graph, no upscale, loop flag', () {
      final a = _args(
        buildGif(
          input: 'i',
          output: 'o.gif',
          info: _video(w: 400, h: 300),
          options: const GifOptions(width: 640, loop: false, dither: GifDither.bayer, start: Duration(seconds: 2)),
        ),
      );
      final graph = _opt(a, '-filter_complex')!;
      expect(graph, contains('palettegen'));
      expect(graph, contains('paletteuse=dither=bayer'));
      expect(graph, isNot(contains('lanczos')), reason: 'source narrower than requested width');
      expect(_opt(a, '-loop'), '-1');
      expect(_opt(a, '-ss'), '2');
    });
  });

  group('transform', () {
    test('rotation, flip and speed build one filter chain with atempo', () {
      final plan = buildTransform(
        input: 'i',
        output: 'o',
        encoders: _mac,
        info: _video(seconds: 60),
        options: const TransformOptions(speed: 2, rotation: Rotation.cw90, flipH: true, preferGpu: false),
      );
      final a = _args(plan);
      expect(_opt(a, '-vf'), 'transpose=clock,hflip,setpts=PTS/2.0');
      expect(_opt(a, '-af'), 'atempo=2.0');
      expect(plan.expectedDuration, const Duration(seconds: 30));
    });

    test('vertical framing uses a blurred-background filter_complex', () {
      final a = _args(
        buildTransform(
          input: 'i',
          output: 'o',
          encoders: _mac,
          info: _video(),
          options: const TransformOptions(framing: Framing.vertical916, mute: true),
        ),
      );
      final graph = _opt(a, '-filter_complex')!;
      expect(graph, startsWith('[0:v]split=2'));
      expect(graph, contains('crop=1080:1920'));
      expect(graph, contains('gblur'));
      expect(_opt(a, '-map'), '[vout]');
      expect(a, contains('-an'));
      expect(a, isNot(contains('0:a?')));
    });

    test('mute alone is valid and emits no empty -vf', () {
      final a = _args(
        buildTransform(
          input: 'i',
          output: 'o',
          encoders: _mac,
          info: _video(),
          options: const TransformOptions(mute: true),
        ),
      );
      expect(a, isNot(contains('-vf')));
      expect(
        () =>
            buildTransform(input: 'i', output: 'o', encoders: _mac, info: _video(), options: const TransformOptions()),
        throwsA(isA<PlanException>().having((e) => e.messageKey, 'key', 'media.errors.nothing_to_do')),
      );
    });
  });

  group('concat', () {
    test('ffconcat list escapes single quotes', () {
      expect(
        ffconcatList(["/a/it's.mp4", '/b/x.mp4']),
        "ffconcat version 1.0\nfile '/a/it'\\''s.mp4'\nfile '/b/x.mp4'",
      );
    });

    test('fast mode writes the list as an aux file and copies streams', () {
      final plan = buildConcat(
        inputs: ['/a.mp4', '/b.mp4'],
        output: 'o.mp4',
        encoders: _mac,
        listPath: '/tmp/l.txt',
        infos: [_video(seconds: 10), _video(seconds: 5)],
        options: const ConcatOptions(mode: ConcatMode.fast),
      );
      expect(plan.auxFiles.keys, ['/tmp/l.txt']);
      expect(_args(plan), containsAllInOrder(['-f', 'concat', '-safe', '0', '-i', '/tmp/l.txt', '-c', 'copy']));
      expect(plan.expectedDuration, const Duration(seconds: 15));
    });

    test('compatible mode normalizes to the first clip and fills missing audio', () {
      final a = _args(
        buildConcat(
          inputs: ['/a', '/b'],
          output: 'o',
          encoders: _mac,
          listPath: 'l',
          infos: [_video(w: 1280, h: 720, fps: 25), _video(w: 640, h: 480, audio: false, seconds: 4)],
          options: const ConcatOptions(preferGpu: false),
        ),
      );
      final graph = _opt(a, '-filter_complex')!;
      expect(graph, contains('scale=1280:720'));
      expect(graph, contains('fps=25.0'));
      expect(graph, contains('anullsrc'));
      expect(graph, contains('atrim=duration=4.0'));
      expect(graph, endsWith('concat=n=2:v=1:a=1[v][a]'));
    });

    test('needs at least two inputs', () {
      expect(
        () => buildConcat(inputs: ['/a'], output: 'o', encoders: _mac, listPath: 'l', options: const ConcatOptions()),
        throwsA(isA<PlanException>()),
      );
    });
  });

  group('frames', () {
    test('single snapshot clamps a time past the end', () {
      final a = _args(
        buildFrames(
          input: 'i',
          output: 'o.jpg',
          info: _video(seconds: 3),
          options: const FramesOptions(at: Duration(seconds: 10)),
        ),
      );
      expect(_opt(a, '-ss'), '0');
      expect(_opt(a, '-frames:v'), '1');
    });

    test('interval mode writes a numbered sequence into a fresh folder', () {
      final plan = buildFrames(
        input: '/v/clip.mp4',
        output: '/v/clip_frames',
        info: _video(),
        options: const FramesOptions(mode: FramesMode.interval, everySeconds: 5, format: ImageFormat.png),
      );
      expect(plan.createDirs, ['/v/clip_frames']);
      expect(_args(plan).last, '/v/clip_frames/clip_%04d.png');
      expect(_opt(_args(plan), '-vf'), 'fps=1/5.0');
    });

    test('contact sheet samples evenly across the duration', () {
      final a = _args(
        buildFrames(
          input: 'i',
          output: 'o',
          info: _video(seconds: 120),
          options: const FramesOptions(mode: FramesMode.contactSheet, columns: 4, rows: 4),
        ),
      );
      expect(_opt(a, '-vf'), startsWith('fps=16/120.0,scale=320:-2,tile=4x4'));
    });
  });

  group('cli', () {
    test('placeholders substitute after tokenizing so paths stay one arg', () {
      final args = expandCliArgs('ffmpeg -i {input} -c copy "{dir}/{name} out.mkv"', input: "/m/my 'clip'.mp4");
      expect(args, ['-i', "/m/my 'clip'.mp4", '-c', 'copy', "/m/my 'clip' out.mkv"]);
    });

    test('adds -n unless the user chose, and never deletes user outputs', () {
      final plan = buildCli(template: '-i {input} out.mp4', input: '/a.mp4');
      expect(_args(plan).first, '-n');
      expect(plan.outputs, ['out.mp4']);
      expect(plan.cleanupOnFailure, isFalse);
      expect(_args(buildCli(template: '-y -i a b')).first, '-y');
    });

    test('bad quoting and empty commands are plan errors', () {
      expect(() => buildCli(template: '-i "x'), throwsA(isA<PlanException>()));
      expect(() => buildCli(template: '  '), throwsA(isA<PlanException>()));
    });
  });
}
