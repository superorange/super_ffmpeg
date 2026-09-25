import 'dart:async';

import 'package:flutter/foundation.dart';

enum JobStatus {
  queued,
  running,
  completed,
  failed,
  cancelled;

  bool get isActive => this == queued || this == running;
  bool get isFinished => !isActive;
}

/// A unit of background work any toolbox module can hand to the [JobQueue].
abstract class JobSpec {
  String get title;
  String get toolId;
  List<String> get inputs;

  /// Files or folders this job produces (for open / reveal).
  List<String> get outputs;

  /// Copyable equivalent command, if the job has one.
  String? get commandLine => null;

  /// Runs the job. Throw [JobFailure] with a user-facing message on error.
  /// Must return promptly (throwing [JobCancelled]) after [JobContext.cancelled].
  Future<void> run(JobContext context);
}

class JobFailure implements Exception {
  const JobFailure(this.message, {this.key, this.args = const {}});

  /// Raw (untranslated) explanation, e.g. ffmpeg's error line.
  final String message;

  /// Optional translation key + named args for a friendlier message.
  final String? key;
  final Map<String, String> args;
  @override
  String toString() => message;
}

class JobCancelled implements Exception {
  const JobCancelled();
}

class JobProgress {
  const JobProgress({
    this.fraction,
    this.speed,
    this.fps,
    this.processed,
    this.stepLabel,
  });

  /// 0..1, or null when indeterminate.
  final double? fraction;
  final double? speed;
  final double? fps;
  final Duration? processed;
  final String? stepLabel;
}

/// Handed to a running [JobSpec] to report progress and observe cancellation.
class JobContext {
  JobContext({required this.onProgress, required this.log});

  final void Function(JobProgress progress) onProgress;
  final void Function(String line) log;
  final _cancel = Completer<void>();

  bool get isCancelled => _cancel.isCompleted;
  Future<void> get cancelled => _cancel.future;

  void cancel() {
    if (!_cancel.isCompleted) _cancel.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const JobCancelled();
  }
}

/// Bounded log buffer kept outside of Riverpod state so that log lines don't
/// rebuild every task row.
class JobLog extends ChangeNotifier {
  JobLog({this.capacity = 2000});
  final int capacity;
  final List<String> _lines = [];

  List<String> get lines => List.unmodifiable(_lines);

  void add(String line) {
    _lines.add(line);
    if (_lines.length > capacity) _lines.removeRange(0, _lines.length - capacity);
    notifyListeners();
  }

  @override
  String toString() => _lines.join('\n');
}

@immutable
class Job {
  const Job({
    required this.id,
    required this.spec,
    required this.createdAt,
    this.status = JobStatus.queued,
    this.progress = const JobProgress(),
    this.startedAt,
    this.finishedAt,
    this.error,
    this.errorKey,
    this.errorArgs = const {},
  });

  final int id;
  final JobSpec spec;
  final JobStatus status;
  final JobProgress progress;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? error;
  final String? errorKey;
  final Map<String, String> errorArgs;

  Duration? get elapsed {
    final start = startedAt;
    if (start == null) return null;
    return (finishedAt ?? DateTime.now()).difference(start);
  }

  /// Linear ETA from elapsed time and fraction done.
  Duration? get eta {
    final f = progress.fraction;
    final e = elapsed;
    if (status != JobStatus.running || f == null || e == null || f < 0.02) {
      return null;
    }
    return Duration(milliseconds: (e.inMilliseconds * (1 - f) / f).round());
  }

  Job copyWith({
    JobStatus? status,
    JobProgress? progress,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? error,
    String? errorKey,
    Map<String, String>? errorArgs,
  }) {
    return Job(
      id: id,
      spec: spec,
      createdAt: createdAt,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      error: error ?? this.error,
      errorKey: errorKey ?? this.errorKey,
      errorArgs: errorArgs ?? this.errorArgs,
    );
  }
}
