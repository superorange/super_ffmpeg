# Super Toolbox

本地优先的桌面全能工具箱（Flutter 3.47 · Dart 3.13 · macOS 优先）。所有处理都在本机完成。

**媒体工作室**：拖入一次视频，转换、压缩、剪辑、音频、GIF、变速画面、合并、截图、信息、命令行都在下方标签页里围绕它完成；
时间线（胶片条 + 入出点 + 播放头）被所有功能共享，任何重编码功能都可以「仅处理选区」。另有 **图片**、**数据 · JSON**、**前端开发**、
**编码与加密**、**文本**、**生成与时间** 共 37 个工具，首页拖入任意文件自动打开对应工具。
产品、设计与测试文档：[PRD](docs/PRD.md) · [设计规范](docs/DESIGN.md) · [测试计划](docs/TEST_PLAN.md)。

## 工具

| 分类 | 工具 |
| --- | --- |
| 媒体工作室 | 格式转换（GPU）· 视频压缩（按画质 / 目标大小两遍编码）· 剪辑（无损 / 精确）· 音频提取与响度标准化 · GIF · 变速旋转转竖屏 · 合并 · 截图抽帧缩略图墙 · 媒体信息 · 自定义命令 |
| 图片 | 图片压缩与转换：HEIC / WebP / PNG → JPG、AVIF、PNG、TIFF，批量缩放，清除 EXIF / GPS |
| 数据 · JSON | JSON 格式化（树视图、JSONPath、错误定位）· JSON 对比 · JSON ↔ YAML · JSON 生成代码（TS / Dart / Go / Swift / Kotlin）· CSV ↔ JSON |
| 前端开发 | HTML 实时预览（HTML+CSS+JS + 控制台）· JS 运行（JavaScriptCore）· Markdown 编辑器 · CSS 格式化 · 颜色工具（WCAG）· 正则测试 |
| 编码与加密 | Base64（文本 / 文件 / 图片）· 编码转换（URL、HTML 实体、Unicode、Hex、二进制）· URL 解析 · JWT 解码验签生成 · 哈希校验（含文件、HMAC）· 进制转换 |
| 文本 | 文本对比（词级高亮）· 命名转换 · 文本处理（统计、排序、去重）· 占位文本 |
| 生成与时间 | UUID / ULID / Nano ID · 密码 · 二维码 · 时间戳 · Cron |

## 架构

```
lib/
├── app/                 # 应用壳：路由、侧边栏、⌘K 命令面板、工具注册表
├── core/
│   ├── toolbox/         # ToolDefinition / ToolCategory / 搜索
│   ├── jobs/            # 通用后台任务队列（任何模块都可提交 JobSpec）
│   ├── settings/        # 持久化设置（shared_preferences）
│   └── utils/           # 格式化、时间码、shell 分词、输出命名、访达集成
├── ui/                  # 设计系统：tokens、主题、工作台积木（ToolScaffold/Pane/SplitPane/EditorPane/CodeArea/WebPreview）
└── modules/
    ├── home/ tasks/ settings/
    ├── media/
    │   ├── engine/      # ffmpeg 定位、能力检测、ffprobe、进度解析、进程执行、FFI 桥
    │   ├── builders/    # 纯函数：选项 → CommandPlan（含 applyClipRange 选区裁切）
    │   ├── studio/      # 媒体工作室：状态、预览舞台、时间线、标签页选项 + 运行栏
    │   └── tools/       # 10 个标签页
    ├── image/           # 图片压缩与转换（内置 FFmpeg，HEIC 平铺网格）
    ├── data/ web/ encode/ text/ generate/
    │   ├── logic/       # 纯 Dart 逻辑（全部单测覆盖）
    │   └── tools/       # 页面
    └── web/engine/      # JS 运行：macOS JavaScriptCore（jsc 子进程，超时强杀）
```

**引擎（内置 FFmpeg 9.0.2，GPL 全功能）**：app 自带 FFmpeg，不依赖系统安装。混合调用：

| 场景 | 方式 | 原因 |
| --- | --- | --- |
| 转码任务 | 内置 `ffmpeg` 可执行文件（`Contents/MacOS/ffmpeg`），参数数组启动、`-progress pipe:1` 取进度 | 与进程内同速；多任务并行、崩溃隔离、取消即终止 |
| 媒体信息 / 缩略图 / 预览帧 | FFI 进程内调用 libavformat/libavcodec（`native/src/media_bridge.c`） | 无进程开销：探测 ~2.6 ms（ffprobe ~14 ms），解帧 ~8 ms，直接得到 RGBA，无临时文件 |

编码器：x264、x265（8/10/12-bit）、SVT-AV1、libvpx（VP9）、Opus、LAME，加上 VideoToolbox 硬件编解码和 dav1d（AV1 解码）。
查找顺序：设置里指定的目录 → 内置 → 系统（仅作兜底）。

**新增一个工具**：在模块 `logic/` 写纯函数并单测 → 用 `ToolScaffold` + `Pane`/`EditorPane` 写页面 → 在模块列表加
`ToolDefinition`（`accepts` 声明可打开的扩展名）→ 在 `tool/gen_i18n.py` 加文案。首页、侧边栏、⌘K、路由、首页拖放自动生效；
冒烟测试会自动打开新页面检查布局。

## 开发

```bash
brew install nasm cmake meson ninja pkg-config   # 构建工具（仅开发机需要）
scripts/build_ffmpeg.sh                          # 从官方源码构建内置 FFmpeg → vendor/ffmpeg/darwin-arm64（首次约 15 分钟，之后增量）
fvm flutter pub get
fvm flutter run -d macos                         # Xcode 的 "Embed FFmpeg" 阶段自动把 FFmpeg 打进 .app 并签名
fvm flutter analyze
fvm flutter test                                 # 单元 + 组件 + 真实 FFmpeg 集成测试（使用 vendor 下的内置构建）
fvm flutter test test/screenshots --run-skipped  # 渲染 34 张设计走查截图到 build/screenshots/
SUPER_TOOLBOX_ROUTE=/tool/json build/macos/Build/Products/Debug/super_ffmpeg.app/Contents/MacOS/super_ffmpeg  # 直接打开某页
build/macos/Build/Products/Debug/super_ffmpeg.app/Contents/MacOS/super_ffmpeg clip.mp4 a.json                 # 命令行传入文件
python3 tool/gen_i18n.py                         # 翻译唯一来源 → assets/translations/*.json
```

- 所有源码按版本锁定并校验 SHA256（见 `scripts/build_ffmpeg.sh` 顶部）；升级 FFmpeg 只需改版本和哈希后重跑。
- 目前只构建 arm64（Apple Silicon）。`ARCH=x86_64 scripts/build_ffmpeg.sh` 构建 Intel 版后，嵌入脚本会自动合并为通用二进制。
- 修改 `native/src/media_bridge.c` 后只需运行 `scripts/build_media_bridge.sh`。

## 许可

内置的 FFmpeg 以 **GPL** 配置构建（含 x264、x265 等 GPL 组件）。分发本应用时，整个应用须以 GPL 兼容许可发布，并提供对应源码（构建脚本 + 锁定的上游源码地址）。
