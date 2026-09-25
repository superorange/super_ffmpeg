// Renders key screens to build/screenshots/*.png with real macOS fonts for
// design review. Not part of the default run:
//   fvm flutter test test/screenshots --run-skipped
@Tags(['screenshots'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_ffmpeg/app/shell/command_palette.dart';
import 'package:super_ffmpeg/core/jobs/job.dart';
import 'package:super_ffmpeg/core/jobs/job_queue.dart';
import 'package:super_ffmpeg/modules/media/studio/studio_state.dart';
import 'package:super_ffmpeg/ui/theme/app_theme.dart';

import '../widget/harness.dart';

const _flutterFonts = 'bin/cache/artifacts/material_fonts';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    if (File(path).existsSync()) {
      loader.addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    }
  }
  await loader.load();
}

class _DemoJob extends JobSpec {
  _DemoJob(this.title, this.outputs, {this.fail = false, this.progress = 0.62, this.hold = true});
  @override
  final String title;
  @override
  final List<String> outputs;
  final bool fail;
  final bool hold;
  final double progress;
  @override
  String get toolId => title.startsWith('视频压缩')
      ? 'compress'
      : title.startsWith('GIF')
      ? 'gif'
      : 'convert';
  @override
  List<String> get inputs => const [];
  @override
  String get commandLine => 'ffmpeg -i in.mov -c:v h264_videotoolbox -q:v 60 out.mp4';

  @override
  Future<void> run(JobContext context) async {
    context.onProgress(JobProgress(fraction: progress, speed: 3.42, fps: 102.6));
    if (fail) throw const JobFailure('Invalid data found when processing input');
    if (hold) await context.cancelled;
  }
}

