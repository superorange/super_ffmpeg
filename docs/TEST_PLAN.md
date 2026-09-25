# Super Toolbox — 测试计划

## 测试金字塔

| 层 | 位置 | 内容 | 依赖 |
| --- | --- | --- | --- |
| 单元 | `test/unit/builders_test.dart` `engine_parsing_test.dart` `utils_test.dart` `job_queue_test.dart` | 媒体命令构建器、进度/ffprobe 解析、时间码、shell 分词、输出命名、任务队列 | 无 |
| 单元 | `test/unit/studio_state_test.dart` | 工作室状态（素材库、每文件播放头/选区、入出点、移除后激活邻居）、`applyClipRange`、`MediaInfo.clipped`、GIF 片段规则 | 无 |
| 单元 | `test/unit/devtools_logic_test.dart` | JSON（格式化/错误行列/转义/JSONPath/结构 diff）、YAML/CSV 往返、代码生成 5 语言、Base64/URL/HTML/Unicode/Hex、JWT（jwt.io 向量、签名）、哈希（标准向量、CRC32、HMAC）、进制、Myers diff 与词级 diff、命名转换、统计、UUID v7/ULID 时间反解、密码熵、时间解析、Cron 下次运行、颜色与 WCAG、CSS 格式化/压缩 | 无 |
| 单元 | `test/unit/js_engine_test.dart` | JavaScriptCore 运行：结果值、console、行号报错、Promise + 定时器顺序、死循环超时强杀、运行间隔离 | macOS `jsc` |
| 质量门禁 | `test/unit/registry_i18n_test.dart` | 代码中每个翻译 key（含动态拼接的）在中英文都存在；两种语言 key 集一致；工具 id 唯一；搜索排序 | 无 |
| 组件 | `test/widget/app_test.dart` | 首页分类与拖放区、卡片跳转、⌘K 打开工作室标签、**全部工具页冒烟（逐个打开，无布局溢出/异常）**、工作室：批量范围、仅选区命令含 `-ss/-t`、剪辑需选区、I/O/Esc 快捷键、目标大小预算随选区变化、合并用素材库、引擎缺失；任务中心；主题持久化；中文 | 引擎/探测/缩略图/WebView 用 Fake |
| 组件 | `test/widget/devtools_test.dart` | JSON（错误定位、JSONPath、压缩、树视图）、JSON 对比、生成代码切换语言、YAML 交换、JWT 验签、正则（分组、替换、非法表达式）、哈希比对、Base64 双向、编码转换交换、文本 diff、时间戳识别、Cron、进制前缀、UUID 数量、命名转换、文件投递到工具 | 同上 |
| 集成 | `test/integration/native_media_test.dart` | FFI 探测与解帧 | 内置 FFmpeg |
| 集成 | `test/integration/media_engine_test.dart` | 每个媒体构建器真实执行并校验输出；**仅选区**转换时长 = 选区、两遍目标大小不超标；**图片**：PNG→JPG/AVIF/PNG/TIFF 缩放、有损体积、HEIC 平铺网格（整图尺寸、按组缩放、缩略图 3:2） | 内置 FFmpeg（其次系统） |
| 视觉 | `test/screenshots/` | 34 张设计走查图（深浅色、工作室各状态、每个开发工具、窄窗口）→ `build/screenshots/` | 系统字体 |

## 关键用例

1. **一次拖入**：工作室载入文件后切换任意标签都作用于同一文件；批量范围切换后任务数 = 文件数。
2. **仅选区**：选区 5–20s 的转换命令为 `-ss 5 -t 15 -i …`；关闭开关后命令恢复；目标大小按选区时长分配码率。
3. **命令安全 / 不覆盖 / 取消清理 / 进度单调**（沿用 v0.3）。
4. **HEIC**：平铺网格按整图处理，缩放经 `-filter_complex [0:g:0]`。
5. **JS 隔离**：死循环 5 秒内被杀；上一次运行定义的全局变量下一次不可见。
6. **i18n**：新增任何 `'ns.key'.tr()` 必须在 `tool/gen_i18n.py` 登记，否则门禁失败。

## 运行

```bash
fvm flutter test                                  # 全部（有 FFmpeg 时包含集成测试）
fvm flutter test test/unit test/widget            # 仅快速测试
fvm flutter test test/screenshots --run-skipped   # 渲染设计走查截图
fvm flutter analyze
```

真机走查：`SUPER_TOOLBOX_ROUTE=/tool/json build/macos/Build/Products/Debug/super_ffmpeg.app/Contents/MacOS/super_ffmpeg [文件…]`
可直接打开某页或用命令行传入文件（媒体进工作室，其它进对应工具）。
