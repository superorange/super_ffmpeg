import 'package:flutter/material.dart';

import '../core/toolbox/tool.dart';
import '../modules/data/data_module.dart';
import '../modules/encode/encode_module.dart';
import '../modules/generate/generate_module.dart';
import '../modules/image/image_module.dart';
import '../modules/media/media_module.dart';
import '../modules/text/text_module.dart';
import '../modules/web/web_module.dart';

/// Tools on the roadmap (docs/PRD.md §6) — listed so users see where the
/// toolbox is going; they render as "coming soon".
const _plannedTools = <ToolDefinition>[
  ToolDefinition(
    id: 'rename',
    category: ToolCategory.file,
    icon: Icons.drive_file_rename_outline_rounded,
    status: ToolStatus.planned,
    keywords: ['batch', 'rename', '重命名'],
  ),
  ToolDefinition(
    id: 'duplicates',
    category: ToolCategory.file,
    icon: Icons.file_copy_rounded,
    status: ToolStatus.planned,
    keywords: ['duplicate', 'dedupe', '重复'],
  ),
];

/// Every tool in the toolbox. Add a module by appending its list here.
final toolRegistry = <ToolDefinition>[
  ...mediaTools,
  ...imageTools,
  ...dataTools,
  ...webTools,
  ...encodeTools,
  ...textTools,
  ...generateTools,
  ..._plannedTools,
];

ToolDefinition? toolById(String id) {
  for (final t in toolRegistry) {
    if (t.id == id) return t;
  }
  return null;
}

Map<ToolCategory, List<ToolDefinition>> toolsByCategory([List<ToolDefinition>? tools]) {
  final map = <ToolCategory, List<ToolDefinition>>{};
  for (final t in tools ?? toolRegistry) {
    map.putIfAbsent(t.category, () => []).add(t);
  }
  // Categories with something usable first; roadmap-only ones last.
  final order = [
    for (final c in ToolCategory.values)
      if (map[c]?.any((t) => t.isAvailable) ?? false) c,
    for (final c in ToolCategory.values)
      if (map[c] != null && !map[c]!.any((t) => t.isAvailable)) c,
  ];
  return {for (final c in order) c: map[c]!};
}

/// The tool that should open a dropped file, by extension. Media files go
/// to the media studio.
ToolDefinition? toolForFile(String path, {bool Function(String)? isMedia}) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return null;
  final ext = path.substring(dot + 1).toLowerCase();
  if (isMedia?.call(path) ?? false) return mediaTools.first;
  for (final t in toolRegistry) {
    if (t.accepts.contains(ext) && t.isAvailable) return t;
  }
  return null;
}
