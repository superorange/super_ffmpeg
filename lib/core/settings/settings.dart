import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loaded in `main()` and injected with an override so settings are
/// available synchronously.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.ffmpegDir,
    this.outputDir,
    this.concurrency = 2,
    this.preferGpu = true,
    this.recentTools = const [],
  });

  final ThemeMode themeMode;

  /// Folder containing ffmpeg/ffprobe; null = auto-detect.
  final String? ffmpegDir;

  /// Where results go; null = next to the source file.
  final String? outputDir;
  final int concurrency;
  final bool preferGpu;
  final List<String> recentTools;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? Function()? ffmpegDir,
    String? Function()? outputDir,
    int? concurrency,
    bool? preferGpu,
    List<String>? recentTools,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      ffmpegDir: ffmpegDir != null ? ffmpegDir() : this.ffmpegDir,
      outputDir: outputDir != null ? outputDir() : this.outputDir,
      concurrency: concurrency ?? this.concurrency,
      preferGpu: preferGpu ?? this.preferGpu,
      recentTools: recentTools ?? this.recentTools,
    );
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  static const _kTheme = 'theme_mode';
  static const _kFfmpegDir = 'ffmpeg_dir';
  static const _kOutputDir = 'output_dir';
  static const _kConcurrency = 'concurrency';
  static const _kPreferGpu = 'prefer_gpu';
  static const _kRecent = 'recent_tools';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AppSettings(
      themeMode: ThemeMode.values.asNameMap()[prefs.getString(_kTheme)] ?? ThemeMode.system,
      ffmpegDir: prefs.getString(_kFfmpegDir),
      outputDir: prefs.getString(_kOutputDir),
      concurrency: (prefs.getInt(_kConcurrency) ?? 2).clamp(1, 4),
      preferGpu: prefs.getBool(_kPreferGpu) ?? true,
      recentTools: prefs.getStringList(_kRecent) ?? const [],
    );
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _prefs.setString(_kTheme, mode.name);
  }

  void setFfmpegDir(String? dir) {
    state = state.copyWith(ffmpegDir: () => dir);
    dir == null ? _prefs.remove(_kFfmpegDir) : _prefs.setString(_kFfmpegDir, dir);
  }

  void setOutputDir(String? dir) {
    state = state.copyWith(outputDir: () => dir);
    dir == null ? _prefs.remove(_kOutputDir) : _prefs.setString(_kOutputDir, dir);
  }

  void setConcurrency(int value) {
    state = state.copyWith(concurrency: value.clamp(1, 4));
    _prefs.setInt(_kConcurrency, state.concurrency);
  }

  void setPreferGpu(bool value) {
    state = state.copyWith(preferGpu: value);
    _prefs.setBool(_kPreferGpu, value);
  }

  void markToolUsed(String toolId) {
    final recent = [toolId, ...state.recentTools.where((t) => t != toolId)].take(6).toList();
    state = state.copyWith(recentTools: recent);
    _prefs.setStringList(_kRecent, recent);
  }
}
