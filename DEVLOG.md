# SakuraReel 开发日志

## Phase 1 — 基础架构

- [x] 创建 Xcode 项目（iOS 17+，SakuraReel 名称）
- [x] 建立目录结构：App / Models / Views / Components / Services / Utilities
- [x] 创建 `Models/MediaStatus.swift`
- [x] 创建 `Models/MediaItem.swift`（Codable 结构体；`poster` 不入 JSON，单独存为 `Documents/Posters/<id>.jpg`）
- [x] 创建 `Utilities/RatingColor.swift`（评分颜色唯一来源）
- [x] 创建 `Utilities/MediaSort.swift`（排序与拖动分组逻辑）
- [x] 创建 `Utilities/Constants.swift`（樱花粉、圆角、间距等常量）
- [x] 创建 `Services/MediaRepository.swift`（本地 JSON 文件读写 + 海报文件管理，替代 SwiftData / CloudKit）
- [x] ~~创建 `Services/CloudKitConfiguration.swift`~~（2026-08-22 移除）
- [x] ~~配置 `App/SakuraReel.entitlements` 与 iCloud / CloudKit capability~~（2026-08-22 移除）
- [x] ~~配置 `App/SakuraReelApp.swift` 的 `ModelContainer`~~（2026-08-22 改为 `MediaRepository` + `.environment` 注入）
- [x] 开启文件共享：Info.plist 配置 `UIFileSharingEnabled`、`LSSupportsOpeningDocumentsInPlace`，数据可在「文件」App 查看
- [x] 创建空壳 `Views/ContentView.swift`、`HomeView.swift`、`RankingsView.swift`
- [x] 编译通过并在 iPhone 模拟器运行

## Phase 2 — 首页

- [x] 实现首页顶部三段式导航（排序 / SakuraReel / 排行）
- [x] 实现排序模式顶部导航（✕ / SakuraReel / 完成）
- [x] 实现分类选择器：看过 / 在看 / 想看（UISegmentedControl）+ 独立搜索按钮
- [x] 实现 `Components/PosterPlaceholderView`
- [x] 实现 `Components/PosterView`
- [x] 实现 `Components/RatingLabel`（大字数字 + 小字「分」）
- [x] 实现 `Components/PlayButtonOverlay`
- [x] 实现 `Components/MediaCard`（2:3 海报、片名、评分、年月、播放按钮）
- [x] 实现 `Components/AdaptiveGridLayout`（iPhone 2 列 / iPad ~5 列）
- [x] 实现 `Components/EmptyStateView`
- [x] 实现 `Components/AddButton`
- [x] 组装 `HomeView`：分类切换、网格、空状态、添加按钮
- [x] 在预览/模拟器中添加测试数据验证布局

### 2026-08-21 首页基础版
- 完成 HomeView 基础版：三段式导航、排序模式切换、分类胶囊、搜索栏、自适应网格、空状态、FAB
- 完成 `MediaCard`、`EmptyStateView`、`AddButton`、`PreviewSampleData`
- 组件内联实现海报占位/海报/评分/播放按钮，AdaptiveGridLayout 内联于 HomeView
- 编译通过，可在 iPhone / iPad 预览运行

### 2026-08-21 组件拆分完成
- 从 MediaCard / HomeView 中提取：
  - `PosterPlaceholderView`
  - `PosterView`
  - `RatingLabel`
  - `PlayButtonOverlay`
  - `AdaptiveGridLayout`
- 更新 `project.pbxproj` 注册所有新组件文件
- 编译通过

### 2026-08-22 分类选择器改为原生 Segmented Picker
- 分类选择器改为 SwiftUI `Picker(.segmented)`（原生 UISegmentedControl），遵循系统呈现与横向滑动切换手势
- 文字外观：选中项樱花粉加粗 14pt、未选中浅灰；搜索按钮从分段中拆出，独立置于选择器右侧（樱花粉放大镜）
- 选择器行移至标题（SakuraReel）下方内容区，标题保留原 26pt 圆体樱花粉；搜索框激活时从选择器下方弹簧滑入
- 修复：工具栏内 `.tint()` 不生效导致搜索图标渲染为黑色，改用 `.foregroundStyle(Constants.accentPink)`
- 验证：模拟器运行 + 像素采样确认选中粉 / 未选中灰 / 搜索图标粉，且不遮挡两侧导航按钮

