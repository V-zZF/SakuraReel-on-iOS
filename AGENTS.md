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

它不是影视资讯 App，也不是影视社区。支持手动添加和用户主动从 TMDb 快捷录入。2026-10-02 用户授权接入 TMDb 搜索及详情，此授权替代早期不接入外部数据源的限制；不扩展其他外部数据源。TMDb 仅作一次性导入，后续作品资料可自行修改，主动重新获取必须经过字段预览。

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
- **外部数据源**：TMDb（Foundation + URLSession），仅用户主动搜索／获取
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

- `LibraryEntry` 是不含图片字节的 Codable 持久化条目；`MediaItem` 是包含条目与可选图片载荷的独立编辑／传输草稿，不是 `@Model`
- JSON 根为 `LibraryDocument`：`schemaVersion = 1`、`libraryID`、`revision`、条目与分组顺序；不读取旧格式、不提供迁移
- 条目按 `WorkDetails`、`PersonalRecord`、类型化 `TMDbIdentity` 与 `AttachmentManifest` 分工；观看年月使用完整的可选 `YearMonth`
- 本地 UUID 和 TMDb 身份分开；来源语言与获取时间不参与判重
- 元数据写入 `Documents/SakuraReelLibrary.json`（`.prettyPrinted`，日期 `.iso8601`）
- `poster` 只在内存中使用，不参与 JSON 编解码；海报单独存为 `Documents/Posters/<id>.jpg`
- `rating` 为整数 0–10，`0` 表示未评分
- 首页仅持久化 `homeGroups` 中的年月组内 UUID 顺序；排行榜仅持久化 `rankingGroups` 中手动评分组的 UUID 顺序
- 删除 `sortIndex` / `rankIndex`；没有整库重复顺序数组
- 所有读入、导入和写入统一校验，不静默修复非法数据；仓库管理时间戳，排序不改变内容时间戳
- 文件工作由串行 `LibraryStorage` actor 执行，提交成功后仓库才发布数据；图片按需加载，列表不携带字节

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
3. 年月组内 UUID 顺序；新添加作品插入对应年月组首位，普通编辑不改变组内位置

### 首页手动排序
- 只能在**同年同月**内拖动
- 跨年月拖动显示提示：「无法移动 只能调整相同观看年月内的作品顺序。」

### 排行榜排序
- 仅“看过”参与排行榜，“在看”和“想看”不参与展示、名次或拖动排序。
1. 评分从高到低
2. 手动评分组的 UUID 顺序（未手动评分组跳过）
3. 观看时间从新到旧
4. 首页年月组内顺序

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
- 排行榜 iPad 判定：`horizontalSizeClass == .regular && verticalSizeClass != .compact`；竖横判定直接比 `availableSize` 的宽高
- 卡内字号由卡高算出，**不跟随系统动态字体** —— 这是「一屏几张」的代价

## 视觉方向

- **主背景**：白色、极浅灰、极浅暖灰
- **卡片**：白色、柔和圆角、极轻阴影
- **主文字**：深灰 / 近黑
- **次级文字**：系统灰
- **品牌强调**：樱花粉，仅用于选中态、按钮、评分高区间，不作为大面积背景
- **海报**：2:3 比例，卡片视觉中心
- **信息层级**：海报 > 片名 > 评分 > 观看年月 > 播放入口

## 网格窗口自适应（2026-10-02）

- 首页与排序模式共用 `AdaptiveGridLayout` 和 `GridColumns`，按当前内容区可用宽度实时计算列数。
- 一行五张仅作卡片尺寸参考，不是固定列数或上限；不以设备型号、横竖屏或尺寸类限制列数。
- iPad 窗口缩放／分栏、iPhone 与 iPad 旋转时，由外层 GeometryReader 直接传入当前视口宽度并重新排布；不缓存宽度，也不从被网格撑宽的背景反向测量。每张卡片连同分摊的周围间隙按477.6屏幕像素占宽（2026-10-03 用户明确以iPad Pro 11寸默认横屏一行五张为尺寸基准：2388px ÷ 5；新版2420px横屏同样五列），通过当前环境displayScale换算pt；列数为可用像素宽度除以477.6向下取整，至少一列，剩余宽度由各列均分。间距及两侧留白16pt。

- TMDb 搜索结果按用户参考图改为满宽横向卡片：左侧海报，右侧片名、完整日期与最多三行简介；右上角与片名并排放置操作按钮：剧集显示“单季”并进入季度选择，电影显示“选择”。搜索结果不再使用550px海报网格。

## 交互要点

