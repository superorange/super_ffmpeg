import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_ffmpeg/app/tool_registry.dart';
import 'package:super_ffmpeg/core/jobs/job.dart';
import 'package:super_ffmpeg/core/toolbox/tool.dart';
import 'package:super_ffmpeg/modules/generate/logic/generators.dart';
import 'package:super_ffmpeg/modules/media/builders/cli.dart';
import 'package:super_ffmpeg/modules/media/media_module.dart';
import 'package:super_ffmpeg/modules/text/logic/text_tools.dart';
import 'package:super_ffmpeg/modules/web/tools/js_page.dart' show jsSamples;
import 'package:super_ffmpeg/modules/media/widgets/drop_zone.dart';

Set<String> _flatten(Map<String, dynamic> map, [String prefix = '']) => {
  for (final e in map.entries)
    if (e.value is Map)
      ..._flatten((e.value as Map).cast<String, dynamic>(), '$prefix${e.key}.')
    else
      '$prefix${e.key}',
};

Set<String> _load(String locale) =>
    _flatten(jsonDecode(File('assets/translations/$locale.json').readAsStringSync()) as Map<String, dynamic>);

void main() {
  final zh = _load('zh-CN');
  final en = _load('en');

  test('zh-CN and en define the same keys', () {
    expect(zh.difference(en), isEmpty, reason: 'missing in en');
    expect(en.difference(zh), isEmpty, reason: 'missing in zh-CN');
  });

  test('every translation key referenced in lib/ exists', () {
    const namespaces =
        'app|common|nav|palette|categories|home|tools|media|tasks|settings|studio|json|json_diff|json_code|csv|'
        'html_preview|js_runner|markdown|color|regex|encode|base64|url|jwt|hash|number_base|diff|case|text_tools|'
        'lorem|uuid|password|qrcode|time|cron|image';
    final literal = RegExp("'((?:$namespaces)\\.[a-z0-9_.]+[a-z0-9_])'");
    final used = <String>{
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart'))
          for (final m in literal.allMatches(f.readAsStringSync())) m.group(1)!,
      // Keys built at runtime.
      for (final t in toolRegistry) ...[t.nameKey, t.descKey],
      for (final c in ToolCategory.values) c.labelKey,
      for (final s in JobStatus.values) 'tasks.status.${s.name}',
      for (final a in MediaAccept.values) a.hintKey,
      for (final t in cliTemplates) t.labelKey,
      for (final t in mediaTools) 'studio.tabs.${t.id}',
      for (final op in LineOp.values) 'text_tools.ops.${op.name}',
      for (final u in ['seconds', 'minutes', 'hours', 'days', 'months', 'years']) 'time.units.$u',
      for (var d = 1; d <= 7; d++) 'time.weekdays.$d',
      for (final k in IdKind.values) 'uuid.${k.name}_desc',
      for (final k in jsSamples.keys) 'js_runner.sample_$k',
    };
    final missing = used.difference(zh)
      ..removeWhere((k) => RegExp(r'\.(txt|png|json|ya?ml|csv|html|md|css|js)$').hasMatch(k));
    expect(missing, isEmpty);
  });

  test('tool ids are unique and every available tool has a page', () {
    final ids = toolRegistry.map((t) => t.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final t in toolRegistry) {
      expect(t.isAvailable, t.status != ToolStatus.planned, reason: t.id);
    }
    expect(toolRegistry.where((t) => t.category == ToolCategory.media && t.isAvailable), hasLength(10));
  });

  group('searchTools', () {
    String tr(String key) =>
        {
          'tools.gif.name': 'GIF 制作',
          'tools.gif.desc': '动图',
          'tools.compress.name': '视频压缩',
          'tools.compress.desc': '缩小视频',
        }[key] ??
        key;

    final tools = [
      const ToolDefinition(
        id: 'compress',
        category: ToolCategory.media,
        icon: IconDataStub.icon,
        keywords: ['discord', '8mb'],
      ),
      const ToolDefinition(id: 'gif', category: ToolCategory.media, icon: IconDataStub.icon, keywords: ['meme']),
    ];

    test('matches name, keywords and description', () {
      expect(searchTools(tools, 'gif', translate: tr).map((t) => t.id), ['gif']);
      expect(searchTools(tools, 'DISCORD', translate: tr).map((t) => t.id), ['compress']);
      expect(searchTools(tools, '缩小', translate: tr).map((t) => t.id), ['compress']);
      expect(searchTools(tools, '', translate: tr), tools);
      expect(searchTools(tools, 'zzz', translate: tr), isEmpty);
    });

    test('name prefix outranks keyword match', () {
      final ranked = searchTools(tools, '视频', translate: tr);
      expect(ranked.first.id, 'compress');
    });
  });
}

abstract final class IconDataStub {
  static const icon = IconData(0);
}