## Phase 3 — 添加 / 编辑

- [x] 创建 `Services/MediaRepository.swift`（本地 JSON 文件 CRUD 与海报文件管理；排序索引维护在 Phase 4）
- [x] 创建 `Services/PosterResizer.swift`（居中裁剪为 2:3、缩放到 ≤900px、JPEG 0.85 压缩）
- [x] 创建 `Components/PosterImagePicker.swift`（PhotosPicker 封装，选中即压缩写入）
- [x] 创建 `Components/YearMonthPickers.swift`（年 + 月原生 Picker，未设年份时隐藏月份）
- [x] 实现 `AddEditMediaView` Sheet 骨架
- [x] 实现表单字段：片名、分类、观看年月、评分、短评、播放链接
- [x] 实现添加模式底部按钮：[取消] [保存]
- [x] 实现编辑模式底部按钮：[删除] [取消] [保存]
- [x] 实现删除二次确认 Alert
- [x] 实现未保存内容提示
- [x] 实现保存 / 删除后自动关闭 Sheet
- [x] 实现 ✕ 关闭 / 下滑关闭（有未保存内容时拦截）

## Phase 4 — 排序

- [x] 首页默认排序：观看年月从新到旧
- [x] 进入排序模式后卡片可拖动
- [x] 实现同年同月内拖动重排并持久化 `sortIndex`
- [x] 实现跨年月拖动时显示提示并阻止移动
- [x] 点击「完成」退出排序模式

## Phase 5 — 排行榜

- [x] 创建 `RankingsView`，从首页 Push 进入
- [x] 顶部：返回 / 评分排行榜 / 排序
- [x] 第二行：共 N 部 / 平均 N 分（仅统计已评分）
- [x] 实现排行榜横向列表条目（排名、海报、片名、评分、年月）
- [x] 实现排行榜排序：评分 > 观看时间 > sortIndex
- [x] 实现同评分内手动排序
- [x] 实现跨评分拖动提示并阻止移动

## Phase 6 — 搜索

- [x] 点击「搜索」胶囊变为可编辑搜索栏
- [x] 实时按片名过滤
- [x] 搜索结果复用 `MediaCard` 与 adaptive 网格
- [x] 处理空搜索状态与取消恢复

> 2026-09-14 验收：四项在 Phase 2 重做分类选择器时就已实现（现在是「Segmented Picker +
> 右端独立放大镜按钮」，点放大镜在胶囊行下方滑出搜索栏）；第 3 项即 `HomeView.gridContent`
> 复用 `MediaCard` + `AdaptiveGridLayout`，第 4 项是「无搜索结果」空态 + 取消恢复。
> 本次**只补 UI 用例**（`SakuraReelUITests/SearchUITests.swift`），未改动行为。
> 详见下方「2026-09-14 Phase 6 搜索：验收 + 补测试」。

## Phase 7 — UI Polish

- [ ] 统一 Light Mode 配色与樱花粉强调
- [ ] 卡片点击轻微缩放动画
- [ ] 分类切换平滑布局变化
- [ ] 排序拖动抬起、缩放、阴影、触觉反馈
- [ ] 图片加载后轻微淡入
- [ ] 删除平滑淡出
- [ ] Sheet 原生过渡
- [ ] iPad Split View / Slide Over 适配
- [ ] Dynamic Type 与 VoiceOver 检查
- [ ] 最终运行验证 iPhone + iPad

## 记录

### 2026-08-20
- 完成需求确认、技术方案确认、模块化开发计划制定
- 生成 `CLAUDE.md` 与 `DEVLOG.md`

### 2026-08-21
- 完成 Phase 1 — 基础架构
  - 创建 Xcode 项目 `SakuraReel.xcodeproj`，iOS 17+ 目标
  - 建立 App / Models / Views / Components / Services / Utilities 目录
  - 实现 `MediaStatus`、`MediaItem`（含 `@Attribute(.externalStorage) poster`）
  - 实现 `RatingColor`、`MediaSort`、`Constants`
  - 实现 `CloudKitConfiguration` 与 `SakuraReel.entitlements`
  - 配置 `SakuraReelApp.swift` 的本地 `ModelContainer`（CloudKit 同步留待 Phase 7）
  - 创建空壳 `ContentView`、`HomeView`、`RankingsView`
  - 编译通过并在 iPhone 17 Pro 模拟器成功运行

