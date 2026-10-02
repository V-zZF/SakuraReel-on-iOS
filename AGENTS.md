# SakuraReel — Codex 工作记忆

## 项目定位

SakuraReel 是一款 **Personal Media Library** 应用，用于：
- 收藏影视作品
- 记录观看状态（看过 / 在看 / 想看）
- 记录观看年月
- 记录个人评分（0–10）
- 保存个人短评
- 保存播放入口
- 数据以本地文件形式保存在 App 的 Documents 目录，可在系统「文件」App 中直接查看 / 备份

它不是影视资讯 App，也不是影视社区。第一阶段所有内容均由用户手动添加，不接入 TMDB、Bangumi、豆瓣等外部数据源。

## 核心原则

1. **数据正确 > 视觉效果**
2. **优先原生 SwiftUI，不自己模拟系统组件**
3. **不擅自增加产品功能**
4. **不改变已定规则**：评分范围、评分颜色、首页排序、排行榜排序、同组拖动限制、卡片布局、浅色樱花粉视觉方向
5. **发现技术冲突时**：先指出问题，给出最符合 Apple 原生设计的方案，再修改代码

## 技术栈

- **语言**：Swift 6.3+
- **UI**：SwiftUI
- **数据持久化**：本地 JSON 文件（App 沙盒 Documents 目录，可在「文件」App 中查看、备份）
- **海报存储**：单独图片文件（`Documents/Posters/<id>.jpg`），不写入 JSON
- **图片选择**：PhotosPicker
- **外部链接**：UIApplication.shared.open
- **最低系统版本**：iOS 18+（`@Observable` 依赖 Observation 框架）
- **无第三方 UI 框架**
- **无第三方影视数据库 API**
- **无 iCloud / CloudKit 同步**：数据只存在本机

## 项目目录

```
SakuraReel
├── App/
├── Models/
├── Views/
├── Components/
├── Services/
└── Utilities/
```

## 关键文件

| 文件 | 职责 |
|------|------|
| `Models/MediaItem.swift` | 核心数据模型（Codable 结构体） |
| `Models/MediaStatus.swift` | 观看状态枚举 |
| `Utilities/RatingColor.swift` | 评分颜色唯一来源 |
| `Utilities/MediaSort.swift` | 排序与拖动分组逻辑唯一来源 |
| `Services/MediaRepository.swift` | 本地 JSON 文件读写、海报文件管理、CRUD 与排序索引维护 |
| `Services/PosterResizer.swift` | 海报裁剪、缩放、压缩 |
| `Views/HomeView.swift` | 首页 |
| `Views/RankingsView.swift` | 排行榜 |
| `Views/AddEditMediaView.swift` | 添加 / 编辑页 |
| `Components/MediaCard.swift` | 影视卡片 |
| `Components/AdaptiveGridLayout.swift` | iPhone / iPad 自适应网格 |
| `Utilities/RankingMetrics.swift` | 排行榜卡片尺寸唯一来源（一屏几张 → 卡高 → 卡内等比缩放） |

## 数据模型要点

- `MediaItem` 是 `Codable` 结构体（同时 `Identifiable, Hashable`），**不是** `@Model`
- 元数据写入 `Documents/SakuraReelLibrary.json`（`.prettyPrinted`，日期 `.iso8601`）
- `poster` 只在内存中使用，不参与 JSON 编解码；海报单独存为 `Documents/Posters/<id>.jpg`
- `rating` 为整数 0–10，`0` 表示未评分
- `sortIndex` 用于首页「同观看年月」组内手动排序
- `rankIndex` 用于排行榜「同评分」组内手动排序（`nil` = 该评分组未手动排过）
- `watchYear` / `watchMonth` 单独存储，便于按年月分组排序

## 评分颜色规范

评分颜色必须唯一来自 `RatingColor.color(for:)`：

| 分数 | Hex | 视觉 |
|------|-----|------|
| 0 未评分 | `#E5E5EA` | 浅灰 |
| 1–3 | `#C7C7CC` | 浅灰 |
| 4–5 | `#F8A5B6` | 浅粉 |
| 6–7 | `#F08080` | 珊瑚粉 |
| 8–9 | `#E88398` | 深粉 |
| 10 | `#E2556B` | 红粉 / 满分特殊色 |

## 排序规则

### 首页默认排序
1. 观看年份从新到旧
2. 观看月份从新到旧
3. `sortIndex`

### 首页手动排序
- 只能在**同年同月**内拖动
- 跨年月拖动显示提示：「无法移动 只能调整相同观看年月内的作品顺序。」

### 排行榜排序
1. 评分从高到低
2. `rankIndex`（只有被手动排过的评分组有值，整库未手动排序时此条不生效）
3. 观看时间从新到旧
4. `sortIndex`

