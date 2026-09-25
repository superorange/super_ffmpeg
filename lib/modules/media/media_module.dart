import 'package:flutter/material.dart';

import '../../core/toolbox/tool.dart';
import 'tools/audio_page.dart';
import 'tools/cli_page.dart';
import 'tools/compress_page.dart';
import 'tools/concat_page.dart';
import 'tools/convert_page.dart';
import 'tools/frames_page.dart';
import 'tools/gif_page.dart';
import 'tools/inspect_page.dart';
import 'tools/transform_page.dart';
import 'tools/trim_page.dart';

/// Media module (FFmpeg). Each tool is a tab of the media studio
/// (`/media/<id>`); order here is the tab order.
final mediaTools = <ToolDefinition>[
  ToolDefinition(
    id: 'convert',
    category: ToolCategory.media,
    path: '/media/convert',
    icon: Icons.swap_horiz_rounded,
    keywords: ['transcode', 'mp4', 'mkv', 'mov', 'webm', 'h264', 'hevc', 'h265', 'av1', 'vp9', 'prores', '转码', '格式'],
    builder: (_) => const ConvertTool(),
  ),
  ToolDefinition(
    id: 'compress',
    category: ToolCategory.media,
    path: '/media/compress',
    icon: Icons.compress_rounded,
    keywords: ['shrink', 'size', 'discord', '8mb', 'smaller', '压缩', '体积', '大小'],
    builder: (_) => const CompressTool(),
  ),
  ToolDefinition(
    id: 'trim',
    category: ToolCategory.media,
    path: '/media/trim',
    icon: Icons.content_cut_rounded,
    keywords: ['cut', 'clip', 'split', 'segment', '剪切', '裁剪', '片段'],
    builder: (_) => const TrimTool(),
  ),
  ToolDefinition(
    id: 'audio',
    category: ToolCategory.media,
    path: '/media/audio',
    icon: Icons.graphic_eq_rounded,
    keywords: ['extract', 'mp3', 'aac', 'flac', 'wav', 'opus', 'loudness', 'normalize', '提取', '音频', '响度'],
    builder: (_) => const AudioTool(),
  ),
  ToolDefinition(
    id: 'gif',
    category: ToolCategory.media,
    path: '/media/gif',
    icon: Icons.gif_box_rounded,
    keywords: ['animation', 'animated', 'meme', '动图', '表情'],
    builder: (_) => const GifTool(),
  ),
  ToolDefinition(
    id: 'transform',
    category: ToolCategory.media,
    path: '/media/transform',
    icon: Icons.auto_fix_high_rounded,
    keywords: ['speed', 'rotate', 'flip', 'vertical', 'tiktok', 'shorts', 'reels', '9:16', 'mute', '变速', '旋转', '竖屏'],
    builder: (_) => const TransformTool(),
  ),
  ToolDefinition(
    id: 'concat',
    category: ToolCategory.media,
    path: '/media/concat',
    icon: Icons.merge_rounded,
    keywords: ['join', 'merge', 'combine', 'append', '拼接', '合并'],
    builder: (_) => const ConcatTool(),
  ),
  ToolDefinition(
    id: 'frames',
    category: ToolCategory.media,
    path: '/media/frames',
    icon: Icons.photo_library_rounded,
    keywords: ['screenshot', 'thumbnail', 'snapshot', 'contact sheet', 'image', '截图', '抽帧', '缩略图'],
    builder: (_) => const FramesTool(),
  ),
  ToolDefinition(
    id: 'inspect',
    category: ToolCategory.media,
    path: '/media/inspect',
    icon: Icons.manage_search_rounded,
    keywords: ['ffprobe', 'metadata', 'info', 'codec', 'stream', '信息', '元数据'],
    builder: (_) => const InspectTool(),
  ),
  ToolDefinition(
    id: 'cli',
    category: ToolCategory.media,
    path: '/media/cli',
    icon: Icons.terminal_rounded,
    keywords: ['command', 'terminal', 'ffmpeg', 'args', 'custom', '命令'],
    builder: (_) => const CliTool(),
  ),
];