### 2026-08-22
- 首页分类选择器重构为原生 Segmented Picker（`CategorySegmentedControl`），搜索按钮独立置于右侧
- 选择器行移到标题下方内容区，保留导航栏标题
- 搜索框弹簧滑入动画、工具栏内 tint 修复
- 模拟器运行验证通过

### 2026-08-22 存储方案调整：移除 iCloud，改用本地文件存储
- 需求调整：先移除 iCloud 云同步；数据保存在本地文件中，并可在系统「文件」App 中查看 / 备份
- `MediaItem` 由 `@Model` 改为 Codable 结构体；`poster` 不入 JSON，单独存为 `Documents/Posters/<id>.jpg`
- 新增 `Services/MediaRepository.swift`（`@MainActor @Observable`）：读写 `Documents/SakuraReelLibrary.json`，提供 upsert / delete / save
- 移除 `Services/CloudKitConfiguration.swift` 与 `App/SakuraReel.entitlements`，清理 pbxproj 中 CloudKit 引用与 `CODE_SIGN_ENTITLEMENTS`
- `Info.plist` 开启 `UIFileSharingEnabled`、`LSSupportsOpeningDocumentsInPlace`，数据在「文件」App 可见
- 视图从 `@Query` 改为读取 `@Environment(MediaRepository.self)`；`MediaSort` 改为数组排序
- 更新 `CLAUDE.md`、`CodingPlan.md`、`DEVLOG.md`
- 编译通过（iOS Simulator）

### 2026-08-27 v0.3 — 添加 / 编辑 与首页卡片微调
- 完成 Phase 3 添加 / 编辑：
  - `PosterResizer`：海报居中裁剪为 2:3、≤900px 高、JPEG 0.85 压缩，控制海报文件体积
  - `PosterImagePicker`：PhotosPicker 封装，选中后立即裁剪压缩并写入绑定
  - `YearMonthPickers`：年 + 月两个原生 Picker；未设年份时隐藏月份，选定年后默认当前月
  - `AddEditMediaView`：添加 / 编辑 Sheet，表单顺序固定为 海报→片名→分类→观看年月→评分→短评→播放链接
  - 底部原生按钮栏：添加模式 [取消][保存]；编辑模式 [删除][取消][保存]
  - 删除二次确认 Alert、未保存内容拦截提示、空片名校验、保存 / 删除后自动关闭
  - `HomeView` 接入 Sheet：FAB 打开添加、点击卡片进入编辑；经 `MediaRepository` 的 upsert / delete 持久化
- 首页卡片微调：
  - 海报贴紧卡片顶部（`VStack(spacing: 0)`、`PosterView(cornerRadius: 0)`），顶部圆角由卡片外层 `clipShape` 统一裁剪
  - 播放按钮移入「评分 + 日期」同一行、日期右侧行末，改为粉底白心（粉色圆形底 + 白色播放图标）
  - 评分区域可点击，弹出短评 Alert；评分数字加大为 30pt，两位数字（10）保证单行（`lineLimit(1)` + `minimumScaleFactor`）
  - `PosterView` 重构：`Color.clear` 撑满 2:3 区域 + `scaledToFill` 裁剪溢出
- 编译通过，模拟器运行验证

### 2026-09-13 v0.4 — Phase 4 排序
- 新增 `Components/HomeReorderDropDelegate.swift`：`DropDelegate` 只在「同年同月」组内重排，跨组时 `performDrop` 拒绝落点并上报提示文案。分组键复用 `MediaSort.groupKey(of:)`，不新增分组逻辑
- `HomeView`：
  - 新增 `draftItems` 草稿顺序、`draggedItemID`、`blockedMessage` 三个状态
  - 排序模式复用 `AdaptiveGridLayout`（列数唯一来源）挂 `onDrag` / `onDrop`，卡片改为 `MediaCard(item:isInteractive:false)` 避免评分 / 播放按钮与拖动抢触摸
  - 排序模式隐藏分类胶囊、搜索栏、空态与 FAB，显示全部条目 —— 保证每个观看年月组完整，`sortIndex` 重编才不会与未显示条目撞车
  - 进入排序模式先退出搜索；「完成」调 `applyHomeReorder(draftItems.map(\.id))` 落盘，「✕」直接丢弃草稿即回滚
  - 跨年月提示用系统 `.alert`，与项目其它 4 处 alert 一致
