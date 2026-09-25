import 'dart:math';

final _rand = Random.secure();

enum IdKind { uuid4, uuid7, ulid, nanoid, objectId }

abstract final class Ids {
  static String generate(IdKind kind, {bool upper = false, bool hyphens = true, int nanoLength = 21}) {
    var id = switch (kind) {
      IdKind.uuid4 => uuid4(),
      IdKind.uuid7 => uuid7(),
      IdKind.ulid => ulid(),
      IdKind.nanoid => nanoid(nanoLength),
      IdKind.objectId => objectId(),
    };
    if ((kind == IdKind.uuid4 || kind == IdKind.uuid7) && !hyphens) id = id.replaceAll('-', '');
    if (kind != IdKind.nanoid && kind != IdKind.ulid) id = upper ? id.toUpperCase() : id.toLowerCase();
    return id;
  }

  static List<int> _bytes(int n) => List<int>.generate(n, (_) => _rand.nextInt(256));

  static String _uuidString(List<int> b) {
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static String uuid4() {
    final b = _bytes(16);
    b[6] = (b[6] & 0x0F) | 0x40;
    b[8] = (b[8] & 0x3F) | 0x80;
    return _uuidString(b);
  }

  /// RFC 9562 time-ordered UUID.
  static String uuid7([DateTime? at]) {
    final ms = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final b = _bytes(16);
    for (var i = 0; i < 6; i++) {
      b[i] = (ms >> (8 * (5 - i))) & 0xFF;
    }
    b[6] = (b[6] & 0x0F) | 0x70;
    b[8] = (b[8] & 0x3F) | 0x80;
    return _uuidString(b);
  }

  static const _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static String ulid([DateTime? at]) {
    var ms = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final time = List.filled(10, '0');
    for (var i = 9; i >= 0; i--) {
      time[i] = _crockford[ms % 32];
      ms ~/= 32;
    }
    final rand = List.generate(16, (_) => _crockford[_rand.nextInt(32)]);
    return time.join() + rand.join();
  }

  /// Timestamp encoded in a ULID or UUIDv7 (null if not time-based).
  static DateTime? timestampOf(String id) {
    final s = id.trim();
    if (RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$', caseSensitive: false).hasMatch(s)) {
      var ms = 0;
      for (final ch in s.substring(0, 10).toUpperCase().split('')) {
        ms = ms * 32 + _crockford.indexOf(ch);
      }
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    final hex = s.replaceAll('-', '');
    if (RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hex) && hex[12] == '7') {
      return DateTime.fromMillisecondsSinceEpoch(int.parse(hex.substring(0, 12), radix: 16));
    }
    return null;
  }

  static const _nanoAlphabet = '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

  static String nanoid([int length = 21]) =>
      List.generate(length, (_) => _nanoAlphabet[_rand.nextInt(_nanoAlphabet.length)]).join();

  /// MongoDB ObjectId: 4-byte seconds + 5 random + 3 counter.
  static int _counter = Random().nextInt(0xFFFFFF);
  static String objectId() {
    final secs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _counter = (_counter + 1) & 0xFFFFFF;
    final parts = [
      secs.toRadixString(16).padLeft(8, '0'),
      _bytes(5).map((x) => x.toRadixString(16).padLeft(2, '0')).join(),
      _counter.toRadixString(16).padLeft(6, '0'),
    ];
    return parts.join();
  }
}

class PasswordOptions {
  const PasswordOptions({
    this.length = 20,
    this.lower = true,
    this.upper = true,
    this.digits = true,
    this.symbols = true,
    this.excludeAmbiguous = false,
  });

  final int length;
  final bool lower;
  final bool upper;
  final bool digits;
  final bool symbols;
  final bool excludeAmbiguous;

  PasswordOptions copyWith({
    int? length,
    bool? lower,
    bool? upper,
    bool? digits,
    bool? symbols,
    bool? excludeAmbiguous,
  }) => PasswordOptions(
    length: length ?? this.length,
    lower: lower ?? this.lower,
    upper: upper ?? this.upper,
    digits: digits ?? this.digits,
    symbols: symbols ?? this.symbols,
    excludeAmbiguous: excludeAmbiguous ?? this.excludeAmbiguous,
  );
}

abstract final class Passwords {
  static const _ambiguous = 'Il1O0o|`\'"';

  static List<String> sets(PasswordOptions o) {
    String f(String s) => o.excludeAmbiguous ? s.split('').where((c) => !_ambiguous.contains(c)).join() : s;
    return [
      if (o.lower) f('abcdefghijklmnopqrstuvwxyz'),
      if (o.upper) f('ABCDEFGHIJKLMNOPQRSTUVWXYZ'),
      if (o.digits) f('0123456789'),
      if (o.symbols) f(r'!@#$%^&*()-_=+[]{};:,.<>/?~'),
    ];
  }

  /// Guarantees at least one character from each enabled set.
  static String generate(PasswordOptions o) {
    final s = sets(o);
    if (s.isEmpty) return '';
    final all = s.join();
    final chars = <String>[
      for (final set in s.take(o.length)) set[_rand.nextInt(set.length)],
    ];
    while (chars.length < o.length) {
      chars.add(all[_rand.nextInt(all.length)]);
    }
    chars.shuffle(_rand);
    return chars.join();
  }

  /// Entropy in bits for a random password from these options.
  static double entropy(PasswordOptions o) {
    final pool = sets(o).join().length;
    return pool <= 1 ? 0 : o.length * log(pool) / ln2;
  }
}
