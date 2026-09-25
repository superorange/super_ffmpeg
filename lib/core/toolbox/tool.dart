import 'package:flutter/material.dart';

/// Top-level toolbox sections. Every tool lives in exactly one category.
/// Hues are spread around the colour wheel so categories stay distinct.
enum ToolCategory {
  media(Icons.movie_filter_rounded, Color(0xFFF43F5E), Color(0xFFFB923C)),
  image(Icons.image_rounded, Color(0xFFF97316), Color(0xFFFBBF24)),
  data(Icons.data_object_rounded, Color(0xFF3B82F6), Color(0xFF22D3EE)),
  web(Icons.web_rounded, Color(0xFF06B6D4), Color(0xFF34D399)),
  encode(Icons.lock_rounded, Color(0xFF8B5CF6), Color(0xFFD946EF)),
  text(Icons.notes_rounded, Color(0xFF10B981), Color(0xFFA3E635)),
  generate(Icons.auto_awesome_rounded, Color(0xFFEAB308), Color(0xFFF97316)),
  file(Icons.folder_rounded, Color(0xFF64748B), Color(0xFF94A3B8));

  const ToolCategory(this.icon, this.color, this.color2);
  final IconData icon;
  final Color color;
  final Color color2;

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [color, color2],
  );

  String get labelKey => 'categories.$name';
}

enum ToolStatus { ready, beta, planned }

/// A tool registered with the toolbox. Home, sidebar, ⌘K palette and routing
/// are all generated from the registry.
@immutable
class ToolDefinition {
  const ToolDefinition({
    required this.id,
    required this.category,
    required this.icon,
    this.keywords = const [],
    this.status = ToolStatus.ready,
    this.builder,
    this.path,
    this.accepts = const {},
  });

  /// Unique id, also used for i18n keys `tools.<id>.name` / `.desc`.
  final String id;
  final ToolCategory category;
  final IconData icon;

  /// Extra search terms (both languages, codec names…).
  final List<String> keywords;
  final ToolStatus status;

  /// Standalone page. Null for tools hosted inside another page ([path]).
  final WidgetBuilder? builder;

  /// Custom location for tools that live inside a workspace page (e.g. media
  /// tools are tabs of the media studio at `/media/<id>`).
  final String? path;

  /// Lower-case file extensions this tool opens when a file is dropped on
  /// the home page (e.g. `json`, `md`).
  final Set<String> accepts;

  String get route => path ?? '/tool/$id';
  String get nameKey => 'tools.$id.name';
  String get descKey => 'tools.$id.desc';
  bool get isAvailable => status != ToolStatus.planned && (builder != null || path != null);
}

/// Ranks tools against a search query using name, description and keywords.
List<ToolDefinition> searchTools(
  List<ToolDefinition> tools,
  String query, {
  required String Function(String key) translate,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return tools;
  final scored = <(int, ToolDefinition)>[];
  for (final t in tools) {
    final name = translate(t.nameKey).toLowerCase();
    final desc = translate(t.descKey).toLowerCase();
    final cat = translate(t.category.labelKey).toLowerCase();
    int score;
    if (name.startsWith(q)) {
      score = 0;
    } else if (name.contains(q)) {
      score = 1;
    } else if (t.keywords.any((k) => k.toLowerCase().contains(q)) || t.id.contains(q)) {
      score = 2;
    } else if (desc.contains(q) || cat.contains(q)) {
      score = 3;
    } else {
      continue;
    }
    if (!t.isAvailable) score += 10;
    scored.add((score, t));
  }
  scored.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final s in scored) s.$2];
}
