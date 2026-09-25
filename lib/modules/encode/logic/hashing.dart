import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart' as c;

enum HashAlg {
  md5('MD5'),
  sha1('SHA-1'),
  sha224('SHA-224'),
  sha256('SHA-256'),
  sha384('SHA-384'),
  sha512('SHA-512'),
  crc32('CRC32');

  const HashAlg(this.label);
  final String label;

  c.Hash? get _hash => switch (this) {
    md5 => c.md5,
    sha1 => c.sha1,
    sha224 => c.sha224,
    sha256 => c.sha256,
    sha384 => c.sha384,
    sha512 => c.sha512,
    crc32 => null,
  };
}

abstract final class Hashing {
  static String text(HashAlg alg, String input, {String? hmacKey, bool upper = false}) =>
      bytes(alg, utf8.encode(input), hmacKey: hmacKey, upper: upper);

  static String bytes(HashAlg alg, List<int> data, {String? hmacKey, bool upper = false}) {
    String out;
    if (alg == HashAlg.crc32) {
      out = crc32(data).toRadixString(16).padLeft(8, '0');
    } else if (hmacKey != null && hmacKey.isNotEmpty) {
      out = c.Hmac(alg._hash!, utf8.encode(hmacKey)).convert(data).toString();
    } else {
      out = alg._hash!.convert(data).toString();
    }
    return upper ? out.toUpperCase() : out;
  }

  /// Streams a file through every algorithm at once on a background isolate.
  static Future<Map<HashAlg, String>> file(String path, {void Function(double)? onProgress}) async {
    final total = await File(path).length();
    final port = ReceivePort();
    final send = port.sendPort;
    final sub = port.listen((m) {
      if (m is double) onProgress?.call(m);
    });
    try {
      return await Isolate.run(() async {
        final sinks = <HashAlg, (ByteConversionSink, _DigestSink)>{};
        for (final a in HashAlg.values) {
          if (a == HashAlg.crc32) continue;
          final out = _DigestSink();
          sinks[a] = (a._hash!.startChunkedConversion(out), out);
        }
        var crc = 0xFFFFFFFF;
        var read = 0;
        var lastReport = 0;
        await for (final chunk in File(path).openRead()) {
          for (final s in sinks.values) {
            s.$1.add(chunk);
          }
          crc = _crcUpdate(crc, chunk);
          read += chunk.length;
          if (total > 0 && read - lastReport > total ~/ 100) {
            lastReport = read;
            send.send(read / total);
          }
        }
        final result = <HashAlg, String>{};
        for (final e in sinks.entries) {
          e.value.$1.close();
          result[e.key] = e.value.$2.value.toString();
        }
        result[HashAlg.crc32] = ((crc ^ 0xFFFFFFFF) & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
        return result;
      });
    } finally {
      await sub.cancel();
      port.close();
    }
  }

  static final List<int> _table = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int _crcUpdate(int crc, List<int> data) {
    var c = crc;
    for (final b in data) {
      c = _table[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return c;
  }

  static int crc32(List<int> data) => (_crcUpdate(0xFFFFFFFF, data) ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

class _DigestSink implements Sink<c.Digest> {
  late c.Digest value;
  @override
  void add(c.Digest data) => value = data;
  @override
  void close() {}
}
