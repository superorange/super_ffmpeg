/// Arbitrary-precision base conversion.
abstract final class NumberBase {
  static const _digits = '0123456789abcdefghijklmnopqrstuvwxyz';

  /// Parses [input] in [radix] (2–36). A `0x`/`0b`/`0o` prefix overrides
  /// [radix]; `_`/space/comma separators and a leading minus are accepted.
  static BigInt parse(String input, int radix) => parseWithRadix(input, radix).$1;

  /// Like [parse], also returning the radix actually used.
  static (BigInt, int) parseWithRadix(String input, int radix) {
    var s = input.trim().toLowerCase().replaceAll(RegExp(r'[\s_,]'), '');
    var negative = false;
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1);
    }
    const prefixes = {'0x': 16, '0b': 2, '0o': 8};
    for (final e in prefixes.entries) {
      // "0b" is also a valid hex number, so only strip it outside base 16.
      if (s.startsWith(e.key) && s.length > 2 && !(radix == 16 && e.key == '0b')) {
        radix = e.value;
        s = s.substring(2);
        break;
      }
    }
    if (s.isEmpty) throw const FormatException('Empty number');
    var v = BigInt.zero;
    final r = BigInt.from(radix);
    for (final ch in s.split('')) {
      final d = _digits.indexOf(ch);
      if (d < 0 || d >= radix) throw FormatException('"$ch" is not a base-$radix digit');
      v = v * r + BigInt.from(d);
    }
    return (negative ? -v : v, radix);
  }

  static String format(BigInt v, int radix, {bool group = false, bool upper = false}) {
    var s = v.abs().toRadixString(radix);
    if (upper) s = s.toUpperCase();
    if (group) {
      final size = radix == 10 ? 3 : 4;
      final buf = StringBuffer();
      for (var i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % size == 0) buf.write(radix == 10 ? ',' : ' ');
        buf.write(s[i]);
      }
      s = buf.toString();
    }
    return v.isNegative ? '-$s' : s;
  }

  /// Two's complement bit pattern for negative numbers at [bits] width.
  static String twosComplement(BigInt v, int bits) {
    final mod = BigInt.one << bits;
    final x = v.isNegative ? (mod + v) % mod : v % mod;
    return x.toRadixString(2).padLeft(bits, '0');
  }
}
