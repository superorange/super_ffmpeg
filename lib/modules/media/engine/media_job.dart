import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/jobs/job.dart';
import 'command_plan.dart';
import 'ffmpeg_runner.dart';

/// Executes a [CommandPlan] as a toolbox job.
class MediaJobSpec extends JobSpec {
  MediaJobSpec({
    required this.title,
    required this.toolId,
    required this.inputs,
    required this.plan,
    required this.ffmpeg,
  });

  @override
  final String title;
  @override
  final String toolId;
  @override
  final List<String> inputs;
  final CommandPlan plan;
  final String ffmpeg;

  @override
  List<String> get outputs => plan.outputs;

  @override
  String get commandLine => plan.commandLine();

  @override
  Future<void> run(JobContext context) async {
    final createdDirs = <String>[];
    var succeeded = false;
    try {
      for (final dir in plan.createDirs) {
        final d = Directory(dir);
        if (!d.existsSync()) {
          d.createSync(recursive: true);
          createdDirs.add(dir);
        }
      }
      for (final entry in plan.auxFiles.entries) {
        File(entry.key)
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(entry.value);
      }

      final steps = plan.steps;
      for (var i = 0; i < steps.length; i++) {
        context.throwIfCancelled();
        final step = steps[i];
        if (steps.length > 1) {
          context.log('── ${step.label ?? 'Step ${i + 1}'} (${i + 1}/${steps.length}) ──');
        }
        final exit = await FfmpegRunner.run(
          ffmpeg: ffmpeg,
          args: step.args,
          cancelSignal: context.cancelled,
          onLog: context.log,
          workingDirectory: Directory.systemTemp.path,
          onProgress: (fp) {
            final f = fp.fractionOf(plan.expectedDuration);
            context.onProgress(
              JobProgress(
                fraction: f == null ? null : (i + f) / steps.length,
                speed: fp.speed,
                fps: fp.fps,
                processed: fp.outTime,
                stepLabel: steps.length > 1 ? '${i + 1}/${steps.length}' : null,
              ),
            );
          },
        );
        if (exit.cancelled) throw const JobCancelled();
        if (!exit.ok) throw JobFailure(exit.errorSummary);
      }
      final limit = plan.maxOutputBytes;
      if (limit != null && plan.outputs.isNotEmpty) {
        final size = File(plan.outputs.first).lengthSync();
        if (size > limit) {
          throw JobFailure(
            'Output is ${(size / 1048576).toStringAsFixed(2)} MB, above the ${(limit / 1048576).toStringAsFixed(2)} MB limit',
            key: 'media.errors.size_exceeded',
            args: {
              'size': (size / 1048576).toStringAsFixed(2),
              'limit': (limit / 1048576).toStringAsFixed(2),
            },
          );
        }
      }
      succeeded = true;
    } finally {
      for (final path in plan.auxFiles.keys) {
        _delete(path);
      }
      for (final prefix in plan.scratchPrefixes) {
        final dir = Directory(p.dirname(prefix));
        if (dir.existsSync()) {
          for (final f in dir.listSync().whereType<File>()) {
            if (p.basename(f.path).startsWith(p.basename(prefix))) _delete(f.path);
          }
        }
      }
      if (!succeeded && plan.cleanupOnFailure) {
        // Remove partial results — outputs were planned as fresh paths.
        for (final out in plan.outputs) {
          if (!plan.createDirs.contains(out) || createdDirs.contains(out)) {
            _delete(out);
          }
        }
      }
    }
  }

  static void _delete(String path) {
    try {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        Directory(path).deleteSync(recursive: true);
      } else if (type != FileSystemEntityType.notFound) {
        File(path).deleteSync();
      }
    } catch (_) {}
  }
}
