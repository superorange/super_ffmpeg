import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:super_ffmpeg/app/tool_registry.dart';
import 'package:super_ffmpeg/core/jobs/job.dart';
import 'package:super_ffmpeg/core/jobs/job_queue.dart';
import 'package:super_ffmpeg/core/settings/settings.dart';
import 'package:super_ffmpeg/modules/media/engine/media_job.dart';
import 'package:super_ffmpeg/modules/media/studio/studio_state.dart';

import 'harness.dart';

class _ControlledJob extends JobSpec {
  final finish = Completer<void>();
  @override
  String get title => 'Convert · holiday.mov';
  @override
  String get toolId => 'convert';
  @override
  List<String> get inputs => const ['/v/holiday.mov'];
  @override
  List<String> get outputs => const ['/v/holiday_h264.mp4'];
  @override
  String get commandLine => 'ffmpeg -i /v/holiday.mov out.mp4';

  @override
  Future<void> run(JobContext context) async {
    context.onProgress(const JobProgress(fraction: 0.5, speed: 2.5, fps: 75));
    await Future.any([finish.future, context.cancelled]);
    context.throwIfCancelled();
  }
}

void main() {
  group('shell', () {
    testWidgets('home shows the studio card, drop zone and every category', (tester) async {
      await pumpApp(tester);
      expect(find.text('What are we working on today?'), findsOneWidget);
      expect(find.text('Media Studio'), findsWidgets);
      expect(find.text('Drop any file'), findsOneWidget);
      for (final label in ['Data & JSON', 'Web dev', 'Encode & crypto', 'Text', 'Generate & time']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('JSON Formatter'), findsWidgets);
      expect(find.text('FFmpeg 9.0.2'), findsWidgets);
      expect(find.text('VideoToolbox'), findsOneWidget);
    });

    testWidgets('tool card opens its page', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Structural diff that ignores key order'));
      await tester.pumpAndSettle();
      expect(find.text('Differences'), findsOneWidget);
    });

    testWidgets('⌘K palette searches and opens a studio tab', (tester) async {
      await pumpApp(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.text('Search tools and pages…'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'meme');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Drop a video or audio file'), findsOneWidget);
      final router = GoRouter.of(tester.element(find.text('Drop a video or audio file')));
      expect(router.state.uri.path, '/media/gif');
    });

    testWidgets('every available tool page builds cleanly', (tester) async {
      final container = await pumpApp(tester);
      container.read(studioProvider.notifier).add(['/v/clip.mp4']);
      for (final tool in toolRegistry.where((t) => t.isAvailable)) {
        final ctx = tester.element(find.byType(Scaffold).first);
        GoRouter.of(ctx).go(tool.route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tool.id);
      }
      container.read(studioProvider.notifier).clear();
      await tester.pumpAndSettle();
    });

    testWidgets('settings switch theme and persist it', (tester) async {
      final container = await pumpApp(tester, location: '/settings');
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
      expect(container.read(sharedPreferencesProvider).getString('theme_mode'), 'dark');
    });

    testWidgets('Chinese locale renders translated shell', (tester) async {
      await pumpApp(tester, locale: const Locale('zh', 'CN'));
      expect(find.text('今天想处理点什么？'), findsOneWidget);
      expect(find.text('媒体工作室'), findsWidgets);
      expect(find.text('JSON 格式化'), findsWidgets);
    });
  });

  group('media studio', () {
    testWidgets('one file drives every tab; batch scope plans all files', (tester) async {
      final container = await pumpApp(tester, location: '/media/convert');
      expect(find.text('Drop a video or audio file'), findsOneWidget);

      container.read(studioProvider.notifier).add(['/v/a.mov', '/v/b.mov']);
      await tester.pumpAndSettle();
      // Library chips + facts panel for the active (first new) file.
      expect(find.text('a.mov'), findsWidgets);
      expect(find.text('b.mov'), findsOneWidget);
      expect(find.text('Convert · 1'), findsOneWidget);
      expect(find.text('a_h264.mp4'), findsOneWidget);
      expect(find.text('h264_videotoolbox'), findsOneWidget);

      await tester.tap(find.text('All 2'));
      await tester.pumpAndSettle();
      expect(find.text('Convert · 2'), findsOneWidget);

      await tester.tap(find.text('Convert · 2'));
      await tester.pump();
      final jobs = container.read(jobQueueProvider);
      expect(jobs, hasLength(2));
      expect((jobs.first.spec as MediaJobSpec).plan.outputs.single, endsWith('_h264.mp4'));
      expect(find.text('2 task(s) queued'), findsOneWidget);

      // Switching tabs keeps the same file.
      await tester.tap(find.text('Compress'));
      await tester.pumpAndSettle();
      expect(find.text('Compress · 2'), findsOneWidget);

      container.read(jobQueueProvider.notifier).cancelAll();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('timeline selection clips other tools on demand', (tester) async {
      final container = await pumpApp(tester, location: '/media/convert');
      final studio = container.read(studioProvider.notifier)..add(['/v/clip.mp4']);
      studio.setRange(const Duration(seconds: 5), const Duration(seconds: 20));
      await tester.pumpAndSettle();

      expect(find.text('Selection only 0:05.0–0:20.0'), findsOneWidget);
      // Show the command: input-seeking was added before -i.
      await tester.tap(find.byTooltip('Command'));
      await tester.pumpAndSettle();
      expect(find.textContaining('-ss 5 -t 15 -i /v/clip.mp4'), findsOneWidget);

      // Opt out of the selection.
      await tester.tap(find.text('Selection only 0:05.0–0:20.0'));
      await tester.pumpAndSettle();
      expect(find.textContaining('-ss 5 -t 15'), findsNothing);
    });

    testWidgets('trim needs a selection, then cuts it', (tester) async {
      final container = await pumpApp(tester, location: '/media/trim');
      container.read(studioProvider.notifier).add(['/v/clip.mp4']);
      await tester.pumpAndSettle();
      expect(find.text('Select the part to keep on the timeline first'), findsOneWidget);

      container.read(studioProvider.notifier).setRange(const Duration(seconds: 2), const Duration(seconds: 12));
      await tester.pumpAndSettle();
      expect(find.text('Select the part to keep on the timeline first'), findsNothing);
      expect(find.text('clip_trim.mp4'), findsOneWidget);
    });

    testWidgets('keyboard marks in and out at the playhead', (tester) async {
      final container = await pumpApp(tester, location: '/media/trim');
      final studio = container.read(studioProvider.notifier)..add(['/v/clip.mp4']);
      await tester.pumpAndSettle();
      studio.setPlayhead(const Duration(seconds: 10));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      studio.setPlayhead(const Duration(seconds: 25));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
      await tester.pumpAndSettle();
      expect(container.read(studioProvider).range(), const ClipRange(Duration(seconds: 10), Duration(seconds: 25)));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(container.read(studioProvider).range(), isNull);
    });

    testWidgets('compress target-size budget follows the selection', (tester) async {
      final container = await pumpApp(tester, location: '/media/compress');
      container.read(studioProvider.notifier).add(['/v/clip.mp4']);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Target size'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('8 MB'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Video 9'), findsOneWidget, reason: '8 MiB over 60 s ≈ 940 kbps video');

      container.read(studioProvider.notifier).setRange(Duration.zero, const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.textContaining('Video 2'), findsOneWidget, reason: '30 s selection doubles the budget (≈ 2019 kbps)');
    });

    testWidgets('invalid options disable start and explain why', (tester) async {
      final container = await pumpApp(tester, location: '/media/transform');
      container.read(studioProvider.notifier).add(['/v/clip.mp4']);
      await tester.pumpAndSettle();
      expect(find.text('Pick at least one change'), findsOneWidget);
    });

    testWidgets('merge uses the library order', (tester) async {
      final container = await pumpApp(tester, location: '/media/concat');
      container.read(studioProvider.notifier).add(['/v/one.mp4']);
      await tester.pumpAndSettle();
      expect(find.text('Add at least 2 files to the library above'), findsWidgets);
      container.read(studioProvider.notifier).add(['/v/two.mp4']);
      await tester.pumpAndSettle();
      expect(find.text('one_merged.mp4'), findsOneWidget);
    });

    testWidgets('studio explains how to install a missing engine', (tester) async {
      await pumpApp(tester, location: '/media/trim', engineInstalled: false);
      expect(find.text('FFmpeg not found'), findsWidgets);
    });
  });

  testWidgets('task center shows live progress, then completion', (tester) async {
    final container = await pumpApp(tester, location: '/tasks');
    expect(find.text('No tasks yet'), findsOneWidget);

    final job = _ControlledJob();
    container.read(jobQueueProvider.notifier).enqueueAll([job]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Convert · holiday.mov'), findsOneWidget);
    expect(find.text('→ holiday_h264.mp4'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.textContaining('50.0%'), findsOneWidget);
    expect(find.textContaining('2.50×'), findsOneWidget);

    job.finish.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Done'), findsWidgets);
    expect(find.textContaining('100%'), findsOneWidget);
  });
}
