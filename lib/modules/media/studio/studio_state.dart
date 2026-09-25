import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A selected in/out segment of one file.
@immutable
class ClipRange {
  const ClipRange(this.start, this.end);
  final Duration start;
  final Duration end;

  Duration get length => end - start;

  /// Whether this is a real sub-range of a file of [total] length.
  bool isPartialOf(Duration total) => start > Duration.zero || (total > Duration.zero && end < total);

  @override
  bool operator ==(Object other) => other is ClipRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'ClipRange($start – $end)';
}

/// Everything the media studio works on: the file library, which file is
/// active, and the per-file playhead / selection shared by every tool tab.
@immutable
class StudioState {
  const StudioState({
    this.files = const [],
    this.active,
    this.playheads = const {},
    this.ranges = const {},
    this.batch = false,
  });

  final List<String> files;
  final String? active;
  final Map<String, Duration> playheads;
  final Map<String, ClipRange> ranges;

  /// Apply batchable tools to every file in the library instead of only the
  /// active one.
  final bool batch;

  Duration playhead([String? path]) => playheads[path ?? active] ?? Duration.zero;
  ClipRange? range([String? path]) => ranges[path ?? active];

  StudioState copyWith({
    List<String>? files,
    String? Function()? active,
    Map<String, Duration>? playheads,
    Map<String, ClipRange>? ranges,
    bool? batch,
  }) {
    return StudioState(
      files: files ?? this.files,
      active: active != null ? active() : this.active,
      playheads: playheads ?? this.playheads,
      ranges: ranges ?? this.ranges,
      batch: batch ?? this.batch,
    );
  }
}

final studioProvider = NotifierProvider<StudioNotifier, StudioState>(StudioNotifier.new);

class StudioNotifier extends Notifier<StudioState> {
  @override
  StudioState build() => const StudioState();

  /// Adds files to the library and makes the first new one active.
  void add(Iterable<String> paths) {
    final fresh = <String>[];
    for (final p in paths) {
      if (!state.files.contains(p) && !fresh.contains(p)) fresh.add(p);
    }
    if (fresh.isEmpty) {
      if (paths.isNotEmpty) select(paths.first);
      return;
    }
    state = state.copyWith(files: [...state.files, ...fresh], active: () => fresh.first);
  }

  void select(String path) {
    if (state.files.contains(path)) state = state.copyWith(active: () => path);
  }

  void remove(String path) {
    final i = state.files.indexOf(path);
    if (i < 0) return;
    final files = [...state.files]..removeAt(i);
    String? active = state.active;
    if (active == path) active = files.isEmpty ? null : files[i.clamp(0, files.length - 1)];
    state = StudioState(
      files: files,
      active: active,
      playheads: {...state.playheads}..remove(path),
      ranges: {...state.ranges}..remove(path),
      batch: files.length > 1 && state.batch,
    );
  }

  void clear() => state = const StudioState();

  /// [to] is the index after removing [from] (ReorderableList.onReorderItem).
  void move(int from, int to) {
    final list = [...state.files];
    final item = list.removeAt(from);
    list.insert(to.clamp(0, list.length), item);
    state = state.copyWith(files: list);
  }

  void setPlayhead(Duration at, {String? path}) {
    final p = path ?? state.active;
    if (p == null) return;
    state = state.copyWith(playheads: {...state.playheads, p: at < Duration.zero ? Duration.zero : at});
  }

  void setRange(Duration start, Duration end, {String? path}) {
    final p = path ?? state.active;
    if (p == null) return;
    final (s, e) = start <= end ? (start, end) : (end, start);
    state = state.copyWith(ranges: {...state.ranges, p: ClipRange(s < Duration.zero ? Duration.zero : s, e)});
  }

  /// Sets the in point at the playhead, keeping the out point if valid.
  void markIn(Duration total) {
    final at = state.playhead();
    final end = state.range()?.end ?? total;
    setRange(at, end > at ? end : total);
  }

  /// Sets the out point at the playhead, keeping the in point if valid.
  void markOut(Duration total) {
    final at = state.playhead();
    final start = state.range()?.start ?? Duration.zero;
    setRange(start < at ? start : Duration.zero, at);
  }

  void clearRange({String? path}) {
    final p = path ?? state.active;
    if (p == null) return;
    state = state.copyWith(ranges: {...state.ranges}..remove(p));
  }

  void setBatch(bool value) => state = state.copyWith(batch: value);
}

/// Live preview adjustments a tool wants the stage to show (e.g. rotation
/// from the transform tab). Reset when leaving that tab.
@immutable
class StagePreview {
  const StagePreview({this.quarterTurns = 0, this.flipH = false, this.flipV = false, this.aspect});
  final int quarterTurns;
  final bool flipH;
  final bool flipV;

  /// Output frame aspect ratio guide (e.g. 9/16), null = none.
  final double? aspect;

  static const none = StagePreview();
}

final stagePreviewProvider = NotifierProvider<StagePreviewNotifier, StagePreview>(StagePreviewNotifier.new);

class StagePreviewNotifier extends Notifier<StagePreview> {
  @override
  StagePreview build() => StagePreview.none;

  void set(StagePreview value) => state = value;
}
