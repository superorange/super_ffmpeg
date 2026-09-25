import 'package:flutter/foundation.dart';

enum EpochUnit { seconds, milliseconds, microseconds, nanoseconds }

@immutable
class ParsedTime {
  const ParsedTime(this.time, this.source);
  final DateTime time;

  /// How the input was understood (e.g. "unix seconds", "ISO 8601").
  final String source;
}

abstract final class TimeTools {
  /// Understands unix timestamps (unit guessed by magnitude), ISO 8601,
  /// RFC 2822-ish dates and `yyyy-MM-dd HH:mm:ss`.
  static ParsedTime? parse(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s)) {
      final v = double.parse(s);
      final abs = v.abs();
      final (unit, micros) = abs >= 1e17
          ? (EpochUnit.nanoseconds, v / 1000)
          : abs >= 1e14
          ? (EpochUnit.microseconds, v)
          : abs >= 1e11
          ? (EpochUnit.milliseconds, v * 1000)
          : (EpochUnit.seconds, v * 1e6);
      return ParsedTime(DateTime.fromMicrosecondsSinceEpoch(micros.round(), isUtc: true), 'unix:${unit.name}');
    }
    final iso = DateTime.tryParse(s);
    if (iso != null) return ParsedTime(iso, 'iso');
    final rfc = _parseRfc2822(s);
    if (rfc != null) return ParsedTime(rfc, 'rfc2822');
    return null;
  }

  static const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static DateTime? _parseRfc2822(String s) {
    final m = RegExp(
      r'^(?:\w{3},\s*)?(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d\d):(\d\d)(?::(\d\d))?\s*(GMT|UTC|Z|[+-]\d{4})?$',
      caseSensitive: false,
    ).firstMatch(s);
    if (m == null) return null;
    final month = _months.indexOf(m[2]!.toLowerCase());
    if (month < 0) return null;
    var t = DateTime.utc(
      int.parse(m[3]!),
      month + 1,
      int.parse(m[1]!),
      int.parse(m[4]!),
      int.parse(m[5]!),
      int.parse(m[6] ?? '0'),
    );
    final zone = m[7];
    if (zone != null && (zone.startsWith('+') || zone.startsWith('-'))) {
      final sign = zone.startsWith('-') ? -1 : 1;
      final offset = Duration(hours: int.parse(zone.substring(1, 3)), minutes: int.parse(zone.substring(3)));
      t = t.subtract(offset * sign);
    }
    return t;
  }

  static String two(int v) => v.toString().padLeft(2, '0');

  static String offsetOf(DateTime t) {
    final o = t.timeZoneOffset;
    final sign = o.isNegative ? '-' : '+';
    final a = o.abs();
    return '$sign${two(a.inHours)}:${two(a.inMinutes.remainder(60))}';
  }

  /// `2026-09-25T13:26:00.000+08:00`
  static String iso(DateTime t) {
    if (t.isUtc) return t.toIso8601String();
    final base = t.toIso8601String();
    return '$base${offsetOf(t)}';
  }

  /// `Fri, 25 Sep 2026 05:26:00 GMT`
  static String rfc2822(DateTime t) {
    final u = t.toUtc();
    final m = _months[u.month - 1];
    return '${_days[u.weekday - 1]}, ${two(u.day)} ${m[0].toUpperCase()}${m.substring(1)} ${u.year} '
        '${two(u.hour)}:${two(u.minute)}:${two(u.second)} GMT';
  }

  static String dateTime(DateTime t) =>
      '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';

  /// "3 hours ago" / "in 2 days" — returns (value, unit, future).
  static (int, String, bool) relative(DateTime t, [DateTime? now]) {
    final diff = t.difference(now ?? DateTime.now());
    final future = !diff.isNegative;
    final a = diff.abs();
    if (a.inSeconds < 60) return (a.inSeconds, 'seconds', future);
    if (a.inMinutes < 60) return (a.inMinutes, 'minutes', future);
    if (a.inHours < 24) return (a.inHours, 'hours', future);
    if (a.inDays < 30) return (a.inDays, 'days', future);
    if (a.inDays < 365) return (a.inDays ~/ 30, 'months', future);
    return (a.inDays ~/ 365, 'years', future);
  }

  /// ISO week number.
  static int isoWeek(DateTime t) {
    final d = DateTime.utc(t.year, t.month, t.day);
    final thursday = d.add(Duration(days: 4 - (d.weekday)));
    final firstDay = DateTime.utc(thursday.year, 1, 1);
    return (thursday.difference(firstDay).inDays ~/ 7) + 1;
  }

  static int dayOfYear(DateTime t) => DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(t.year)).inDays + 1;
}