- 首页分类选择器：原生 Segmented Picker（看过 / 在看 / 想看）+ 右端独立的放大镜按钮
- 点放大镜在胶囊行**下方**滑出搜索栏（弹簧动画），实时按**片名**过滤（`localizedStandardContains`）
- 搜索**忽略当前分类**、跨看过 / 在看 / 想看全局搜；**不搜短评**；没命中时显示「无搜索结果」空态；点「取消」退出并清空关键词
- 点分类胶囊会退出搜索；进排序模式前先退出搜索（排序模式只显示当前分类的全部条目，三个分类独立排序，保存时不改变其他分类顺序）
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
- 除用户授权的 TMDb 外，不要接入其他影视数据源；不自动刷新资料库
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

## TMDb 与作品资料（2026-10-02）

- `MediaItem.source` / `metadata` 是可选 Codable 值；图片字节不写 JSON。
- 永久附件：`Posters/<UUID>.jpg`、`Artwork/<UUID>/backdrop.jpg`、`Artwork/<UUID>/logo.png`。完整备份必须包含两种目录。
- 来源身份区分电影、剧集、季度；季度包含父剧集和季号，语言与获取时间不参与重复判断。
- 首次导入和主动重新获取均通过独立草稿与字段预览。默认仅填空字段，所有个人记录及两套顺序保持原规则。
- 作品资料可在独立编辑页修改；打开详情不自动获取远端资料。用户填写的 Key 只存 Keychain，默认直连。2026-10-02 用户授权复用 AniShelf 网络方案，设置中可主动选择其两条 API 代理；只在该代理组内故障切换，不将直连或自定义代理请求自动转发给第三方。图片仍直连 TMDb CDN。
- 加号默认打开 TMDb 搜索；未配置 Key 时显示可跳过的官网指引与下方高亮 API 输入框，搜索页底部提供手动添加，不显示 TMDb／收藏库切换。
- 用户授权的默认 API 凭据由 Git 忽略的 `Configuration/TMDb.local.xcconfig` 供构建注入，点击跳过后写入 Keychain；不要把凭据提交到源码、收藏库或导出文件。未提供本地配置的构建应保留个人 Key 与手动添加入口。
- 运行 `./Scripts/run-model-tests.sh` 和 `./Scripts/run-tmdb-tests.sh`，再完成通用模拟器构建；不要擅自启动模拟器。

## 双向增量同步（2026-10-06）

- 首页只保留「同步」入口，使用系统选择的授权文件夹；用户主动发起，不接入 CloudKit、自建账号或后台自动同步。
- `SakuraReelSync.json` 为独立版本化清单，保存字段／附件／排序时钟、图片 SHA-256 与大小、删除历史和 UUID 别名；资料库 schemaVersion 仍为 1。完整备份应同时保存该清单、资料库 JSON、Posters 和 Artwork。
- 各属性独立合并，同字段最后修改优先；同时间用稳定操作标识确定结果。观看年月、TMDb 身份和数组分别作为完整值。删除传播，但删除与未同步修改冲突必须通过原生 Sheet 选择保留／删除，取消不提交。
- 首次没有同步历史时合并两端，不把缺失作品推断为删除。同一类型化 TMDb 身份归并到稳定 UUID 并保存别名；无来源的手动作品不按片名合并。
- 首页按年月和分类保留独立排序，排行榜按手动评分组保留排序；冲突采用较晚排序，新成员位置沿用原规则。排序不修改作品内容时间。
- 未变化图片不得读取或重写；JSON 有变化时完整写入该文件。旧文件夹首次建立摘要可全量读取一次。有效清单与资料库摘要不符时重新校验并停止提交，等待文件提供商送达一致快照；损坏或丢失清单通过可信基线重建，无基线则停止，不能丢弃删除历史。
- 由 LibrarySyncMerger／LibrarySyncDisk／LibrarySyncCoordinator 分别管理合并、文件事务、双端提交；仓库提交成功后发布状态。LibraryStorage actor 执行磁盘工作，同一文件协调器覆盖 JSON 锁与嵌套读写，不能在主线程等待文件提供商。
- 文件级事务仅暂存和备份变化文件，保留旧版目录事务恢复。新事务记录安装实例 owner，只有创建者可恢复，不能把云盘送达的其他设备进行中事务误判为本机中断。Application Support 按目标保存检查点与成功基线；只有两端成功后推进基线。提交前检查两端精确元数据摘要，过期预览重新比较。
- 读写字节数含变化文件的回滚备份，不代表云盘网络流量。协议默认图片由新版 App 管理，其他工具直接修改图片不在可靠增量判定范围。删除历史暂不清理，避免离线设备复活作品。