- `MediaCard` 新增带默认值的 `isInteractive` 参数（`.allowsHitTesting`），现有调用点与预览行为不变
- 关键决策：排序模式必须沿用 `.default` 排序（年倒序 → 月倒序 → `sortIndex`），**不能**用 `MediaSort.homeSorted(mode: .manual)` —— 手动顺序是按组各自重编 `0…n-1` 的，全局按 `sortIndex` 排会让不同年月组交错、同组不再连续
- 数据层沿用工作区已有的 `MediaRepository.applyHomeReorder` / `upsert` 的 `sortIndex` 分配，未改动
- 新增 `SakuraReelUITests/HomeSortModeUITests.swift`（UI 测试 target）+ `Scripts/run-ui-tests.sh`（写入测试数据并跑测试），5 个用例覆盖：排序模式隐藏筛选/FAB、组内拖动重排 + 完成落盘 + 重启保持、跨年月阻止 + 提示文案、✕ 回滚、排序模式下评分按钮不响应
- **验证中发现的真实缺陷**：跨年月拖动被拒绝时，卡片在拖向禁用目标的途中会依次经过本组其它卡片，每次都触发合法的组内重排，结果「一次被拒绝的拖动」顺带把卡片挪到了本组末尾。修复：`onDrag` 开始时快照草稿顺序，`performDrop` 判定跨组被拒时整体回滚到快照
- 编译通过（Swift 6 语言模式，无警告）；5 个 UI 测试全部通过（`./Scripts/run-ui-tests.sh`），模拟器截图确认排序模式布局正常

### 2026-09-13 v0.5 — Phase 5 排行榜
- **关键决策：新增 `MediaItem.rankIndex`**。Phase 5 要的「同评分内手动排序」与 Phase 4 已占用的 `sortIndex`（同观看年月）是**两套分组**，同一个整数无法同时表达 —— 复用会让排行榜重编在同年月组内造出重复 `sortIndex`，直接打乱首页已排好的顺序。故 `sortIndex` 语义与首页行为完全不动，排行榜单独用 `rankIndex`
  - 排序规则仍是「评分 > 观看时间 > sortIndex」：`rankIndex` 插在评分之后、观看时间之前，**整库都没手动排过时全为 nil（按 0 比较），比较器逐级落到观看时间与 `sortIndex`，与已定规则逐字一致**；只有被手动排过的那一组才改按 `rankIndex` 走。与首页「默认排序 / 手动排序」同构
  - `rankIndex` 声明为 `Int?` 而非 `Int = 0`：合成的 `init(from:)` 不会对缺失的 key 取属性默认值，非可选属性会让旧库文件解码失败；可选属性走 `decodeIfPresent`，旧文件自然得到 `nil`，零迁移代码
