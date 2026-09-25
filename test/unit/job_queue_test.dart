import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_ffmpeg/core/jobs/job.dart';
import 'package:super_ffmpeg/core/jobs/job_queue.dart';
import 'package:super_ffmpeg/core/settings/settings.dart';

/// A job whose completion the test controls.
class FakeJob extends JobSpec {
  FakeJob(this.title, {this.fail = false});

  @override
  final String title;
  final bool fail;
  final started = Completer<JobContext>();
  final finish = Completer<void>();
  int runs = 0;

  @override
  String get toolId => 'fake';
  @override
  List<String> get inputs => const [];
  @override
  List<String> get outputs => const [];

  @override
  Future<void> run(JobContext context) async {
    runs++;
    if (!started.isCompleted) started.complete(context);
    context.onProgress(const JobProgress(fraction: 0.5));
    context.log('working');
    await Future.any([finish.future, context.cancelled]);
    context.throwIfCancelled();
    if (fail) throw const JobFailure('boom', key: 'media.errors.no_audio');
  }
}

Future<ProviderContainer> _container({int concurrency = 1}) async {
  SharedPreferences.setMockInitialValues({'concurrency': concurrency});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
  addTearDown(container.dispose);
  return container;
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('respects concurrency and runs jobs oldest-first', () async {
    final c = await _container(concurrency: 1);
    final queue = c.read(jobQueueProvider.notifier);
    final a = FakeJob('a'), b = FakeJob('b');
    queue.enqueueAll([a, b]);
    await _settle();

    List<Job> jobs() => c.read(jobQueueProvider);
    expect(jobs().map((j) => j.spec.title), ['b', 'a'], reason: 'newest first in the list');
    expect(jobs().firstWhere((j) => j.spec == a).status, JobStatus.running);
    expect(jobs().firstWhere((j) => j.spec == b).status, JobStatus.queued);
    expect(jobs().firstWhere((j) => j.spec == a).progress.fraction, 0.5);
    expect(queue.logOf(jobs().firstWhere((j) => j.spec == a).id).lines, ['working']);

    a.finish.complete();
    await _settle();
    await _settle();
    expect(jobs().firstWhere((j) => j.spec == a).status, JobStatus.completed);
    expect(jobs().firstWhere((j) => j.spec == a).progress.fraction, 1.0);
    expect(jobs().firstWhere((j) => j.spec == b).status, JobStatus.running);
  });

  test('raising concurrency starts waiting jobs immediately', () async {
    final c = await _container(concurrency: 1);
    final queue = c.read(jobQueueProvider.notifier);
    final jobs = [FakeJob('1'), FakeJob('2'), FakeJob('3')];
    queue.enqueueAll(jobs);
    await _settle();
    expect(c.read(jobQueueProvider).where((j) => j.status == JobStatus.running), hasLength(1));
    c.read(settingsProvider.notifier).setConcurrency(3);
    await _settle();
    expect(c.read(jobQueueProvider).where((j) => j.status == JobStatus.running), hasLength(3));
  });

  test('cancel works for queued and running jobs', () async {
    final c = await _container();
    final queue = c.read(jobQueueProvider.notifier);
    final a = FakeJob('a'), b = FakeJob('b');
    final ids = queue.enqueueAll([a, b]);
    await _settle();

    queue.cancel(ids[1]); // queued
    expect(c.read(jobQueueProvider).firstWhere((j) => j.id == ids[1]).status, JobStatus.cancelled);

    queue.cancel(ids[0]); // running
    await _settle();
    await _settle();
    expect(c.read(jobQueueProvider).firstWhere((j) => j.id == ids[0]).status, JobStatus.cancelled);
    expect(b.runs, 0, reason: 'cancelled while queued, never started');
  });

  test('failures keep message + translation key; retry re-enqueues the same spec', () async {
    final c = await _container();
    final queue = c.read(jobQueueProvider.notifier);
    final job = FakeJob('x', fail: true)..finish.complete();
    final id = queue.enqueueAll([job]).single;
    await _settle();
    await _settle();

    final failed = c.read(jobQueueProvider).single;
    expect(failed.status, JobStatus.failed);
    expect(failed.error, 'boom');
    expect(failed.errorKey, 'media.errors.no_audio');

    final retryId = queue.retry(id)!;
    await _settle();
    expect(retryId, isNot(id));
    expect(job.runs, 2);
    expect(c.read(jobQueueProvider).map((j) => j.id), [retryId]);
  });

  test('clearFinished keeps active jobs', () async {
    final c = await _container(concurrency: 2);
    final queue = c.read(jobQueueProvider.notifier);
    final done = FakeJob('done')..finish.complete();
    final running = FakeJob('running');
    queue.enqueueAll([done, running]);
    await _settle();
    await _settle();
    queue.clearFinished();
    expect(c.read(jobQueueProvider).map((j) => j.spec.title), ['running']);
  });

  test('eta extrapolates from elapsed time', () {
    final job = Job(
      id: 1,
      spec: FakeJob('x'),
      createdAt: DateTime.now(),
      status: JobStatus.running,
      startedAt: DateTime.now().subtract(const Duration(seconds: 10)),
      progress: const JobProgress(fraction: 0.25),
    );
    expect(job.eta!.inSeconds, inInclusiveRange(29, 31));
  });
}
