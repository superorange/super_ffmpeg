import 'package:flutter/material.dart';

import '../../core/toolbox/tool.dart';
import 'tools/base64_page.dart';
import 'tools/encode_page.dart';
import 'tools/hash_page.dart';
import 'tools/jwt_page.dart';
import 'tools/number_base_page.dart';
import 'tools/url_page.dart';

/// Encodings, tokens and checksums.
final encodeTools = <ToolDefinition>[
  ToolDefinition(
    id: 'base64',
    category: ToolCategory.encode,
    icon: Icons.text_snippet_outlined,
    keywords: ['base64', 'data uri', 'image', 'encode', 'decode', '编码', '解码', '图片'],
    builder: (_) => const Base64Page(),
  ),
  ToolDefinition(
    id: 'encode',
    category: ToolCategory.encode,
    icon: Icons.code_rounded,
    keywords: ['url', 'urlencode', 'percent', 'html entity', 'unicode', 'escape', 'hex', 'binary', '转义', '编码'],
    builder: (_) => const EncodePage(),
  ),
  ToolDefinition(
    id: 'url',
    category: ToolCategory.encode,
    icon: Icons.link_rounded,
    keywords: ['url', 'query', 'params', 'parse', 'uri', '链接', '参数', '解析'],
    builder: (_) => const UrlPage(),
  ),
  ToolDefinition(
    id: 'jwt',
    category: ToolCategory.encode,
    icon: Icons.key_rounded,
    keywords: ['jwt', 'token', 'bearer', 'oauth', 'claims', 'hs256', '令牌', '解码', '签名'],
    builder: (_) => const JwtPage(),
  ),
  ToolDefinition(
    id: 'hash',
    category: ToolCategory.encode,
    icon: Icons.fingerprint_rounded,
    keywords: ['md5', 'sha1', 'sha256', 'sha512', 'crc32', 'hmac', 'checksum', '校验', '哈希', '摘要'],
    builder: (_) => const HashPage(),
  ),
  ToolDefinition(
    id: 'number_base',
    category: ToolCategory.encode,
    icon: Icons.onetwothree_rounded,
    keywords: ['binary', 'hex', 'octal', 'decimal', 'radix', 'bits', '进制', '二进制', '十六进制'],
    builder: (_) => const NumberBasePage(),
  ),
];

ToolDefinition encodeTool(String id) => encodeTools.firstWhere((t) => t.id == id);
