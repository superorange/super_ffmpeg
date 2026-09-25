import 'dart:math' as math;
import 'dart:ui' show Color;

/// Colour parsing/formatting across CSS notations plus WCAG contrast.
abstract final class ColorTools {
  static const named = {
    'black': 0xFF000000,
    'white': 0xFFFFFFFF,
    'red': 0xFFFF0000,
    'green': 0xFF008000,
    'blue': 0xFF0000FF,
    'yellow': 0xFFFFFF00,
    'cyan': 0xFF00FFFF,
    'magenta': 0xFFFF00FF,
    'gray': 0xFF808080,
    'grey': 0xFF808080,
    'orange': 0xFFFFA500,
    'purple': 0xFF800080,
    'pink': 0xFFFFC0CB,
    'brown': 0xFFA52A2A,
    'navy': 0xFF000080,
    'teal': 0xFF008080,
    'olive': 0xFF808000,
    'maroon': 0xFF800000,
    'lime': 0xFF00FF00,
    'aqua': 0xFF00FFFF,
    'fuchsia': 0xFFFF00FF,
    'silver': 0xFFC0C0C0,
    'gold': 0xFFFFD700,
    'indigo': 0xFF4B0082,
    'violet': 0xFFEE82EE,
    'coral': 0xFFFF7F50,
    'salmon': 0xFFFA8072,
    'tomato': 0xFFFF6347,
    'crimson': 0xFFDC143C,
    'khaki': 0xFFF0E68C,
    'turquoise': 0xFF40E0D0,
    'orchid': 0xFFDA70D6,
    'plum': 0xFFDDA0DD,
    'tan': 0xFFD2B48C,
    'beige': 0xFFF5F5DC,
    'ivory': 0xFFFFFFF0,
    'lavender': 0xFFE6E6FA,
    'skyblue': 0xFF87CEEB,
    'steelblue': 0xFF4682B4,
    'rebeccapurple': 0xFF663399,
    'transparent': 0x00000000,
  };

  /// `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb()/rgba()`, `hsl()/hsla()`,
  /// `hsv()`, named colours, bare `rrggbb`.
  static Color? parse(String input) {
    final s = input.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (named.containsKey(s)) return Color(named[s]!);
    final hex = RegExp(r'^#?([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$').firstMatch(s);
    if (hex != null) {
      var h = hex[1]!;
      if (h.length <= 4) h = h.split('').map((c) => '$c$c').join();
      final rgb = int.parse(h.substring(0, 6), radix: 16);
      final a = h.length == 8 ? int.parse(h.substring(6), radix: 16) : 255;
      return Color((a << 24) | rgb);
    }
    final fn = RegExp(r'^(rgba?|hsla?|hsv|hsb)\(([^)]*)\)$').firstMatch(s);
    if (fn == null) return null;
    final args = fn[2]!.split(RegExp(r'[\s,/]+')).where((x) => x.isNotEmpty).toList();
    if (args.length < 3) return null;
    double num(String x, double scale) => x.endsWith('%')
        ? double.parse(x.substring(0, x.length - 1)) / 100 * scale
        : double.parse(x.replaceAll('deg', ''));
    try {
      final alpha = args.length > 3 ? num(args[3], 1).clamp(0.0, 1.0) : 1.0;
      switch (fn[1]) {
        case 'rgb' || 'rgba':
          return Color.fromARGB(
            (alpha * 255).round(),
            num(args[0], 255).round().clamp(0, 255),
            num(args[1], 255).round().clamp(0, 255),
            num(args[2], 255).round().clamp(0, 255),
          );
        case 'hsl' || 'hsla':
          return fromHsl(num(args[0], 360), num(args[1], 1), num(args[2], 1), alpha);
        default:
          return fromHsv(num(args[0], 360), num(args[1], 1), num(args[2], 1), alpha);
      }
    } on FormatException {
      return null;
    }
  }

  static int _r(Color c) => (c.r * 255).round();
  static int _g(Color c) => (c.g * 255).round();
  static int _b(Color c) => (c.b * 255).round();

