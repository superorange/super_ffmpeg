import 'dart:io';

/// Desktop integrations: reveal in Finder/Explorer, open with default app.
abstract final class PlatformActions {
  static Future<void> reveal(String path) async {
    final target = FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound ? File(path).parent.path : path;
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', target]);
    } else if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', target]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [File(target).parent.path]);
    }
  }

  static Future<void> open(String path) async {
    if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    }
  }
}
