import 'dart:convert';
import 'dart:math';

enum CaseStyle {
  camel('camelCase'),
  pascal('PascalCase'),
  snake('snake_case'),
  constant('CONSTANT_CASE'),
  kebab('kebab-case'),
  train('Train-Case'),
  dot('dot.case'),
  path('path/case'),
  title('Title Case'),
  sentence('Sentence case'),
  lower('lower case'),
  upper('UPPER CASE');

  const CaseStyle(this.example);
  final String example;
}

abstract final class TextTools {
  /// Splits identifiers and prose into words: `parseHTTPResponse2` →
  /// [parse, HTTP, Response, 2]; separators are any non-alphanumerics.
  static List<String> words(String s) {
    final re = RegExp(r'[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z]+|[A-Z]+|\d+|[^\x00-\x7F]+');
    return [for (final m in re.allMatches(s)) m[0]!];
  }

  static String convertCase(String input, CaseStyle style) {
    // Convert each line independently so lists of identifiers work.
    return input.split('\n').map((line) => _convertLine(line, style)).join('\n');
  }

  static String _convertLine(String line, CaseStyle style) {
    final w = words(line);
    if (w.isEmpty) return line;
    String cap(String x) => x.isEmpty ? x : x[0].toUpperCase() + x.substring(1).toLowerCase();
    final lower = w.map((x) => x.toLowerCase()).toList();
    return switch (style) {
      CaseStyle.camel => lower.first + w.skip(1).map(cap).join(),
      CaseStyle.pascal => w.map(cap).join(),
      CaseStyle.snake => lower.join('_'),
      CaseStyle.constant => w.map((x) => x.toUpperCase()).join('_'),
      CaseStyle.kebab => lower.join('-'),
      CaseStyle.train => w.map(cap).join('-'),
      CaseStyle.dot => lower.join('.'),
      CaseStyle.path => lower.join('/'),
      CaseStyle.title => w.map(cap).join(' '),
      CaseStyle.sentence => [cap(w.first), ...lower.skip(1)].join(' '),
      CaseStyle.lower => line.toLowerCase(),
      CaseStyle.upper => line.toUpperCase(),
    };
  }

  static final _cjk = RegExp(r'[぀-ヿ㐀-䶿一-鿿豈-﫿가-힯]');

  /// Character/word/line statistics. CJK characters count as one word each.
  static TextStats stats(String s) {
    final chars = s.runes.length;
    final noSpace = s.replaceAll(RegExp(r'\s'), '').runes.length;
    final cjk = _cjk.allMatches(s).length;
    final latinWords = RegExp(r"[A-Za-z0-9À-ɏ]+(?:['’-][A-Za-z0-9À-ɏ]+)*").allMatches(s).length;
    final lines = s.isEmpty ? 0 : '\n'.allMatches(s).length + 1;
    final paragraphs = s.trim().isEmpty ? 0 : s.trim().split(RegExp(r'\n\s*\n')).length;
    final sentences = s.trim().isEmpty ? 0 : RegExp(r'[.!?。！？]+(\s|$)').allMatches(s.trim()).length.clamp(1, 1 << 30);
    final words = cjk + latinWords;
    // ~250 English words or ~400 CJK characters per minute.
    final minutes = latinWords / 250 + cjk / 400;
    return TextStats(
      characters: chars,
      charactersNoSpaces: noSpace,
      words: words,
      lines: lines,
      paragraphs: paragraphs,
      sentences: sentences,
      bytes: utf8.encode(s).length,
      readingTime: Duration(seconds: (minutes * 60).ceil()),
    );
  }