/// Standard 5-field cron (`min hour dom month dow`) with lists, ranges,
/// steps, names (`JAN`, `MON`), `?` and the `@daily`-style macros.
class CronExpression {
  CronExpression._(
    this.source,
    this.minutes,
    this.hours,
    this.days,
    this.months,
    this.weekdays,
    this._domStar,
    this._dowStar,
  );

  final String source;
  final Set<int> minutes;
  final Set<int> hours;
  final Set<int> days;
  final Set<int> months;
  final Set<int> weekdays; // 0 = Sunday
  final bool _domStar;
  final bool _dowStar;

  static const macros = {
    '@yearly': '0 0 1 1 *',
    '@annually': '0 0 1 1 *',
    '@monthly': '0 0 1 * *',
    '@weekly': '0 0 * * 0',
    '@daily': '0 0 * * *',
    '@midnight': '0 0 * * *',
    '@hourly': '0 * * * *',
  };

  static const _monthNames = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  static const _dayNames = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

  factory CronExpression.parse(String input) {
    var s = input.trim();
    s = macros[s.toLowerCase()] ?? s;
    final f = s.split(RegExp(r'\s+'));
    if (f.length == 6) f.removeAt(0); // tolerate a leading seconds field
    if (f.length != 5) throw const FormatException('Cron needs 5 fields: minute hour day month weekday');
    final dow = _field(f[4], 0, 7, names: _dayNames).map((d) => d % 7).toSet();
    return CronExpression._(
      input.trim(),
      _field(f[0], 0, 59),
      _field(f[1], 0, 23),
      _field(f[2], 1, 31),
      _field(f[3], 1, 12, names: _monthNames, nameBase: 1),
      dow,
      f[2] == '*' || f[2] == '?',
      f[4] == '*' || f[4] == '?',
    );
  }

  static Set<int> _field(String text, int min, int max, {List<String>? names, int nameBase = 0}) {
    int value(String t) {
      final upper = t.toUpperCase();
      if (names != null) {
        final i = names.indexOf(upper);
        if (i >= 0) return i + nameBase;
      }
      final v = int.tryParse(t);
      if (v == null || v < min || v > max) throw FormatException('Invalid value "$t" (allowed $min–$max)');
      return v;
    }

    final out = <int>{};
    for (final part in text.split(',')) {
      final stepParts = part.split('/');
      if (stepParts.length > 2) throw FormatException('Invalid step "$part"');
      final step = stepParts.length == 2 ? int.tryParse(stepParts[1]) : 1;
      if (step == null || step <= 0) throw FormatException('Invalid step "$part"');
      final range = stepParts[0];
      int lo, hi;
      if (range == '*' || range == '?') {
        lo = min;
        hi = max;
      } else if (range.contains('-')) {
        final r = range.split('-');
        lo = value(r[0]);
        hi = value(r[1]);
        if (lo > hi) throw FormatException('Invalid range "$range"');
      } else {
        lo = value(range);
        hi = stepParts.length == 2 ? max : lo;
      }
      for (var v = lo; v <= hi; v += step) {
        out.add(v);
      }
    }
    return out;
  }

  bool _dayMatches(DateTime t) {
    final dom = days.contains(t.day);
    final dow = weekdays.contains(t.weekday % 7);
    // POSIX: when both day fields are restricted, either may match.
    if (_domStar && _dowStar) return true;
    if (_domStar) return dow;
    if (_dowStar) return dom;
    return dom || dow;
  }

  /// Next [count] run times strictly after [from] (local time).
  List<DateTime> next(int count, {DateTime? from}) {
    final out = <DateTime>[];
    var t = (from ?? DateTime.now());
    t = DateTime(t.year, t.month, t.day, t.hour, t.minute).add(const Duration(minutes: 1));
    final limit = t.add(const Duration(days: 366 * 5));
    while (out.length < count && t.isBefore(limit)) {
      if (!months.contains(t.month)) {
        t = DateTime(t.year, t.month + 1);
        continue;
      }
      if (!_dayMatches(t)) {
        t = DateTime(t.year, t.month, t.day + 1);
        continue;
      }
      if (!hours.contains(t.hour)) {
        t = DateTime(t.year, t.month, t.day, t.hour + 1);
        continue;
      }
      if (!minutes.contains(t.minute)) {
        t = t.add(const Duration(minutes: 1));
        continue;
      }
      out.add(t);
      t = t.add(const Duration(minutes: 1));
    }
    return out;
  }
}