void main() {
  late ui.Image thumb;
  final strip = <ui.Image>[];

  setUpAll(() async {
    AppTheme.fontFamilyOverride = 'Roboto';
    final sdk =
        Platform.environment['FLUTTER_ROOT'] ??
        File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
    await _loadFont('Roboto', [
      '/System/Library/AssetsV2/com_apple_MobileAsset_Font8/86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc',
      '/System/Library/Fonts/Hiragino Sans GB.ttc',
    ]);
    await _loadFont('Menlo', ['/System/Library/Fonts/Menlo.ttc']);
    await _loadFont('MaterialIcons', ['$sdk/$_flutterFonts/MaterialIcons-Regular.otf']);
    final dir = Directory('${Directory.systemTemp.path}/super_toolbox_shots')..createSync(recursive: true);
    final ffmpeg = File('vendor/ffmpeg/darwin-arm64/bin/ffmpeg').existsSync()
        ? 'vendor/ffmpeg/darwin-arm64/bin/ffmpeg'
        : 'ffmpeg';
    Process.runSync(ffmpeg, [
      '-y',
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'testsrc2=size=1280x720:rate=2',
      '-frames:v',
      '16',
      '${dir.path}/f_%02d.jpg',
    ]);
    Future<ui.Image> load(String path) async {
      final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
      return (await codec.getNextFrame()).image;
    }

    thumb = await load('${dir.path}/f_05.jpg');
    for (var i = 1; i <= 16; i++) {
      strip.add(await load('${dir.path}/f_${i.toString().padLeft(2, '0')}.jpg'));
    }
  });

  Future<void> shot(WidgetTester tester, String name) async {
    await tester
        .pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2))
        .catchError((_) => 0);
    // Give the engine real time to decode thumbnails.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump(const Duration(milliseconds: 50));
    final boundary = screenshotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('build/screenshots/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  const zh = Locale('zh', 'CN');
  const dark = {'theme_mode': 'dark'};

  Future<void> page(WidgetTester tester, String name, String location, {bool isDark = false, Size? size}) async {
    await pumpApp(
      tester,
      locale: zh,
      location: location,
      thumbnail: thumb,
      filmstrip: strip,
      prefs: isDark ? dark : const {},
      size: size ?? const Size(1440, 960),
    );
    await shot(tester, name);
  }

  testWidgets('home', (tester) async {
    await pumpApp(
      tester,
      locale: zh,
      thumbnail: thumb,
      prefs: {
        'recent_tools': ['compress', 'json', 'markdown', 'gif'],
      },
    );
    await shot(tester, '01_home_light');
  });

  testWidgets('home dark', (tester) async {
    await pumpApp(tester, locale: zh, thumbnail: thumb, prefs: dark);
    await shot(tester, '02_home_dark');
  });

  testWidgets('studio empty', (tester) async => page(tester, '03_studio_empty', '/media/convert', isDark: true));

  testWidgets('studio convert', (tester) async {
    final c = await pumpApp(
      tester,
      locale: zh,
      location: '/media/convert',
      thumbnail: thumb,
      filmstrip: strip,
      prefs: dark,
    );
    c.read(studioProvider.notifier)
      ..add(['/Movies/旅行 Vlog 2026.mov', '/Movies/drone_4k.mp4', '/Movies/interview.mkv'])
      ..select('/Movies/旅行 Vlog 2026.mov')
      ..setPlayhead(const Duration(seconds: 21))
      ..setRange(const Duration(seconds: 12), const Duration(seconds: 38));
    await shot(tester, '04_studio_convert_dark');
  });

  testWidgets('studio compress light', (tester) async {
    final c = await pumpApp(tester, locale: zh, location: '/media/compress', thumbnail: thumb, filmstrip: strip);
    c.read(studioProvider.notifier).add(['/Movies/screen_recording.mov']);
    await tester.pumpAndSettle();
    await tester.tap(find.text('按目标大小'));
    await shot(tester, '05_studio_compress_light');
  });

  testWidgets('studio transform', (tester) async {
    final c = await pumpApp(
      tester,
      locale: zh,
      location: '/media/transform',
      thumbnail: thumb,
      filmstrip: strip,
      prefs: dark,
    );
    c.read(studioProvider.notifier).add(['/Movies/keynote.mp4']);
    await tester.pumpAndSettle();
    await tester.tap(find.text('竖屏 9:16'));
    await shot(tester, '06_studio_transform_dark');
  });

  testWidgets('json', (tester) async => page(tester, '07_json_dark', '/tool/json', isDark: true));
  testWidgets('json light', (tester) async => page(tester, '08_json_light', '/tool/json'));
  testWidgets('json diff', (tester) async => page(tester, '09_json_diff', '/tool/json_diff', isDark: true));
  testWidgets('json code', (tester) async => page(tester, '10_json_code', '/tool/json_code'));
  testWidgets('regex', (tester) async => page(tester, '11_regex', '/tool/regex', isDark: true));
  testWidgets('color', (tester) async => page(tester, '12_color', '/tool/color'));
  testWidgets('jwt', (tester) async => page(tester, '13_jwt', '/tool/jwt', isDark: true));
  testWidgets('hash', (tester) async => page(tester, '14_hash', '/tool/hash'));
  testWidgets('diff', (tester) async => page(tester, '15_diff', '/tool/diff', isDark: true));
  testWidgets('timestamp', (tester) async => page(tester, '16_timestamp', '/tool/timestamp'));
  testWidgets('cron', (tester) async => page(tester, '17_cron', '/tool/cron', isDark: true));
  testWidgets('uuid', (tester) async => page(tester, '18_uuid', '/tool/uuid'));
  testWidgets('password', (tester) async => page(tester, '19_password', '/tool/password', isDark: true));
  testWidgets('qrcode', (tester) async => page(tester, '20_qrcode', '/tool/qrcode'));
  testWidgets('number base', (tester) async => page(tester, '21_number_base', '/tool/number_base', isDark: true));
  testWidgets('text tools', (tester) async => page(tester, '22_text_tools', '/tool/text_tools'));
  testWidgets('case', (tester) async => page(tester, '23_case', '/tool/case', isDark: true));
  testWidgets('js runner', (tester) async => page(tester, '24_js', '/tool/js_runner', isDark: true));
  testWidgets('html', (tester) async => page(tester, '25_html', '/tool/html_preview'));
  testWidgets('markdown', (tester) async => page(tester, '26_markdown', '/tool/markdown', isDark: true));
  testWidgets('base64', (tester) async => page(tester, '27_base64', '/tool/base64'));
  testWidgets('url', (tester) async => page(tester, '28_url', '/tool/url', isDark: true));
  testWidgets('csv', (tester) async => page(tester, '29_csv', '/tool/csv_json'));
  testWidgets('yaml', (tester) async => page(tester, '30_yaml', '/tool/json_yaml', isDark: true));

  testWidgets('tasks', (tester) async {
    final c = await pumpApp(tester, locale: zh, location: '/tasks', prefs: {'theme_mode': 'dark', 'concurrency': 3});
    c.read(jobQueueProvider.notifier).enqueueAll([
      _DemoJob('格式转换 · 旅行 Vlog 2026.mov', ['/Movies/旅行 Vlog 2026_h264.mp4'], hold: false),
      _DemoJob('GIF 制作 · reaction.mp4', ['/Movies/reaction.gif'], fail: true),
      _DemoJob('视频压缩 · screen_recording.mov', ['/Movies/screen_recording_compressed.mp4']),
      _DemoJob('格式转换 · drone_4k.mp4', ['/Movies/drone_4k_hevc.mp4'], progress: 0.18),
    ]);
    await tester.pump();
    await tester.pump();
    await shot(tester, '31_tasks_dark');
    c.read(jobQueueProvider.notifier).cancelAll();
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('palette', (tester) async {
    await pumpApp(tester, locale: zh);
    unawaited(CommandPalette.show(tester.element(find.text('今天想处理点什么？'))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'json');
    await shot(tester, '32_palette_light');
  });

  testWidgets('settings', (tester) async => page(tester, '33_settings', '/settings'));

  testWidgets('studio narrow', (tester) async {
    final c = await pumpApp(
      tester,
      locale: zh,
      location: '/media/concat',
      thumbnail: thumb,
      filmstrip: strip,
      size: const Size(900, 820),
    );
    c.read(studioProvider.notifier).add(['/Movies/intro.mp4', '/Movies/part1.mp4', '/Movies/outro.mp4']);
    await shot(tester, '34_studio_narrow');
  });
}
