import 'package:flutter/material.dart';

import '../../core/toolbox/tool.dart';
import 'tools/case_page.dart';
import 'tools/diff_page.dart';
import 'tools/lorem_page.dart';
import 'tools/text_tools_page.dart';

/// Text comparison and transformation.
final textTools = <ToolDefinition>[
  ToolDefinition(
    id: 'diff',
    category: ToolCategory.text,
    icon: Icons.difference_outlined,
    keywords: ['diff', 'compare', 'difference', 'merge', '对比', '比较', '差异'],
    accepts: {'txt', 'log', 'diff', 'patch'},
    builder: (_) => const DiffPage(),
  ),
  ToolDefinition(
    id: 'case',
    category: ToolCategory.text,
    icon: Icons.text_fields_rounded,
    keywords: ['camel', 'snake', 'kebab', 'pascal', 'upper', 'lower', 'title', '驼峰', '下划线', '大小写', '命名'],
    builder: (_) => const CasePage(),
  ),
  ToolDefinition(
    id: 'text_tools',
    category: ToolCategory.text,
    icon: Icons.format_line_spacing_rounded,
    keywords: ['count', 'words', 'characters', 'sort', 'unique', 'dedupe', 'lines', '字数', '统计', '排序', '去重'],
    builder: (_) => const TextToolsPage(),
  ),
  ToolDefinition(
    id: 'lorem',
    category: ToolCategory.text,
    icon: Icons.short_text_rounded,
    keywords: ['lorem', 'ipsum', 'placeholder', 'dummy', 'filler', '假文', '占位'],
    builder: (_) => const LoremPage(),
  ),
];

ToolDefinition textTool(String id) => textTools.firstWhere((t) => t.id == id);