- 新增 `Components/RankingRow.swift`：横向条目 `#排名 + 海报 + 片名 + 日历图标&年月 + 右侧彩色评分`。海报复用 `PosterView`（宽 60 → 行高 90pt，2:3），评分复用 `RatingLabel`，颜色仍唯一来自 `RatingColor`。行内无按钮，因此不需要 `MediaCard` 那样的 `isInteractive` 开关（那会把 `.onDrag` 一起挡掉）
- 新增 `Components/RankingReorderDropDelegate.swift`：镜像 `HomeReorderDropDelegate`，分组键换成 `MediaSort.rankingGroupKey(of:)`，**保留 Phase 4 的 `dragStartSnapshot` 回滚**（跨组被拒时拖动途中已发生的组内重排必须整体回滚）
- `MediaSort`：`rankingSorted` 在评分之后插入 `rankIndex` 比较；新增 `rankingGroupKey(of:)` 条目便捷版（与 `homeGroupKey` / `groupKey(of:)` 那对同形）
- `MediaRepository`：新增 `applyRankingReorder(_:)`，镜像 `applyHomeReorder` —— 按每个 id 所属评分组各自重编连续 `0…n-1`；`upsert` 在评分变化时把 `rankIndex` 清回 `nil`（换组后旧名次无意义）
- `RankingsView` 整体重写：删掉自建的 `NavigationStack`（它本来就在 `HomeView` 的栈里，嵌套是 bug）；工具栏 `返回 / 评分排行榜 / 排序`，排序模式为 `✕ / 评分排行榜 / 完成`；第二行固定摘要`共 N 部 / 平均 N 分`（平均只算已评分，全未评分时显示 `—`）；`ScrollView` + `LazyVStack` 列表，普通模式点条目开编辑 Sheet，排序模式挂 `onDrag` / `onDrop`；跨评分提示复用首页的 alert 写法
- 零散改动：`RatingLabel` 加 `size: CGFloat = 30` 默认参数（排行榜用 22pt，首页不变）；`AddEditMediaView.handleSave` 保留 `rankIndex`；`HomeView` 补 `.navigationTitle("SakuraReel")`，让系统返回按钮显示「‹ SakuraReel」而不是英文 "Back"（首页显示的仍是那个粉色 principal 标题）
- 新增 `SakuraReelUITests/RankingsUITests.swift`（6 个用例）+ 扩展 `Scripts/run-ui-tests.sh`（fixture 加 2024.05 两条同为 10 分的条目，且**故意不写 `rankIndex`**，顺带验证旧库文件向后兼容）
- 验证：编译通过（Swift 6 语言模式，无警告）；`./Scripts/run-ui-tests.sh` 11 个用例全部通过（Phase 4 首页排序 5 个 + Phase 5 排行榜 6 个）；iPhone 17 Pro 与 iPad Pro 11-inch 截图核对，行内布局与设计稿一致
- **测试过程中发现的问题**：一开始让两个测试类共用一份 fixture，把 Phase 4 的用例打挂了 4 个 —— 新加的 10 分条目让 `app.staticTexts["10"]` 从唯一匹配变成多匹配，网格也从 5 格变 7 格把卡片挤出可点区域。改为两个类各写各的 fixture，不动 Phase 4 的断言
- `Scripts/run-ui-tests.sh` 三处修复：zsh 里 `$status` 是只读特殊变量（改名为 `exit_code`）；`test-without-building` 会重装 App，重装后数据容器 UUID 会变，容器路径必须每次现取（否则写 fixture 时报 FileNotFoundError）；原脚本测试失败也 `exit 0`，改为透传 `xcodebuild` 的退出码

### 2026-09-13 手动同步：导出 / 导入 iCloud 云盘文件夹（临时加入）
- 需求调整：想让 iPhone 与 iPad 共用同一份库。**关键结论：免费（personal team）开发者账号用不了 iCloud capability** —— ubiquity container 与 CloudKit 都属于它，Xcode 会直接拒绝。所以「自动同步」这条路的前提是 $99/年 的 Apple Developer Program
- 改走**显式操作**：「导出到 iCloud 云盘文件夹 / 从此文件夹导入」，用系统文档选择器授予的 security-scoped 访问，**不需要任何 entitlement**，免费账号可用
- 为什么这样反而更稳：正因为是用户手动触发的一次性操作，才能做**按条目合并**并在确认弹窗里报数（新增 / 更新 / 跳过 / 保留各几条）；自动同步那种无人值守的整文件覆盖做不到 —— 冲突时 App 根本不知道有第二份存在，失败模式是静默丢掉整个库
- 新增 `Services/LibraryArchive.swift`：导出 / 读取 / 按 `id` + `updatedAt` 合并 / 合并后的索引查重修正。导出**先写海报、JSON 最后写**（JSON 是「这份快照完整」的标志）。只依赖 Foundation，所以能脱离 Xcode 直接 `swiftc` 编译跑断言 —— 这条约束要保持
- 新增 `Services/SyncFolder.swift`：bookmark 存取与访问配对，只管「那个文件夹在哪、能不能访问」，不做任何读写业务
- `HomeView` 工具栏「排序」右侧加「···」菜单（选择同步文件夹 / 导出 / 导入，菜单项带文件夹名）；导入前先弹确认框报数，确认后才写盘
- `MediaRepository`：encoder / decoder 提为 `LibraryCoding` 供导出文件复用 —— 导出文件必须与本机库文件格式逐字一致，否则「导出的文件能不能当备份手工放回去」就成了未知数；新增 `makeImportBackup()` 与 `applyImport(_:)`
- **两台设备收敛**（这块最要紧，也是唯一无法靠肉眼验证的）：
  - 合并平局不能写成「平局保本机」：那样 A 留 A 的、B 留 B 的，A→B→A 会来回翻、永远合不拢。裁决必须**对称**，且只依赖两端一致的数据（`updatedAt` → `sortIndex` → `rankIndex`）
  - `sortIndex`（同观看年月组）与 `rankIndex`（同评分组）都是每组各自 `0…n-1`，两台设备各自排过序后合并，同组内会冒出重复索引；而 `MediaSort` 的比较器最后一级正是这个索引，Swift 的 `sorted` 又**不保证稳定** —— 重复索引会让那两条的先后每次刷新都可能不同。故合并后只对**已经不合法**的组重编为连续 `0…n-1`，没问题的组一条都不动
  - 重编时的兜底比较**不能**用数组下标：两台设备的数组顺序本来就不同，用下标会让同一份库在两边归一化出不同顺序。用 `createdAt` + `id`
  - 测试里 `fixedCount` 数的是「修正处数」而非条目数：同一条在两个维度各撞一次算两处
