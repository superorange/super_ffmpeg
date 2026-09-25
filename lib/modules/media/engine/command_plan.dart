import 'package:flutter/foundation.dart';

import '../../../core/utils/shell_words.dart';

/// One ffmpeg invocation (argv without the binary or progress flags).
@immutable
class FfmpegStep {
  const FfmpegStep(this.args, {this.label});
  final List<String> args;
  final String? label;
}

/// Everything needed to run a media job — produced by the pure builders in
/// `builders/`, executed by `MediaJobSpec`.
@immutable
class CommandPlan {
  const CommandPlan({
    required this.steps,
    required this.outputs,
    this.expectedDuration,
    this.auxFiles = const {},
    this.createDirs = const [],
    this.scratchPrefixes = const [],
    this.cleanupOnFailure = true,
    this.maxOutputBytes,
  });

  CommandPlan.single(
    List<String> args, {
    required String output,
    Duration? expectedDuration,
  }) : this(
         steps: [FfmpegStep(args)],
         outputs: [output],
         expectedDuration: expectedDuration,
       );

  final List<FfmpegStep> steps;

  /// Files/folders produced; removed if the job fails or is cancelled.
  final List<String> outputs;

  /// Media duration each step processes — drives the progress percentage.
  final Duration? expectedDuration;

  /// Files written before the run and removed afterwards (e.g. concat lists).
  final Map<String, String> auxFiles;

  /// Folders created before the run (e.g. frame sequence output).
  final List<String> createDirs;

  /// Path prefixes of temp files ffmpeg creates (e.g. two-pass logs).
  final List<String> scratchPrefixes;

  /// Delete [outputs] when the job fails or is cancelled. Only safe when the
  /// outputs were planned as fresh paths — false for user-written commands.
  final bool cleanupOnFailure;

  /// Hard size limit for the (single) output; exceeding it fails the job.
  final int? maxOutputBytes;

  String commandLine([String binary = 'ffmpeg']) =>
      steps.map((s) => ShellWords.join([binary, ...s.args])).join(' && \\\n  ');
}

/// Thrown by builders when options can't produce a valid command.
class PlanException implements Exception {
  const PlanException(this.messageKey, [this.args = const {}]);

  /// Translation key.
  final String messageKey;
  final Map<String, String> args;

  @override
  String toString() => 'PlanException($messageKey, $args)';
}
