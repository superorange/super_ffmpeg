# Super Toolbox — 设计规范

方向：**精致、有活力的专业工具**（参考 Raycast / Linear / Arc）。深浅两套中性底色，
品牌紫色渐变作强调，每个分类一组渐变色作身份标识；靠层级、留白和细边框区分区域，
浅色模式用柔和阴影、深色模式用细描边。

## 1. 设计令牌（`lib/ui/theme/tokens.dart`）

### 颜色

| Token | Dark | Light | 用途 |
| --- | --- | --- | --- |
| `bg` | `#0C0C10` | `#F6F6F9` | 窗口底色 |
| `sidebar` | `#111116` | `#EEEEF3` | 侧边栏 |
| `surface` | `#16161C` | `#FFFFFF` | 卡片 / 面板 |
| `surfaceAlt` | `#1D1D25` | `#F3F3F7` | 输入框、分段控件底 |
| `elevated` | `#23232C` | `#FFFFFF` | 选中分段、弹出层、对话框 |
| `border` / `borderStrong` | `#26262F` / `#363642` | `#E4E4EB` / `#D2D2DC` | 描边 |
| `text` / `textMuted` / `textSubtle` | `#F1F1F4` / `#A3A3B2` / `#6C6C7C` | `#16161D` / `#585866` / `#9696A6` | 文字三级 |
| `accent` → `accent2` | `#7C6CFF` → `#C06CFF` | `#6554F0` → `#A64DF5` | 品牌渐变：主按钮、Logo、选中 |
| `success` / `warning` / `danger` / `info` | `#34D399` `#FBBF24` `#FB7185` `#60A5FA` | `#10A36B` `#D08700` `#E11D48` `#2563EB` | 状态 |
| `stage` | `#050507` | `#0B0B0E` | 媒体预览舞台（始终近黑） |
| `codeBg` | `#101015` | `#FAFAFC` | 编辑器、命令块 |

`cardShadow`（仅浅色）与 `popShadow` 由 `shadow` 派生。

### 分类渐变（`ToolCategory`，色相环均匀分布）

媒体 `#F43F5E→#FB923C` · 图片 `#F97316→#FBBF24` · 数据 `#3B82F6→#22D3EE` · 前端 `#06B6D4→#34D399` ·
编码 `#8B5CF6→#D946EF` · 文本 `#10B981→#A3E635` · 生成 `#EAB308→#F97316` · 文件 `#64748B→#94A3B8`。

`ToolIcon.of(tool)`：渐变实底 + 白色图标 + 同色投影，用于工具身份（卡片、页头、最近使用）；
侧边栏只用分类色的图标，不加底块。

### 字号 · 间距 · 圆角 · 动效

`display 28/700` · `title 19/600` · `heading 14/600` · `body 13` · `label 12/500` · `caption 11` · `overline 10.5/600` · `mono 12.5 Menlo`

4pt 网格（4 · 8 · 12 · 16 · 20 · 24 · 32）；圆角 控件 8 · 卡片 12 · 面板 16；
动效 `fast 120ms` / `normal 180ms` / `slow 260ms`，曲线 `easeOutCubic`。

## 2. 布局

### 2.1 外壳

```
┌ Sidebar 244 ─┬──────────────────────────────────────────┐
│ Logo · ⌘K    │  页面                                      │
│ 首页 · 任务   │                                           │
│ ▣ 媒体工作室  │                                           │
│ 数据 · JSON 5 │                                           │
│   JSON 格式化 │                                           │
│ 前端开发 6 …  │                                           │
│ 设置 · 引擎   │                                           │
└──────────────┴──────────────────────────────────────────┘
```

侧边栏分类可折叠，当前工具所在分类始终展开；仅路线图的分类排在最后；< 900px 收成图标栏。

### 2.2 工具页（`ToolScaffold`，`lib/ui/widgets/workbench.dart`）

页头（渐变图标 · 标题 · 描述 · 右侧操作）→ 工具栏（`ToolbarRow` / `ToolbarField`，模式、选项）→ 主体。
主体一般为 `SplitPane`（可拖动分隔条，双击复位，窄屏自动上下堆叠）+ 两个 `Pane`：

- `Pane`：40px 标题栏（标题 · 标题旁控件 · 右侧 `PaneAction`）、内容、可选状态脚（`StatusLine`）。`shrinkWrap` 用于按内容定高。
- `EditorPane` = `Pane` + `CodeArea`（re_editor：行号、按主题配色的语法高亮）+ 粘贴/打开/保存/复制/清空。
- `ValueRow`：标签 + 等宽值 + 悬停复制，用于多结果（哈希、时间、颜色格式…）。
- 所有工具页接受拖放文件（`ToolScaffold.onFiles`，拖入时整页描边高亮）。

### 2.3 媒体工作室

```
素材库条（文件胶囊，当前文件高亮） ─────────────── 添加 · 访达 · 清空
预览舞台（高度 = 可用高度 40%，170–440）         │ 文件信息卡 290（≥1040px）
时间线：胶片条 + 入/出点手柄（黄色=已选区）+ 播放头 · 入点/出点/选区 · 设为入点/出点/全选
功能标签（图标 + 名称，下划线选中）
选项网格（OptionsGrid，最小列宽 300，1–3 栏）
运行栏：范围开关 · 仅选区 · 输出位置 → 文件名 · </> · [开始 · N]
```

空状态：大拖放区（媒体渐变 + 圆形图标）+「载入后可以」的 10 个能力卡（点击 = 选中该标签并打开文件选择）。

## 3. 组件（`lib/ui/widgets/`）

| 组件 | 说明 |
| --- | --- |
| `ToolScaffold` `ToolbarRow` `ToolbarField` | 工具页骨架与工具栏 |
| `Pane` `SplitPane` `PaneAction` `CopyAction` `StatusLine` `ValueRow` `TextArea` | 工作台积木 |
| `CodeArea` `EditorPane` | 代码编辑器（10+ 语言高亮） |
| `WebPreview` | WebKit 预览，注入 console 桥（测试中由 provider 关闭） |
| `Segmented<T>`（`expand:false` 用于工具栏，`dense`） `ChoiceChips<T>` `SelectableChip` `LabeledSlider` `AppSwitch` | 选择控件 |
| `AppButton`（primary 为品牌渐变 + 光晕） `AppIconButton` | 按钮 |
| `Panel` `OptionField` `OptionRow` `Notice` `Tag` `ToolIcon` `CommandPreview` `EmptyState` | 通用 |

## 4. 交互原则

1. **即输即得**：开发类工具无「转换」按钮，输入即计算；昂贵计算（Markdown 渲染、HTML 预览）防抖 250–450ms。
2. **拖一次**：文件拖入后在同一工作区完成所有操作；首页拖任何文件都能找到去处。
3. **默认即最佳**：示例数据预填，打开就能看到工具在做什么。
4. **可预期**：按钮显示结果数量（「开始转换 · 3」）；运行栏显示将生成的文件名；错误就地说明（行列号、原因）。
5. **可逃生**：任务可取消且不留残缺文件；文本工具提供撤销与复制。
6. **键盘**：⌘K 搜索；工作室 I/O 入出点、←/→ 逐帧（⇧ 1 秒）、Home/End、Esc 清除选区；JS 运行 ⌘↩。
