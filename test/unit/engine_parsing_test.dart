import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_ffmpeg/modules/media/engine/capabilities.dart';
import 'package:super_ffmpeg/modules/media/engine/ffmpeg_locator.dart';
import 'package:super_ffmpeg/modules/media/engine/ffmpeg_runner.dart';
import 'package:super_ffmpeg/modules/media/engine/media_info.dart';
import 'package:super_ffmpeg/modules/media/engine/progress.dart';

void main() {
  group('FfmpegProgressParser', () {
    test('emits one snapshot per block with parsed fields', () {
      final parser = FfmpegProgressParser();
      final lines =
          '''
frame=120
fps=59.94
bitrate=1200.5kbits/s
total_size=524288
out_time_us=4000000
out_time_ms=4000000
out_time=00:00:04.000000
speed=2.03x
progress=continue
frame=240
fps=60.00
out_time_us=N/A
out_time=00:00:08.500000
speed=N/A
progress=end
'''
              .trim()
              .split('\n');
      final snaps = [for (final l in lines) ?parser.add(l)];
      expect(snaps, hasLength(2));
      expect(snaps[0].outTime, const Duration(seconds: 4));
      expect(snaps[0].fps, closeTo(59.94, 1e-9));
      expect(snaps[0].speed, closeTo(2.03, 1e-9));
      expect(snaps[0].frame, 120);
      expect(snaps[0].totalSize, 524288);
      expect(snaps[0].done, isFalse);
      // Falls back to the textual out_time when *_us is N/A.
      expect(snaps[1].outTime, const Duration(seconds: 8, milliseconds: 500));
      expect(snaps[1].speed, isNull);
      expect(snaps[1].done, isTrue);
    });

    test('fractionOf clamps, handles unknown duration and done', () {
      const p = FfmpegProgress(outTime: Duration(seconds: 5));
      expect(p.fractionOf(const Duration(seconds: 10)), 0.5);
      expect(p.fractionOf(const Duration(seconds: 2)), 1.0);
      expect(p.fractionOf(null), isNull);
      expect(const FfmpegProgress(done: true).fractionOf(null), 1.0);
    });
  });

  group('MediaInfo.fromProbeJson', () {
    final json = jsonEncode({
      'streams': [
        {
          'index': 0,
          'codec_name': 'mjpeg',
          'codec_type': 'video',
          'width': 600,
          'height': 600,
          'disposition': {'attached_pic': 1},
        },
        {
          'index': 1,
          'codec_name': 'hevc',
          'codec_long_name': 'H.265 / HEVC',
          'profile': 'Main 10',
          'codec_type': 'video',
          'width': 3840,
          'height': 2160,
          'pix_fmt': 'yuv420p10le',
          'color_transfer': 'smpte2084',
          'avg_frame_rate': '30000/1001',
          'r_frame_rate': '30/1',
          'bit_rate': '25000000',
          'side_data_list': [
            {'side_data_type': 'Display Matrix', 'rotation': -90},
          ],
          'disposition': {'default': 1, 'attached_pic': 0},
        },
        {
          'index': 2,
          'codec_name': 'aac',
          'codec_type': 'audio',
          'sample_rate': '48000',
          'channels': 6,
          'channel_layout': '5.1',
          'tags': {'language': 'jpn'},
        },
        {'index': 3, 'codec_name': 'subrip', 'codec_type': 'subtitle', 'avg_frame_rate': '0/0'},
      ],
      'format': {
        'format_name': 'mov,mp4,m4a,3gp,3g2,mj2',
        'format_long_name': 'QuickTime / MOV',
        'duration': '12.345000',
        'size': '38000000',
        'bit_rate': '24625000',
        'tags': {'title': 'Demo', 'encoder': 'Lavf'},
      },
    });

    final info = MediaInfo.fromProbeJson('/x/demo.mov', json);

    test('reads container facts', () {
      expect(info.duration, const Duration(seconds: 12, milliseconds: 345));
      expect(info.sizeBytes, 38000000);
      expect(info.bitrate, 24625000);
      expect(info.formatLongName, 'QuickTime / MOV');
      expect(info.tags['title'], 'Demo');
    });

    test('primary video skips cover art; rotation swaps display size', () {
      final v = info.video!;
      expect(v.index, 1);
      expect(v.rotation, 270);
      expect(v.displayWidth, 2160);
      expect(v.displayHeight, 3840);
      expect(v.frameRate, closeTo(29.97, 0.01));
      expect(v.isHdr, isTrue);
      expect(v.isDefault, isTrue);
      expect(info.hasCoverArt, isTrue);
    });

    test('audio and subtitle streams', () {
      expect(info.audio!.channels, 6);
      expect(info.audio!.sampleRate, 48000);
      expect(info.audio!.language, 'jpn');
      expect(info.of(StreamKind.subtitle).single.frameRate, isNull);
    });

    test('audio-only files have no video even with cover art', () {
      final cover = MediaInfo.fromProbeJson(
        '/a.mp3',
        jsonEncode({
          'streams': [
            {'index': 0, 'codec_name': 'mp3', 'codec_type': 'audio', 'channels': 2},
            {
              'index': 1,
              'codec_name': 'png',
              'codec_type': 'video',
              'disposition': {'attached_pic': 1},
            },
          ],
          'format': {'duration': '3.0'},
        }),
      );
      expect(cover.hasVideo, isFalse);
      expect(cover.hasCoverArt, isTrue);
    });
  });

  group('FfmpegCapabilities parsing', () {
    test('parses encoders, skipping the legend', () {
      const out = '''
Encoders:
 V..... = Video
 A..... = Audio
 ------
 V....D libx264              libx264 H.264 / AVC / MPEG-4 AVC (codec h264)
 V....D h264_videotoolbox    VideoToolbox H.264 Encoder (codec h264)
 V....D hevc_videotoolbox    VideoToolbox H.265 Encoder (codec hevc)
 A....D aac                  AAC (Advanced Audio Coding)
 S..... srt                  SubRip subtitle
''';
      final encoders = FfmpegCapabilities.parseEncoders(out);
      expect(encoders, {'libx264', 'h264_videotoolbox', 'hevc_videotoolbox', 'aac', 'srt'});
    });

    test('parses version and hwaccels', () {
      expect(FfmpegCapabilities.parseVersion('ffmpeg version 8.1.2 Copyright (c) 2000-2026'), '8.1.2');
      expect(FfmpegCapabilities.parseVersion('garbage'), 'unknown');
      expect(FfmpegCapabilities.parseHwaccels('Hardware acceleration methods:\nvideotoolbox\n\n'), {'videotoolbox'});
    });

    test('gpuEncoders lists hardware encoders only', () {
      const caps = FfmpegCapabilities(
        binaries: FfmpegBinaries(ffmpeg: 'ffmpeg', ffprobe: 'ffprobe'),
        version: '8',
        encoders: {'libx264', 'hevc_videotoolbox', 'h264_nvenc', 'aac'},
        hwaccels: {},
      );
      expect(caps.gpuEncoders, ['h264_nvenc', 'hevc_videotoolbox']);
      expect(caps.hasGpu, isTrue);
    });
  });

  group('FfmpegLocator', () {
    List<(String, FfmpegSource)> candidates({String? custom}) => FfmpegLocator.candidates(
      customDir: custom,
      bundled: ['/App.app/Contents/MacOS'],
      environment: {'PATH': '/usr/bin:/opt/homebrew/bin:/bin'},
      operatingSystem: 'macos',
    );

    test('order: custom folder, then bundled, then system', () {
      final c = candidates(custom: '/custom');
      expect(c.first, ('/custom', FfmpegSource.custom));
      expect(c[1], ('/App.app/Contents/MacOS', FfmpegSource.bundled));
      final dirs = [for (final e in c) e.$1];
      expect(dirs.indexOf('/opt/homebrew/bin'), lessThan(dirs.indexOf('/usr/bin')));
      expect(dirs.where((d) => d == '/opt/homebrew/bin'), hasLength(1), reason: 'deduplicated');
    });

    test('bundled wins over system when both exist', () {
      final files = {
        '/App.app/Contents/MacOS/ffmpeg',
        '/App.app/Contents/MacOS/ffprobe',
        '/opt/homebrew/bin/ffmpeg',
        '/opt/homebrew/bin/ffprobe',
      };
      final bin = FfmpegLocator.locate(
        bundled: ['/App.app/Contents/MacOS'],
        operatingSystem: 'macos',
        environment: const {},
        exists: files.contains,
      );
      expect(bin?.source, FfmpegSource.bundled);
      expect(bin?.ffmpeg, '/App.app/Contents/MacOS/ffmpeg');
    });

    test('falls back to system; requires ffmpeg and ffprobe side by side', () {
      final files = {'/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg', '/usr/local/bin/ffprobe'};
      final bin = FfmpegLocator.locate(
        bundled: ['/App.app/Contents/MacOS'],
        operatingSystem: 'macos',
        environment: const {},
        exists: files.contains,
      );
      expect(bin?.ffmpeg, '/usr/local/bin/ffmpeg');
      expect(bin?.source, FfmpegSource.system);
      expect(
        FfmpegLocator.locate(bundled: const [], includeSystem: false, exists: files.contains),
        isNull,
      );
    });
  });

  test('FfmpegExit.errorSummary picks the most relevant line', () {
    const exit = FfmpegExit(
      exitCode: 1,
      cancelled: false,
      tail: [
        'Input #0, mov...',
        'x.mp4: No such file or directory',
        'Conversion finished',
      ],
    );
    expect(exit.errorSummary, 'x.mp4: No such file or directory');
    expect(const FfmpegExit(exitCode: 3, cancelled: false, tail: []).errorSummary, contains('3'));
  });
}