- 踩到并修掉的坑：
  - `URL.bookmarkData(options: .withSecurityScope)` 在 iOS 上是 `API_UNAVAILABLE`，编译不过 —— 只能用空 options，解析时用 `.withoutUI`
  - bookmark **必须在文档选择器回调的 security scope 内**建立，离开回调再建会失败
  - `startAccessingSecurityScopedResource()` 在**目录**上调，子项不用；返回 `false` 不是错误（非 security-scoped 的 URL 本来就会返回 false），那种情况不要 stop —— 授权是进程级引用计数
  - 云盘上的文件可能是被系统驱逐的 dataless 文件，裸 `Data(contentsOf:)` 会阻塞甚至失败，在主线程上做还有被看门狗杀掉的风险 → 读写都走 `NSFileCoordinator`，真正的 I/O 拆到 `Task.detached`
  - 协调读**不能**传 `.immediatelyAvailableMetadataOnly`（那样不会等 iCloud 下载完）；协调写的 options 用 `[]` 而非 `.forReplacing`，`.atomic` 留在协调块内；不嵌套协调
  - 回滚点用 `Data.write(to:options:.atomic)` 而不是 `FileManager.copyItem` —— 后者在目标已存在时会抛错，正好毁掉「每次覆盖、只留一份」的设计
  - 清理孤儿海报只认 `<UUID>.jpg` 这个形状：用户完全可能选一个放着自己图片的文件夹，删除范围一旦放宽就是在 App 之外毁数据
- 新增 `Tests/ModelTests/`（`main.swift` + `LibraryArchiveTests.swift`）与 `Scripts/run-model-tests.sh`：直接 `swiftc` 编译那几个只依赖 Foundation 的文件跑断言，不经过 Xcode 工程、不需要模拟器、不需要单元测试 target
- 明确不做：不同步删除（另一台设备删掉的条目本机会保留）、不做自动 / 后台同步、不接 CloudKit、不引入第三方库、不动 `Info.plist`、不加 `UTType` 声明（用的是系统的 `.folder`）
- **已知缺口：手动重排不参与合并传播**。`applyHomeReorder` / `applyRankingReorder` 只改 `sortIndex` / `rankIndex`，**不碰 `updatedAt`**，于是重排在导入时不算一次「更新」，另一台设备大概率保留自己那份顺序（只有 `updatedAt` 恰好相同时才会拿 `sortIndex` 做平局裁决，那不是可靠的传播通道）。要传顺序就得让重排也更新 `updatedAt`，可那会让「纯排序」伪装成「内容更新」、反而吃掉对方更晚的编辑 —— 两难，暂不处理
- 代价（明确接受）：不是自动同步 —— 一台设备改完要手动点一次导出，另一台点一次导入；同步文件夹里放的是**明文 JSON + JPEG**，暴露程度与本机 Documents 相同
- **未完成**：功能已实现并通过模型层断言，但「选 iCloud 文件夹 → 导出 → 清库 → 导入」的真机端到端尚未验证；同步菜单的 UI 用例（只断言三个菜单项存在，不点系统选择器）还没写；`CLAUDE.md` / `AGENTS.md` 里「不接入 iCloud / CloudKit」的措辞也还没改准确（准确说法：不使用 iCloud entitlement / ubiquity container / CloudKit，但通过文档选择器读写用户指定的 iCloud 云盘文件夹）

