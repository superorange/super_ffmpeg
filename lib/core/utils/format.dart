/// Human-readable formatting and parsing helpers shared by every module.
abstract final class Fmt {
  static String bytes(int bytes, {int decimals = 1}) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    return i == 0 ? '$bytes B' : '${value.toStringAsFixed(decimals)} ${units[i]}';
  }

  static String bitrate(int bps) {
    if (bps <= 0) return '—';
    if (bps >= 1000000) return '${(bps / 1000000).toStringAsFixed(1)} Mbps';
    return '${(bps / 1000).round()} kbps';
  }

  /// `1:02:03` / `02:03` — for display of media lengths.
  static String duration(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// `00:01:02.500` — lossless timecode used for inputs and ffmpeg args.
  static String timecode(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = d.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  /// `1:02.5` / `1:02:03.5` — compact position with tenths, for chips and
  /// timeline labels.
  static String shortTime(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final t = d.inMilliseconds.remainder(1000) ~/ 100;
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s.$t' : '$m:$s.$t';
  }

  /// Seconds with millisecond precision for ffmpeg (`-ss 12.345`).
  static String seconds(Duration d) {
    final ms = d.inMilliseconds;
    final whole = ms ~/ 1000;
    final frac = ms.remainder(1000);
    return frac == 0 ? '$whole' : '$whole.${frac.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
  }

  /// Parses `90`, `90.5`, `1:30`, `01:30.25`, `1:02:03.5`. Returns null when invalid.
  static Duration? parseTimecode(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final parts = text.split(':');
    if (parts.length > 3) return null;
    double total = 0;
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final isLast = i == parts.length - 1;
      final valid = isLast ? RegExp(r'^\d+(\.\d+)?$').hasMatch(part) : RegExp(r'^\d+$').hasMatch(part);
      if (!valid) return null;
      final value = double.parse(part);
      if (i > 0 && value >= 60) return null;
      total = total * 60 + value;
    }
    return Duration(microseconds: (total * 1000000).round());
  }

  /// Rough "3m 12s" style for ETAs.
  static String eta(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    return '${d.inSeconds}s';
  }
}
