import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings.dart';
import 'job.dart';

final jobQueueProvider = NotifierProvider<JobQueue, List<Job>>(JobQueue.new);

/// Toolbox-wide background job queue. Newest jobs first.
class JobQueue extends Notifier<List<Job>> {
  int _nextId = 1;
  final _contexts = <int, JobContext>{};
  final _logs = <int, JobLog>{};

  @override
  List<Job> build() {
    // Re-evaluate the queue when concurrency changes.
    ref.listen(settingsProvider.select((s) => s.concurrency), (_, _) => _pump());
    ref.onDispose(() {
      for (final c in _contexts.values) {
        c.cancel();
      }
    });
    return const [];
  }

  JobLog logOf(int id) => _logs.putIfAbsent(id, JobLog.new);

  List<int> enqueueAll(List<JobSpec> specs) {
    final now = DateTime.now();
    final jobs = [
      for (final spec in specs) Job(id: _nextId++, spec: spec, createdAt: now),
    ];
    state = [...jobs.reversed, ...state];
    _pump();
    return [for (final j in jobs) j.id];
  }

  void cancel(int id) {
    final job = _find(id);
    if (job == null || job.status.isFinished) return;
    if (job.status == JobStatus.queued) {
      _update(
        id,
        (j) => j.copyWith(
          status: JobStatus.cancelled,
          finishedAt: DateTime.now(),
        ),
      );
    } else {
      _contexts[id]?.cancel();
    }
  }

  void cancelAll() {
    for (final job in state.where((j) => j.status.isActive)) {
      cancel(job.id);
    }
  }

  int? retry(int id) {
    final job = _find(id);
    if (job == null || job.status.isActive) return null;
    remove(id);
    return enqueueAll([job.spec]).single;
  }

  void remove(int id) {
    final job = _find(id);
    if (job == null || job.status.isActive) return;
    _logs.remove(id)?.dispose();
    state = [
      for (final j in state)
        if (j.id != id) j,
    ];
  }

  void clearFinished() {
    for (final j in state.where((j) => j.status.isFinished)) {
      _logs.remove(j.id)?.dispose();
    }
    state = [
      for (final j in state)
        if (j.status.isActive) j,
    ];
  }

  void _pump() {
    final limit = ref.read(settingsProvider).concurrency;
    var running = state.where((j) => j.status == JobStatus.running).length;
    // Oldest queued job first (state is newest-first).
    for (final job in state.reversed.toList()) {
      if (running >= limit) break;
      if (job.status != JobStatus.queued) continue;
      running++;
      _start(job);
    }
  }

  Future<void> _start(Job job) async {
    final id = job.id;
    final log = logOf(id);
    final context = JobContext(
      log: log.add,
      onProgress: (p) {
        final current = _find(id);
        if (current?.status == JobStatus.running) {
          _update(id, (j) => j.copyWith(progress: p));
        }
      },
    );
    _contexts[id] = context;
    _update(
      id,
      (j) => j.copyWith(
        status: JobStatus.running,
        startedAt: DateTime.now(),
      ),
    );

    JobStatus result;
    String? error;
    String? errorKey;
    var errorArgs = const <String, String>{};
    try {
      await job.spec.run(context);
      result = context.isCancelled ? JobStatus.cancelled : JobStatus.completed;
    } on JobCancelled {
      result = JobStatus.cancelled;
    } on JobFailure catch (e) {
      result = context.isCancelled ? JobStatus.cancelled : JobStatus.failed;
      error = e.message;
      errorKey = e.key;
      errorArgs = e.args;
    } catch (e) {
      result = context.isCancelled ? JobStatus.cancelled : JobStatus.failed;
      error = e.toString();
    }
    _contexts.remove(id);
    if (!ref.mounted) return;

    _update(
      id,
      (j) => j.copyWith(
        status: result,
        finishedAt: DateTime.now(),
        error: error,
        errorKey: errorKey,
        errorArgs: errorArgs,
        progress: result == JobStatus.completed
            ? JobProgress(
                fraction: 1,
                speed: j.progress.speed,
                fps: j.progress.fps,
                processed: j.progress.processed,
              )
            : j.progress,
      ),
    );
    _pump();
  }

  Job? _find(int id) {
    for (final j in state) {
      if (j.id == id) return j;
    }
    return null;
  }

  void _update(int id, Job Function(Job) change) {
    state = [
      for (final j in state)
        if (j.id == id) change(j) else j,
    ];
  }
}