### 2026-09-13 排行榜卡片尺寸改为「一屏 5 张」
- 需求调整：排行榜卡片偏小，要按屏幕量化放大 —— iPhone 与 iPad **都是一屏 5 张**；iPad 上整列收窄居中，免得卡片被拉成一条长带
- 新增 `Utilities/RankingMetrics.swift`：卡片尺寸的唯一来源。卡片高度 = 列表可用高度 ÷ (5 + 4×间距比 + 2×留白比)，一屏正好铺下 5 张卡 + 4 个间距 + 上下留白；间距、留白、卡内一切尺寸都按「卡高 ÷ 基准卡高 90」等比缩放。只依赖 CoreGraphics（不 import SwiftUI），所以能被 `Scripts/run-model-tests.sh` 单独编译跑断言 —— 这条约束要保持
- `RankingRow` 改为全量等比：海报宽 = 卡高 × 2:3（卡高实际由海报决定），`#` 序号 / 片名 / 日历图标 / 观看年月 / 评分数值都写成「基准值 × scale」，圆角与阴影同步放大。片名 `lineLimit` 由 1 改 2（卡片放大后一行放不下几个字），行高仍由海报决定，不会因此变高
- `RankingsView`：用 `GeometryReader` **只包住列表**量出净可用高度（已扣掉导航栏与摘要行），交给 `RankingMetrics`；`LazyVStack` 的间距与留白同源，整列两侧各垫一个 `Spacer` 实现居中
  - 关键坑：`ScrollView` 会把内容按 leading 摆放，**只给固定宽度并不会居中**，第一版就是这么写的，iPad 上实测靠左
- iPad **横屏**列宽规则：卡片宽度 = 「半屏宽一列的卡片」× `padCardWidthMultiplier`（1.2，即再宽 1/5），整列居中。加宽算在卡片上、不是算在整列上，所以先减掉左右留白再乘、再加回来
- iPad **竖屏**改用**宽度**做高度预算（竖屏的宽度就是横屏时的屏高），于是竖屏卡高与横屏同一档、整列铺满屏幕宽。竖屏**不按「一屏 5 张」走** —— 屏太高，按可用高度摊会把卡片撑成巨无霸（189pt vs 现在的 144pt）。竖横判定直接比 `availableSize` 的宽高，与 `isPad` 组合
- `RatingLabel` 新增可选 `captionSize`（默认 nil = 系统 `.caption`）：排行榜放大时「分」/「未评」后缀连同间距一起放大；首页调用点不传，行为逐字不变
- 验证：模型层 64 项断言通过（新增 25 项：「一屏正好 5 张」在 iPhone 竖横与 iPad 横屏四种形态下均成立、iPad 竖屏卡高由宽度摊分且整列铺满、竖横两朝向的卡片长宽比一致（实测差 <0.1%）、卡高翻倍则间距留白同比、基准高度下 scale 回到 1、iPad 横屏卡片比半屏宽一列宽 1/5、可用尺寸退化为 0 也不出负卡高）；Swift 6 零警告；`./Scripts/run-ui-tests.sh` 在 iPhone 17 Pro 上 11 个用例全绿；两端截图核对 —— iPhone 一屏正好 5 张完整可见、第 6 张露头、卡片等高；iPad 横屏卡片居中且宽度符合规则
- 顺带修正 `Tests/ModelTests/LibraryArchiveTests.swift` 三条评分索引用例：原本用默认的同年月同 `sortIndex`，同一年月组也撞了车，`fixedCount` 里混进了另一维的修正数。改为互不相同的 `sortIndex`，并补一条「两个维度各撞一次 = 4 处」的显式断言固化计数语义（`fixedCount` 数的是修正处数，不是条目数）
- 已知取舍：卡内字号由卡高算出，**不再跟随系统动态字体**（「一屏几张」的直接代价，首页不受影响）
- 一度出现又已解决：iPad **竖屏**原本也按「一屏 5 张」摊，卡高 189pt → 片名放大到 31pt，而卡片只有 0.6 屏宽、`# 序号` 再占一截，片名净剩约 86pt（≈2.8 字），长片名断成「攻壳机 / 动队」。改为竖屏不按一屏几张走后，卡高回到 144pt、整列铺满 834pt，文字区约 566pt（≈23 字/行），断行消失
- 已知既有缺口（**非本次引入**）：`HomeSortModeUITests` 在 iPad 上跑会挂 4 个（首页网格在 iPad 是 5 列，4 张卡片同处一行，那套排序断言失效）。Phase 4 用例此前只在 iPhone 上跑过，本次因取 iPad 截图才暴露