  static String applyLineOp(String input, LineOp op) {
    final lines = input.split('\n');
    List<String> out;
    switch (op) {
      case LineOp.sortAsc:
        out = [...lines]..sort((a, b) => a.compareTo(b));
      case LineOp.sortDesc:
        out = [...lines]..sort((a, b) => b.compareTo(a));
      case LineOp.sortNatural:
        out = [...lines]..sort(_natural);
      case LineOp.sortLength:
        out = [...lines]..sort((a, b) => a.length.compareTo(b.length));
      case LineOp.reverse:
        out = lines.reversed.toList();
      case LineOp.unique:
        final seen = <String>{};
        out = [
          for (final l in lines)
            if (seen.add(l)) l,
        ];
      case LineOp.removeEmpty:
        out = [
          for (final l in lines)
            if (l.trim().isNotEmpty) l,
        ];
      case LineOp.trim:
        out = [for (final l in lines) l.trim()];
      case LineOp.shuffle:
        out = [...lines]..shuffle(Random.secure());
      case LineOp.number:
        final width = '${lines.length}'.length;
        out = [for (var i = 0; i < lines.length; i++) '${'${i + 1}'.padLeft(width)}. ${lines[i]}'];
      case LineOp.joinLines:
        return lines.map((l) => l.trim()).where((l) => l.isNotEmpty).join(' ');
      case LineOp.collapseSpaces:
        out = [for (final l in lines) l.replaceAll(RegExp(r'[ \t]+'), ' ')];
    }
    return out.join('\n');
  }

  static int _natural(String a, String b) {
    final re = RegExp(r'(\d+)|(\D+)');
    final pa = re.allMatches(a).toList(), pb = re.allMatches(b).toList();
    for (var i = 0; i < pa.length && i < pb.length; i++) {
      final x = pa[i], y = pb[i];
      if (x[1] != null && y[1] != null) {
        final c = BigInt.parse(x[1]!).compareTo(BigInt.parse(y[1]!));
        if (c != 0) return c;
      } else {
        final c = x[0]!.toLowerCase().compareTo(y[0]!.toLowerCase());
        if (c != 0) return c;
      }
    }
    return pa.length.compareTo(pb.length);
  }

  static const _lorem =
      'lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore '
      'magna aliqua ut enim ad minim veniam quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo '
      'consequat duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur '
      'excepteur sint occaecat cupidatat non proident sunt in culpa qui officia deserunt mollit anim id est laborum';

  static const _zh =
      '天地玄黄宇宙洪荒日月盈昃辰宿列张寒来暑往秋收冬藏闰余成岁律吕调阳云腾致雨露结为霜金生丽水玉出昆冈剑号巨阙珠称夜光果珍李柰菜重芥姜'
      '海咸河淡鳞潜羽翔龙师火帝鸟官人皇始制文字乃服衣裳推位让国有虞陶唐吊民伐罪周发殷汤坐朝问道垂拱平章爱育黎首臣伏戎羌';

  /// Placeholder text: [paragraphs] paragraphs of roughly [sentences]
  /// sentences each. Chinese uses classical characters.
  static String lorem({int paragraphs = 3, int sentences = 5, bool chinese = false, int? seed, bool classic = true}) {
    final rnd = Random(seed);
    final words = _lorem.split(' ');
    String sentence(bool first) {
      if (chinese) {
        final len = 8 + rnd.nextInt(14);
        final buf = StringBuffer();
        for (var i = 0; i < len; i++) {
          buf.write(_zh[rnd.nextInt(_zh.length)]);
          if (i > 3 && i < len - 3 && rnd.nextInt(7) == 0) buf.write('，');
        }
        return '$buf。';
      }
      if (first && classic) return 'Lorem ipsum dolor sit amet, consectetur adipiscing elit.';
      final len = 6 + rnd.nextInt(10);
      final w = [for (var i = 0; i < len; i++) words[rnd.nextInt(words.length)]];
      if (len > 8) w[3 + rnd.nextInt(len - 6)] += ',';
      final s = w.join(' ');
      return '${s[0].toUpperCase()}${s.substring(1)}.';
    }

    return [
      for (var p = 0; p < paragraphs; p++)
        [for (var s = 0; s < sentences; s++) sentence(p == 0 && s == 0)].join(chinese ? '' : ' '),
    ].join('\n\n');
  }
}

enum LineOp {
  sortAsc,
  sortDesc,
  sortNatural,
  sortLength,
  reverse,
  unique,
  removeEmpty,
  trim,
  shuffle,
  number,
  joinLines,
  collapseSpaces,
}

class TextStats {
  const TextStats({
    required this.characters,
    required this.charactersNoSpaces,
    required this.words,
    required this.lines,
    required this.paragraphs,
    required this.sentences,
    required this.bytes,
    required this.readingTime,
  });

  final int characters;
  final int charactersNoSpaces;
  final int words;
  final int lines;
  final int paragraphs;
  final int sentences;
  final int bytes;
  final Duration readingTime;
}
