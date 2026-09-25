import 'dart:convert';
import 'dart:typed_data';

/// Text encodings offered by the encode/decode tool.
enum TextCodec { base64, base64url, url, urlComponent, html, unicode, hex, binary }

abstract final class Codecs {
  static String encode(TextCodec codec, String input) => switch (codec) {
    TextCodec.base64 => base64.encode(utf8.encode(input)),
    TextCodec.base64url => base64Url.encode(utf8.encode(input)).replaceAll('=', ''),
    TextCodec.url => Uri.encodeFull(input),
    TextCodec.urlComponent => Uri.encodeComponent(input),
    TextCodec.html => htmlEscape(input),
    TextCodec.unicode => unicodeEscape(input),
    TextCodec.hex => hexEncode(utf8.encode(input)),
    TextCodec.binary => utf8.encode(input).map((b) => b.toRadixString(2).padLeft(8, '0')).join(' '),
  };

  static String decode(TextCodec codec, String input) => switch (codec) {
    TextCodec.base64 || TextCodec.base64url => utf8.decode(base64Decode(input), allowMalformed: false),
    TextCodec.url => Uri.decodeFull(input),
    TextCodec.urlComponent => Uri.decodeComponent(input.replaceAll('+', ' ')),
    TextCodec.html => htmlUnescape(input),
    TextCodec.unicode => unicodeUnescape(input),
    TextCodec.hex => utf8.decode(hexDecode(input)),
    TextCodec.binary => utf8.decode([
      for (final b in input.trim().split(RegExp(r'\s+'))) int.parse(b, radix: 2),
    ]),
  };

  /// Lenient Base64: accepts URL-safe alphabet, whitespace, missing padding
  /// and `data:` URIs.
  static Uint8List base64Decode(String input) {
    var s = input.trim();
    final comma = s.indexOf(',');
    if (s.startsWith('data:') && comma > 0) s = s.substring(comma + 1);
    s = s.replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
    final pad = s.length % 4;
    if (pad == 1) throw const FormatException('Invalid Base64 length');
    if (pad > 0) s += '=' * (4 - pad);
    return base64.decode(s);
  }

  static String htmlEscape(String s) {
    final buf = StringBuffer();
    for (final r in s.runes) {
      switch (r) {
        case 0x26:
          buf.write('&amp;');
        case 0x3C:
          buf.write('&lt;');
        case 0x3E:
          buf.write('&gt;');
        case 0x22:
          buf.write('&quot;');
        case 0x27:
          buf.write('&#39;');
        default:
          buf.writeCharCode(r);
      }
    }
    return buf.toString();
  }

  static const _named = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': '\u00A0',
    'copy': '©',
    'reg': '®',
    'trade': '™',
    'hellip': '…',
    'mdash': '—',
    'ndash': '–',
    'lsquo': '‘',
    'rsquo': '’',
    'ldquo': '“',
    'rdquo': '”',
    'bull': '•',
    'middot': '·',
    'times': '×',
    'divide': '÷',
    'euro': '€',
    'pound': '£',
    'yen': '¥',
    'cent': '¢',
    'sect': '§',
    'deg': '°',
    'plusmn': '±',
    'larr': '←',
    'rarr': '→',
    'uarr': '↑',
    'darr': '↓',
    'hearts': '♥',
    'laquo': '«',
    'raquo': '»',
    'para': '¶',
    'shy': '\u00AD',
  };

  static String htmlUnescape(String s) => s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
    final body = m[1]!;
    if (body.startsWith('#x') || body.startsWith('#X')) {
      return String.fromCharCode(int.parse(body.substring(2), radix: 16));
    }
    if (body.startsWith('#')) return String.fromCharCode(int.parse(body.substring(1)));
    return _named[body] ?? m[0]!;
  });

  /// Non-ASCII → `\uXXXX` (surrogate pairs for astral characters).
  static String unicodeEscape(String s) {
    final buf = StringBuffer();
    for (final unit in s.codeUnits) {
      if (unit < 0x80) {
        buf.writeCharCode(unit);
      } else {
        buf.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
      }
    }
    return buf.toString();
  }

  static String unicodeUnescape(String s) => s.replaceAllMapped(
    RegExp(r'\\u\{([0-9a-fA-F]{1,6})\}|\\u([0-9a-fA-F]{4})|\\x([0-9a-fA-F]{2})'),
    (m) {
      final hex = m[1] ?? m[2] ?? m[3]!;
      return String.fromCharCode(int.parse(hex, radix: 16));
    },
  );

  static String hexEncode(List<int> bytes, {String separator = ''}) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(separator);

  static Uint8List hexDecode(String input) {
    final s = input.replaceAll(RegExp(r'0x|\s|:|-', caseSensitive: false), '');
    if (s.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(s)) throw const FormatException('Invalid hex');
    return Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
  }

  /// Sniffs common file signatures so decoded Base64 can be previewed/saved.
  static ({String mime, String ext})? sniff(List<int> b) {
    bool starts(List<int> sig, [int at = 0]) {
      if (b.length < at + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[at + i] != sig[i]) return false;
      }
      return true;
    }

    if (starts([0x89, 0x50, 0x4E, 0x47])) return (mime: 'image/png', ext: 'png');
    if (starts([0xFF, 0xD8, 0xFF])) return (mime: 'image/jpeg', ext: 'jpg');
    if (starts([0x47, 0x49, 0x46, 0x38])) return (mime: 'image/gif', ext: 'gif');
    if (starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x45, 0x42, 0x50], 8)) {
      return (mime: 'image/webp', ext: 'webp');
    }
    if (starts([0x42, 0x4D])) return (mime: 'image/bmp', ext: 'bmp');
    if (starts([0x25, 0x50, 0x44, 0x46])) return (mime: 'application/pdf', ext: 'pdf');
    if (starts([0x50, 0x4B, 0x03, 0x04])) return (mime: 'application/zip', ext: 'zip');
    if (starts([0x1F, 0x8B])) return (mime: 'application/gzip', ext: 'gz');
    if (starts([0x66, 0x74, 0x79, 0x70], 4)) return (mime: 'video/mp4', ext: 'mp4');
    if (starts([0x3C, 0x73, 0x76, 0x67]) || starts([0x3C, 0x3F, 0x78, 0x6D])) {
      return (mime: 'image/svg+xml', ext: 'svg');
    }
    return null;
  }
}

/// Parsed URL for the URL inspector.
class UrlParts {
  UrlParts(this.uri);
  final Uri uri;

  static UrlParts? tryParse(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || (!uri.hasScheme && uri.host.isEmpty)) return null;
    return UrlParts(uri);
  }

  /// Query parameters in order, keeping repeated keys.
  List<(String, String)> get query {
    if (uri.query.isEmpty) return const [];
    return [
      for (final part in uri.query.split('&'))
        if (part.isNotEmpty)
          () {
            final i = part.indexOf('=');
            String dec(String s) {
              try {
                return Uri.decodeQueryComponent(s);
              } catch (_) {
                return s;
              }
            }

            return i < 0 ? (dec(part), '') : (dec(part.substring(0, i)), dec(part.substring(i + 1)));
          }(),
    ];
  }
}
