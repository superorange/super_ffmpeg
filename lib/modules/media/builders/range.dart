import '../../../core/utils/format.dart';
import '../engine/command_plan.dart';

/// Restricts every step of [plan] to `start … start+length` of [input] by
/// input-seeking (`-ss` / `-t` before `-i`). With re-encoding, input seeking
/// is frame-accurate in modern FFmpeg, so any tool can work on a selection.
CommandPlan applyClipRange(
  CommandPlan plan, {
  required String input,
  required Duration start,
  required Duration length,
}) {
  if (length <= Duration.zero) throw const PlanException('media.errors.invalid_range');
  final seek = [
    if (start > Duration.zero) ...['-ss', Fmt.seconds(start)],
    '-t',
    Fmt.seconds(length),
  ];
  final steps = [
    for (final step in plan.steps) FfmpegStep(_insertBeforeInput(step.args, input, seek), label: step.label),
  ];
  return CommandPlan(
    steps: steps,
    outputs: plan.outputs,
    expectedDuration: plan.expectedDuration == null || plan.expectedDuration! > length ? length : plan.expectedDuration,
    auxFiles: plan.auxFiles,
    createDirs: plan.createDirs,
    scratchPrefixes: plan.scratchPrefixes,
    cleanupOnFailure: plan.cleanupOnFailure,
    maxOutputBytes: plan.maxOutputBytes,
  );
}

List<String> _insertBeforeInput(List<String> args, String input, List<String> seek) {
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '-i' && args[i + 1] == input) {
      return [...args.sublist(0, i), ...seek, ...args.sublist(i)];
    }
  }
  return args;
}