### 排行榜手动排序
- 只能在**同评分**内拖动
- 跨评分拖动显示提示：「无法移动 只能调整相同评分内的作品顺序。」

## 排行榜卡片尺寸

卡片大小不写死成 pt，而是量化成「**一屏放几张**」：

- `RankingMetrics.cardsPerScreen = 5` —— 卡片高度 = 高度预算 ÷ (5 + 4×间距比 + 2×留白比)，一屏正好铺下 5 张卡 + 4 个间距 + 上下留白
- **高度预算按屏幕形态分两种**：
  - iPhone（竖横都算）与 iPad **横屏**：用列表**可用高度** → 一屏正好 5 张
  - iPad **竖屏**：改用列表**可用宽度**（竖屏的宽度就是横屏时的屏高）→ 卡高与横屏同一档，屏再高也不会把卡片撑成巨无霸；代价是竖屏不再「一屏 5 张」，一屏能放多少放多少
- 卡内所有元素（海报、片名、`#` 序号、日历图标、观看年月、评分数值、圆角、阴影）都按「卡高 ÷ 基准卡高 90」等比缩放，少算一处就不再等比
- 海报宽度由卡高按 2:3 反推，卡高实际由海报决定；片名允许 2 行（`lineLimit(2)`），不会把卡片撑高
- 列宽：iPhone 与 iPad 竖屏铺满可用宽度；iPad **横屏**收窄并**居中** —— 卡片宽度按「半屏宽一列的卡片 × `padCardWidthMultiplier`（1.2）」算，否则铺满整屏会把卡片拉成一条长带
- 居中靠整列两侧各垫一个 `Spacer`：`ScrollView` 会把内容按 leading 摆放，**只给固定宽度并不会居中**
- iPad 判定与 `AdaptiveGridLayout` 同一套：`horizontalSizeClass == .regular && verticalSizeClass != .compact`；竖横判定直接比 `availableSize` 的宽高
- 卡内字号由卡高算出，**不跟随系统动态字体** —— 这是「一屏几张」的代价

## 视觉方向

- **主背景**：白色、极浅灰、极浅暖灰
- **卡片**：白色、柔和圆角、极轻阴影
- **主文字**：深灰 / 近黑
- **次级文字**：系统灰
- **品牌强调**：樱花粉，仅用于选中态、按钮、评分高区间，不作为大面积背景
- **海报**：2:3 比例，卡片视觉中心
- **信息层级**：海报 > 片名 > 评分 > 观看年月 > 播放入口

## 交互要点

- 首页分类选择器：原生 Segmented Picker（看过 / 在看 / 想看）+ 右端独立的放大镜按钮
- 点放大镜在胶囊行**下方**滑出搜索栏（弹簧动画），实时按**片名**过滤（`localizedStandardContains`）
- 搜索**忽略当前分类**、跨看过 / 在看 / 想看全局搜；**不搜短评**；没命中时显示「无搜索结果」空态；点「取消」退出并清空关键词
- 点分类胶囊会退出搜索；进排序模式前先退出搜索（排序模式必须显示全部条目）
- 添加 / 编辑为 Sheet，表单顺序固定：海报 → 片名 → 分类 → 观看年月 → 评分 → 短评 → 播放链接
- 播放链接存在时才显示播放按钮，点击用 `UIApplication.shared.open` 打开外部目标
- 删除需要二次确认 Alert
- 未保存内容时，用户点击取消 / 遮罩 / 返回需提示确认

## 注意事项

- 不要为了简单而引入第三方 UI Framework
- 不要把整个 App 写在一个巨大 View 文件中
- 不要把排序逻辑散落在多个 View 中
- 不要把排行榜卡片的尺寸写死在 View 里（走 `RankingMetrics`）
- 不要在不同页面重复硬编码评分颜色
- 不要默认接入外部影视数据源
- 不要重新引入 SwiftData / CloudKit / iCloud 同步
- 不要在大面积使用粉色
- 不要添加复杂动画
- 保持 Light Mode，不考虑深色模式

## 本地文件存储

- 数据保存在 App 沙盒的 `Documents` 目录，用户可在「文件」App 的 **我的 iPhone > SakuraReel** 中直接查看
- 目录结构：
  - `SakuraReelLibrary.json`：所有条目的元数据（片名、分类、年月、评分、短评、链接、排序）
  - `Posters/`：海报图片，按 `<条目 id>.jpg` 命名
- `Info.plist` 已开启 `UIFileSharingEnabled` 与 `LSSupportsOpeningDocumentsInPlace`，用于暴露 Documents 目录
- 读写走 `MediaRepository`（`@MainActor @Observable`），不直接操作 FileManager
- 不建立 SakuraReel 自己的账号体系，不接入 iCloud / CloudKit

## 开发节奏

按 Phase 推进，每完成一个小里程碑更新 `DEVLOG.md`。先保证数据正确，再做视觉效果。
