/// One block of `ffmpeg -progress pipe:1` output.
class FfmpegProgress {
  const FfmpegProgress({
    this.outTime,
    this.fps,
    this.speed,
    this.frame,
    this.totalSize,
    this.done = false,
  });

  final Duration? outTime;
  final double? fps;
  final double? speed;
  final int? frame;
  final int? totalSize;
  final bool done;

  /// Fraction of [expected] processed, clamped to 0..1; null if unknown.
  double? fractionOf(Duration? expected) {
    final t = outTime;
    if (done) return 1;
    if (t == null || expected == null || expected <= Duration.zero) return null;
    return (t.inMicroseconds / expected.inMicroseconds).clamp(0.0, 1.0);
  }
}

/// Incremental parser for `key=value` progress lines. A block ends with
/// `progress=continue` or `progress=end`.
class FfmpegProgressParser {
  final _values = <String, String>{};

  /// Returns a snapshot when [line] completes a block, otherwise null.
  FfmpegProgress? add(String line) {
    final eq = line.indexOf('=');
    if (eq <= 0) return null;
    final key = line.substring(0, eq).trim();
    final value = line.substring(eq + 1).trim();
    if (key != 'progress') {
      _values[key] = value;
      return null;
    }
    final snapshot = FfmpegProgress(
      outTime: _outTime(),
      fps: double.tryParse(_values['fps'] ?? ''),
      speed: double.tryParse((_values['speed'] ?? '').replaceAll('x', '')),
      frame: int.tryParse(_values['frame'] ?? ''),
      totalSize: int.tryParse(_values['total_size'] ?? ''),
      done: value == 'end',
    );
    _values.clear();
    return snapshot;
  }

  Duration? _outTime() {
    // out_time_ms is (historically) also microseconds.
    for (final key in ['out_time_us', 'out_time_ms']) {
      final us = int.tryParse(_values[key] ?? '');
      if (us != null && us >= 0) return Duration(microseconds: us);
    }
    final text = _values['out_time'];
    if (text != null) {
      final m = RegExp(r'^(\d+):(\d{2}):(\d{2}(?:\.\d+)?)$').firstMatch(text);
      if (m != null) {
        final secs = int.parse(m[1]!) * 3600 + int.parse(m[2]!) * 60 + double.parse(m[3]!);
        return Duration(microseconds: (secs * 1000000).round());
      }
    }
    return null;
  }
}
