import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

/// Files handed to a tool from outside it — e.g. dropped on the home page.
/// A tool page picks up its pending files when it opens (or immediately if
/// it's already open).
class FileIntake extends ChangeNotifier {
  FileIntake._();
  static final instance = FileIntake._();

  final _pending = <String, List<String>>{};

  void offer(String toolId, List<String> paths) {
    _pending[toolId] = paths;
    notifyListeners();
  }

  List<String>? take(String toolId) => _pending.remove(toolId);

  /// Reads a dropped file as text (UTF-8, falling back to Latin-1).
  /// Returns null for files that are too large or clearly binary.
  static Future<String?> readText(String path, {int maxBytes = 20 * 1024 * 1024}) async {
    final file = File(path);
    if (await file.length() > maxBytes) return null;
    final bytes = await file.readAsBytes();
    if (bytes.take(8000).contains(0)) return null;
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }
}

/// Lets a tool page receive files from [FileIntake] under [intakeId].
mixin FileIntakeMixin<T extends StatefulWidget> on State<T> {
  String get intakeId;
  void onFiles(List<String> paths);

  @override
  void initState() {
    super.initState();
    FileIntake.instance.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    FileIntake.instance.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (!mounted) return;
    final paths = FileIntake.instance.take(intakeId);
    if (paths != null && paths.isNotEmpty) onFiles(paths);
  }
}
