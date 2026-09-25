import 'package:path/path.dart' as p;

import '../../../core/utils/shell_words.dart';
import '../engine/command_plan.dart';
import '../engine/media_info.dart';

class CliTemplate {
  const CliTemplate(this.labelKey, this.args);
  final String labelKey;
  final String args;
}

const cliTemplates = [
  CliTemplate('media.cli.tpl_remux', '-i {input} -c copy {dir}/{name}_remux.mkv'),
  CliTemplate('media.cli.tpl_reverse', '-i {input} -vf reverse -af areverse {dir}/{name}_reversed.mp4'),
  CliTemplate('media.cli.tpl_denoise', '-i {input} -vf hqdn3d=4:3:6:4 -c:a copy {dir}/{name}_denoised.mp4'),
  CliTemplate('media.cli.tpl_subs', '-i {input} -map 0:s:0 {dir}/{name}.srt'),
  CliTemplate(
    'media.cli.tpl_waveform',
    '-i {input} -filter_complex showwavespic=s=1600x400:colors=0x8B7CF6 -frames:v 1 {dir}/{name}_waveform.png',
  ),
  CliTemplate('media.cli.tpl_stabilize', '-i {input} -vf deshake -c:a copy {dir}/{name}_stable.mp4'),
];

/// Placeholders: `{input}` full path, `{dir}` folder, `{name}` base name
/// without extension. Substitution happens after tokenizing, so paths with
/// spaces or quotes stay a single argument.
List<String> expandCliArgs(String template, {String? input}) {
  final tokens = ShellWords.split(template.trim());
  if (tokens.isNotEmpty && (tokens.first == 'ffmpeg' || tokens.first.endsWith('/ffmpeg'))) {
    tokens.removeAt(0);
  }
  if (input == null) return tokens;
  final values = {
    '{input}': input,
    '{dir}': p.dirname(input),
    '{name}': p.basenameWithoutExtension(input),
  };
  return [
    for (final t in tokens) values.entries.fold(t, (acc, e) => acc.replaceAll(e.key, e.value)),
  ];
}

bool cliUsesInput(String template) => template.contains('{input}');

CommandPlan buildCli({required String template, String? input, MediaInfo? info}) {
  final List<String> args;
  try {
    args = expandCliArgs(template, input: input);
  } on FormatException {
    throw const PlanException('media.errors.bad_quotes');
  }
  if (args.isEmpty) throw const PlanException('media.errors.empty_command');
  if (!args.contains('-y') && !args.contains('-n')) args.insert(0, '-n');
  return CommandPlan(
    steps: [FfmpegStep(args)],
    // Last non-option argument is conventionally the output.
    outputs: [if (args.length > 1 && !args.last.startsWith('-')) args.last],
    expectedDuration: info?.duration,
    cleanupOnFailure: false,
  );
}
