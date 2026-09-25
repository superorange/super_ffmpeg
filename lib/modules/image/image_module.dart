import 'package:flutter/material.dart';

import '../../core/toolbox/tool.dart';
import 'logic/image_convert.dart';
import 'tools/image_convert_page.dart';

/// Image tools, powered by the bundled FFmpeg.
final imageTools = <ToolDefinition>[
  ToolDefinition(
    id: 'image_convert',
    category: ToolCategory.image,
    icon: Icons.photo_size_select_large_rounded,
    keywords: [
      'heic',
      'jpg',
      'jpeg',
      'png',
      'avif',
      'webp',
      'compress',
      'resize',
      'exif',
      'gps',
      'metadata',
      'tinypng',
      '图片',
      '压缩',
      '转换',
      '缩放',
      '尺寸',
      '元数据',
      '隐私',
    ],
    accepts: imageExtensions,
    builder: (_) => const ImageConvertPage(),
  ),
];

ToolDefinition imageTool(String id) => imageTools.firstWhere((t) => t.id == id);
