import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'codecs.dart';

enum JwtAlg {
  hs256('HS256'),
  hs384('HS384'),
  hs512('HS512');

  const JwtAlg(this.name);
  final String name;

  Hash get hash => switch (this) {
    hs256 => sha256,
    hs384 => sha384,
    hs512 => sha512,
  };

  static JwtAlg? byName(String? n) {
    for (final a in values) {
      if (a.name == n) return a;
    }
    return null;
  }
}

enum JwtSignature { valid, invalid, unsupported, unchecked }

@immutable
class DecodedJwt {
  const DecodedJwt({
    required this.header,
    required this.payload,
    required this.signature,
    required this.parts,
  });

  final Map<String, dynamic> header;
  final Object? payload;
  final String signature;
  final List<String> parts;

  String? get alg => header['alg'] as String?;

  Map<String, dynamic> get claims => payload is Map<String, dynamic> ? payload as Map<String, dynamic> : const {};

  DateTime? _time(String claim) {
    final v = claims[claim];
    return v is num ? DateTime.fromMillisecondsSinceEpoch((v * 1000).round()) : null;
  }

  DateTime? get expiresAt => _time('exp');
  DateTime? get issuedAt => _time('iat');
  DateTime? get notBefore => _time('nbf');

  bool isExpired([DateTime? now]) => expiresAt != null && (now ?? DateTime.now()).isAfter(expiresAt!);
  bool isNotYetValid([DateTime? now]) => notBefore != null && (now ?? DateTime.now()).isBefore(notBefore!);

  JwtSignature verify(String secret, {bool secretIsBase64 = false}) {
    final a = JwtAlg.byName(alg);
    if (a == null) return JwtSignature.unsupported;
    if (secret.isEmpty) return JwtSignature.unchecked;
    final key = secretIsBase64 ? Codecs.base64Decode(secret) : utf8.encode(secret);
    final mac = Hmac(a.hash, key).convert(utf8.encode('${parts[0]}.${parts[1]}')).bytes;
    final expected = _b64url(mac);
    return _constantTimeEquals(expected, parts[2]) ? JwtSignature.valid : JwtSignature.invalid;
  }
}

abstract final class Jwt {
  static DecodedJwt decode(String token) {
    final t = token.trim().replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
    final parts = t.split('.');
    if (parts.length != 3) throw const FormatException('A JWT has three dot-separated parts');
    Object? part(String s, String name) {
      try {
        return jsonDecode(utf8.decode(Codecs.base64Decode(s)));
      } catch (_) {
        throw FormatException('Invalid $name');
      }
    }

    final header = part(parts[0], 'header');
    if (header is! Map<String, dynamic>) throw const FormatException('Invalid header');
    return DecodedJwt(header: header, payload: part(parts[1], 'payload'), signature: parts[2], parts: parts);
  }

  /// Builds a signed token (HMAC algorithms).
  static String sign(
    Map<String, dynamic> payload,
    String secret, {
    JwtAlg alg = JwtAlg.hs256,
    Map<String, dynamic>? header,
  }) {
    final h = {'alg': alg.name, 'typ': 'JWT', ...?header};
    final head = _b64url(utf8.encode(jsonEncode(h)));
    final body = _b64url(utf8.encode(jsonEncode(payload)));
    final sig = Hmac(alg.hash, utf8.encode(secret)).convert(utf8.encode('$head.$body')).bytes;
    return '$head.$body.${_b64url(sig)}';
  }
}

String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
