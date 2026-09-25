import 'package:flutter/material.dart';

import '../../core/toolbox/tool.dart';
import 'tools/cron_page.dart';
import 'tools/password_page.dart';
import 'tools/qr_page.dart';
import 'tools/timestamp_page.dart';
import 'tools/uuid_page.dart';

/// Generators and time utilities.
final generateTools = <ToolDefinition>[
  ToolDefinition(
    id: 'uuid',
    category: ToolCategory.generate,
    icon: Icons.fingerprint_outlined,
    keywords: ['uuid', 'guid', 'ulid', 'nanoid', 'objectid', 'id', 'random', '唯一', '标识'],
    builder: (_) => const UuidPage(),
  ),
  ToolDefinition(
    id: 'password',
    category: ToolCategory.generate,
    icon: Icons.password_rounded,
    keywords: ['password', 'random', 'secure', 'strong', 'passphrase', '密码', '随机'],
    builder: (_) => const PasswordPage(),
  ),
  ToolDefinition(
    id: 'qrcode',
    category: ToolCategory.generate,
    icon: Icons.qr_code_2_rounded,
    keywords: ['qr', 'qrcode', 'barcode', 'wifi', '二维码'],
    builder: (_) => const QrPage(),
  ),
  ToolDefinition(
    id: 'timestamp',
    category: ToolCategory.generate,
    icon: Icons.schedule_rounded,
    keywords: ['unix', 'epoch', 'time', 'date', 'iso8601', 'utc', '时间戳', '日期', '时间'],
    builder: (_) => const TimestampPage(),
  ),
  ToolDefinition(
    id: 'cron',
    category: ToolCategory.generate,
    icon: Icons.event_repeat_rounded,
    keywords: ['cron', 'crontab', 'schedule', 'job', '定时', '计划任务'],
    builder: (_) => const CronPage(),
  ),
];

ToolDefinition generateTool(String id) => generateTools.firstWhere((t) => t.id == id);
