import 'package:flutter/material.dart';

import '../../core/toolbox/tool.dart';
import 'tools/color_page.dart';
import 'tools/css_page.dart';
import 'tools/html_page.dart';
import 'tools/js_page.dart';
import 'tools/markdown_page.dart';
import 'tools/regex_page.dart';

/// Front-end tools: live previews, a JS runner, Markdown, CSS, colours, regex.
final webTools = <ToolDefinition>[
  ToolDefinition(
    id: 'html_preview',
    category: ToolCategory.web,
    icon: Icons.preview_rounded,
    keywords: ['html', 'css', 'js', 'playground', 'codepen', 'live', 'sandbox', '实时预览', '前端'],
    accepts: {'html', 'htm'},
    builder: (_) => const HtmlPage(),
  ),
  ToolDefinition(
    id: 'js_runner',
    category: ToolCategory.web,
    icon: Icons.play_circle_outline_rounded,
    keywords: ['javascript', 'js', 'run', 'console', 'node', 'eval', 'repl', '运行', '脚本'],
    accepts: {'js', 'mjs'},
    builder: (_) => const JsPage(),
  ),
  ToolDefinition(
    id: 'markdown',
    category: ToolCategory.web,
    icon: Icons.edit_note_rounded,
    keywords: ['md', 'markdown', 'preview', 'editor', 'readme', 'gfm', '编辑', '预览', '文档'],
    accepts: {'md', 'markdown'},
    builder: (_) => const MarkdownPage(),
  ),
  ToolDefinition(
    id: 'css',
    category: ToolCategory.web,
    icon: Icons.style_outlined,
    keywords: ['css', 'beautify', 'minify', 'format', 'stylesheet', '样式', '格式化', '压缩'],
    accepts: {'css'},
    builder: (_) => const CssPage(),
  ),
  ToolDefinition(
    id: 'color',
    category: ToolCategory.web,
    icon: Icons.palette_outlined,
    keywords: ['hex', 'rgb', 'hsl', 'hsv', 'cmyk', 'picker', 'contrast', 'wcag', '颜色', '取色', '对比度'],
    builder: (_) => const ColorPage(),
  ),
  ToolDefinition(
    id: 'regex',
    category: ToolCategory.web,
    icon: Icons.manage_search_rounded,
    keywords: ['regexp', 'regular expression', 'match', 'replace', 'pattern', '正则', '匹配'],
    builder: (_) => const RegexPage(),
  ),
];

ToolDefinition webTool(String id) => webTools.firstWhere((t) => t.id == id);
