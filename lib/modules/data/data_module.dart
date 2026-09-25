import 'package:flutter/material.dart';

import '../../core/toolbox/tool.dart';
import 'tools/csv_page.dart';
import 'tools/json_code_page.dart';
import 'tools/json_diff_page.dart';
import 'tools/json_page.dart';
import 'tools/yaml_page.dart';

/// JSON, YAML and tabular data tools.
final dataTools = <ToolDefinition>[
  ToolDefinition(
    id: 'json',
    category: ToolCategory.data,
    icon: Icons.data_object_rounded,
    keywords: ['format', 'beautify', 'pretty', 'minify', 'validate', 'jsonpath', 'tree', '格式化', '压缩', '校验', '美化'],
    accepts: {'json', 'geojson', 'jsonc'},
    builder: (_) => const JsonPage(),
  ),
  ToolDefinition(
    id: 'json_diff',
    category: ToolCategory.data,
    icon: Icons.compare_arrows_rounded,
    keywords: ['compare', 'diff', 'difference', '对比', '比较', '差异'],
    builder: (_) => const JsonDiffPage(),
  ),
  ToolDefinition(
    id: 'json_yaml',
    category: ToolCategory.data,
    icon: Icons.swap_vert_rounded,
    keywords: ['yaml', 'yml', 'convert', 'k8s', 'kubernetes', '转换'],
    accepts: {'yaml', 'yml'},
    builder: (_) => const YamlPage(),
  ),
  ToolDefinition(
    id: 'json_code',
    category: ToolCategory.data,
    icon: Icons.integration_instructions_outlined,
    keywords: ['typescript', 'interface', 'dart', 'go', 'struct', 'swift', 'kotlin', 'model', 'class', '实体', '类型'],
    builder: (_) => const JsonCodePage(),
  ),
  ToolDefinition(
    id: 'csv_json',
    category: ToolCategory.data,
    icon: Icons.table_chart_outlined,
    keywords: ['csv', 'excel', 'table', 'tsv', 'spreadsheet', '表格'],
    accepts: {'csv', 'tsv'},
    builder: (_) => const CsvPage(),
  ),
];

ToolDefinition dataTool(String id) => dataTools.firstWhere((t) => t.id == id);