### 2026-09-14 Phase 6 搜索：验收 + 补测试（未改动任何行为）
- 计划里 Phase 6 的两个清单项（搜索胶囊变搜索栏 / 实时过滤）**在 Phase 2 重做分类选择器时就已实现**。本次没有新增功能，只做验收与补测试。`CodingPlan.md` 的复选框此前一直没维护（Phase 1–5 也全未勾选），不代表功能缺失，已在文件里注明
- 验收确认的既定行为（**均未改动**，只用用例把现状钉住）：
  - 只匹配**片名**（`localizedStandardContains`），不搜短评
  - **忽略当前分类胶囊**，跨「看过 / 在看 / 想看」全局搜 —— 在「看过」下搜「阿诺拉」（想看）能搜到
  - 没命中时显示「无搜索结果 / 试试其他关键词」，不会误报「还没有作品」
  - 点分类胶囊退出搜索；进排序模式前先退出搜索
- 新增 `SakuraReelUITests/SearchUITests.swift`（4 个用例）：未点放大镜时无搜索框、输入后实时过滤只剩命中项、跨分类全局搜、无结果空态、取消退出并恢复全量。与 `HomeSortModeUITests` 共用同一份 home fixture
- **试过又回退的一条路**：把搜索框迁移到系统 `.searchable`（`isPresented` 绑定 + `.navigationBarDrawer(.automatic)`，保留放大镜按钮）。实测截图后放弃 —— 「更原生」的代价不止位置：
  1. 搜索框**常驻**显示在胶囊行上方（iOS 26 上 `displayMode: .automatic` 并非「下拉才出现」）
  2. 搜索激活时**整条导航栏被接管**，排序 / ⋯ / SakuraReel / 排行 全部消失（系统标准行为）
  3. `SearchFieldPlacement` 的落点只有导航栏 / 工具栏，**没有「内容区」**，搜索框必然离开胶囊行下方
  与「不改变现有视觉与交互」冲突，故回退，保持手写搜索栏。已 `git restore`，对比截图留在 /tmp 未入库
- **`Scripts/run-ui-tests.sh` 两处修复**：
  - `run_test_class` 改为透传 `"$@"`，同一份 fixture 的多个测试类可以一次跑完（Phase 4 + Phase 6 共用 home fixture）。改完漏改了一处调用点的 `-only-testing:` 前缀，已补
  - **构建失败现在会当场中止**。原来写的是 `xcodebuild build-for-testing ... | tail -1` 配 `set -e` —— 管道的退出码取自 `tail`，**永远是 0**，构建挂了脚本照样往下跑，用上一次的旧测试包跑完并报「全部通过」。这次就中招了：`SearchUITests` 编译不过（`waitForExpectations` 在 Swift 6 下会把 `self` 送过隔离边界），脚本却拿旧包跑出「Phase 4 全部通过」，而旧包里那个临时截图用例还「复活」了一次。真实错误被掩盖了一整轮
- 验证：Swift 6 语言模式编译零警告；`./Scripts/run-ui-tests.sh` 15 个用例全绿（Phase 4 五个 + Phase 6 四个 + Phase 5 六个）
- 视觉验证由用户自行负责，本次未截图入库
