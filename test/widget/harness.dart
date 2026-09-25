import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_ffmpeg/app/app.dart';
import 'package:super_ffmpeg/core/settings/settings.dart';
import 'package:super_ffmpeg/modules/media/engine/capabilities.dart';
import 'package:super_ffmpeg/modules/media/engine/ffmpeg_locator.dart';
import 'package:super_ffmpeg/modules/media/engine/media_info.dart';
import 'package:super_ffmpeg/modules/media/providers.dart';
import 'package:super_ffmpeg/ui/widgets/web_preview.dart';

const fakeBinaries = FfmpegBinaries(ffmpeg: '/fake/ffmpeg', ffprobe: '/fake/ffprobe', source: FfmpegSource.bundled);

const fakeCaps = FfmpegCapabilities(
  binaries: fakeBinaries,
  version: '9.0.2',
  encoders: {'libx264', 'libx265', 'h264_videotoolbox', 'hevc_videotoolbox', 'aac', 'libopus', 'libmp3lame'},
  hwaccels: {'videotoolbox'},
);

MediaInfo fakeInfo(String path, {int seconds = 60}) => MediaInfo(
  path: path,
  duration: Duration(seconds: seconds),
  sizeBytes: 50 * 1024 * 1024,
  streams: const [
    MediaStream(index: 0, kind: StreamKind.video, codec: 'h264', width: 1920, height: 1080, frameRate: 30),
    MediaStream(index: 1, kind: StreamKind.audio, codec: 'aac', channels: 2, sampleRate: 48000),
  ],
);

/// Loads translations synchronously from disk (rootBundle is async IO,
/// which never completes inside the widget-test fake zone).
class _FileLoader extends AssetLoader {
  const _FileLoader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final name = locale.countryCode == null ? locale.languageCode : '${locale.languageCode}-${locale.countryCode}';
    return jsonDecode(File('assets/translations/$name.json').readAsStringSync()) as Map<String, dynamic>;
  }
}

final screenshotKey = GlobalKey();

Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  String location = '/',
  bool engineInstalled = true,
  Locale locale = const Locale('en'),
  Map<String, Object> prefs = const {},
  Size size = const Size(1440, 960),
  ui.Image? thumbnail,
  List<ui.Image> filmstrip = const [],
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  EasyLocalization.logger.enableBuildModes = [];
  await EasyLocalization.ensureInitialized();
  final sp = await SharedPreferences.getInstance();

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    RepaintBoundary(
      key: screenshotKey,
      child: EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
        path: 'assets/translations',
        assetLoader: const _FileLoader(),
        startLocale: locale,
        fallbackLocale: const Locale('en'),
        saveLocale: false,
        child: ProviderScope(
          retry: (_, _) => null,
          overrides: [
            sharedPreferencesProvider.overrideWithValue(sp),
            ffmpegBinariesProvider.overrideWithValue(engineInstalled ? fakeBinaries : null),
            ffmpegCapabilitiesProvider.overrideWith((ref) async {
              if (!engineInstalled) throw const EngineMissingException();
              return fakeCaps;
            }),
            nativeMediaAvailableProvider.overrideWithValue(false),
            probeProvider.overrideWith((ref, path) async => fakeInfo(path)),
            thumbnailProvider.overrideWith((ref, path) async => thumbnail?.clone()),
            framePreviewProvider.overrideWith((ref, req) async => thumbnail?.clone()),
            filmstripProvider.overrideWith((ref, req) async => [for (final f in filmstrip) f.clone()]),
            webPreviewSupportedProvider.overrideWithValue(false),
          ],
          child: SuperToolboxApp(initialLocation: location),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(SuperToolboxApp)));
}