  static String hex(Color c, {bool alpha = false}) {
    String h(int v) => v.toRadixString(16).padLeft(2, '0');
    final a = (c.a * 255).round();
    return '#${h(_r(c))}${h(_g(c))}${h(_b(c))}${alpha || a < 255 ? h(a) : ''}'.toUpperCase();
  }

  static String rgb(Color c) {
    final a = c.a;
    return a < 1 ? 'rgba(${_r(c)}, ${_g(c)}, ${_b(c)}, ${_trim(a)})' : 'rgb(${_r(c)}, ${_g(c)}, ${_b(c)})';
  }

  static (double, double, double) toHsl(Color c) {
    final r = c.r, g = c.g, b = c.b;
    final maxV = math.max(r, math.max(g, b)), minV = math.min(r, math.min(g, b));
    final l = (maxV + minV) / 2;
    if (maxV == minV) return (0, 0, l);
    final d = maxV - minV;
    final s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV);
    double h;
    if (maxV == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (maxV == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    return (h * 60, s, l);
  }

  static (double, double, double) toHsv(Color c) {
    final r = c.r, g = c.g, b = c.b;
    final maxV = math.max(r, math.max(g, b)), minV = math.min(r, math.min(g, b));
    final d = maxV - minV;
    final s = maxV == 0 ? 0.0 : d / maxV;
    final (h, _, _) = toHsl(c);
    return (d == 0 ? 0 : h, s, maxV);
  }

  static String hsl(Color c) {
    final (h, s, l) = toHsl(c);
    final base = '${h.round()}, ${(s * 100).round()}%, ${(l * 100).round()}%';
    return c.a < 1 ? 'hsla($base, ${_trim(c.a)})' : 'hsl($base)';
  }

  static String hsv(Color c) {
    final (h, s, v) = toHsv(c);
    return 'hsv(${h.round()}, ${(s * 100).round()}%, ${(v * 100).round()}%)';
  }

  static String cmyk(Color c) {
    final double k = 1 - math.max(c.r, math.max(c.g, c.b));
    if (k >= 1) return 'cmyk(0%, 0%, 0%, 100%)';
    int p(double x) => (x * 100).round();
    return 'cmyk(${p((1 - c.r - k) / (1 - k))}%, ${p((1 - c.g - k) / (1 - k))}%, ${p((1 - c.b - k) / (1 - k))}%, ${p(k)}%)';
  }

  static String flutter(Color c) => 'Color(0x${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()})';

  static Color fromHsl(double h, double s, double l, [double a = 1]) {
    final c = (1 - (2 * l - 1).abs()) * s;
    final hp = (h % 360) / 60;
    final x = c * (1 - (hp % 2 - 1).abs());
    final (r1, g1, b1) = switch (hp.floor()) {
      0 => (c, x, 0.0),
      1 => (x, c, 0.0),
      2 => (0.0, c, x),
      3 => (0.0, x, c),
      4 => (x, 0.0, c),
      _ => (c, 0.0, x),
    };
    final m = l - c / 2;
    return Color.from(
      alpha: a,
      red: (r1 + m).clamp(0.0, 1.0),
      green: (g1 + m).clamp(0.0, 1.0),
      blue: (b1 + m).clamp(0.0, 1.0),
    );
  }

  static Color fromHsv(double h, double s, double v, [double a = 1]) {
    final l = v * (1 - s / 2);
    final sl = (l == 0 || l == 1) ? 0.0 : (v - l) / math.min(l, 1 - l);
    return fromHsl(h, sl, l, a);
  }

  static double luminance(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  /// WCAG 2.x contrast ratio (1–21).
  static double contrast(Color a, Color b) {
    final la = luminance(a), lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// 5 tints (lighter) then 5 shades (darker) around [c].
  static List<Color> scale(Color c) {
    final (h, s, l) = toHsl(c);
    return [
      for (var i = 5; i >= 1; i--) fromHsl(h, s, l + (1 - l) * i / 6),
      c,
      for (var i = 1; i <= 5; i++) fromHsl(h, s, l * (1 - i / 6)),
    ];
  }

  static String _trim(double v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

/// Small, dependency-free CSS formatter/minifier (keeps strings and comments
/// intact, understands nested at-rules).
abstract final class CssTools {
  static String format(String css, {int indent = 2}) {
    final pad = ' ' * indent;
    final out = StringBuffer();
    var level = 0;
    var line = StringBuffer();
    String declaration(String decl) {
      final colon = decl.indexOf(':');
      return colon > 0 && !decl.startsWith('@')
          ? '${decl.substring(0, colon).trim()}: ${decl.substring(colon + 1).trim()}'
          : decl;
    }

    void flushLine({bool asDeclaration = false}) {
      final t = line.toString().trim();
      if (t.isNotEmpty) out.writeln('${pad * level}${asDeclaration ? '${declaration(t)};' : t}');
      line = StringBuffer();
    }

    final tokens = _tokens(css);
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.startsWith('/*')) {
        flushLine();
        out.writeln('${pad * level}$t');
      } else if (t == '{') {
        final sel = line.toString().trim().replaceAll(RegExp(r'\s*,\s*'), ', ').replaceAll(RegExp(r'\s+'), ' ');
        line = StringBuffer();
        out.writeln('${pad * level}$sel {');
        level++;
      } else if (t == '}') {
        flushLine(asDeclaration: true);
        level = math.max(0, level - 1);
        out.writeln('${pad * level}}');
        if (level == 0) out.writeln();
      } else if (t == ';') {
        final decl = line.toString().trim();
        line = StringBuffer();
        out.writeln('${pad * level}${declaration(decl)};');
      } else {
        line.write(t);
      }
    }
    flushLine();
    return '${out.toString().trimRight()}\n';
  }

  static String minify(String css) {
    final out = StringBuffer();
    for (final t in _tokens(css)) {
      if (t.startsWith('/*')) continue;
      if (t == '{' || t == '}' || t == ';') {
        var s = out.toString().trimRight();
        if (t == '}' && s.endsWith(';')) s = s.substring(0, s.length - 1);
        out
          ..clear()
          ..write(s)
          ..write(t);
      } else if (t.startsWith('"') || t.startsWith("'")) {
        out.write(t);
      } else {
        final collapsed = t.replaceAll(RegExp(r'\s+'), ' ').replaceAllMapped(RegExp(r'\s*([:,>+~])\s*'), (m) => m[1]!);
        final current = out.toString();
        if ((current.endsWith('{') || current.endsWith(';') || current.endsWith('}') || current.isEmpty)) {
          out.write(collapsed.trimLeft());
        } else {
          out.write(collapsed);
        }
      }
    }
    return out.toString().trim();
  }

  /// Splits into strings, comments, braces, semicolons and other text.
  static List<String> _tokens(String css) {
    final tokens = <String>[];
    final buf = StringBuffer();
    void flush() {
      if (buf.isNotEmpty) tokens.add(buf.toString());
      buf.clear();
    }

    var i = 0;
    var paren = 0;
    while (i < css.length) {
      final ch = css[i];
      if (ch == '/' && i + 1 < css.length && css[i + 1] == '*') {
        flush();
        final end = css.indexOf('*/', i + 2);
        final stop = end < 0 ? css.length : end + 2;
        tokens.add(css.substring(i, stop));
        i = stop;
        continue;
      }
      if (ch == '"' || ch == "'") {
        final start = i;
        i++;
        while (i < css.length && css[i] != ch) {
          if (css[i] == '\\') i++;
          i++;
        }
        buf.write(css.substring(start, math.min(i + 1, css.length)));
        i++;
        continue;
      }
      if (ch == '(') paren++;
      if (ch == ')') paren = math.max(0, paren - 1);
      if (paren == 0 && (ch == '{' || ch == '}' || ch == ';')) {
        flush();
        tokens.add(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }
    flush();
    return tokens;
  }
}
