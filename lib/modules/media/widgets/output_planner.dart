import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../../../core/utils/file_naming.dart';

/// Plans collision-free output paths for one batch of jobs.
class OutputPlanner {
  OutputPlanner({this.outputDir, this._exists});

  /// null = next to each source file.
  final String? outputDir;
  final bool Function(String path)? _exists;
  final _reserved = <String>{};
  static final _rand = Random();

  String file(String input, {required String extension, String suffix = ''}) {
    final path = FileNaming.unique(
      FileNaming.derive(inputPath: input, extension: extension, suffix: suffix, outputDir: outputDir),
      reserved: _reserved,
      exists: _exists,
    );
    _reserved.add(path);
    return path;
  }

  String folder(String input, {required String suffix}) {
    final base = p.join(outputDir ?? p.dirname(input), '${p.basenameWithoutExtension(input)}_$suffix');
    final path = FileNaming.unique(base, reserved: _reserved, exists: _exists);
    _reserved.add(path);
    return path;
  }

  /// Unique scratch path in the system temp dir.
  String temp(String name) {
    final id = '${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 32)}';
    return p.join(Directory.systemTemp.path, 'super_toolbox', '${id}_$name');
  }
}
