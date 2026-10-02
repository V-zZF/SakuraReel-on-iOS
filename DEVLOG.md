# SakuraReel 开发日志

### 2026-09-25 排行榜片名字号
- 排行榜卡片片名基准字号按设备区分：iPhone 12 pt、iPad 15 pt，并继续随卡片高度等比缩放。

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

- [x] 统一 Light Mode 配色与樱花粉强调
- [x] 卡片点击轻微缩放动画
- [x] 分类切换平滑布局变化
- [x] 排序拖动抬起、缩放、阴影、触觉反馈 —— 触觉与「抬起」（源卡片变淡）在 App 侧实现；
      跟随手指的**缩放与阴影由系统 `.onDrag` 拖影自带**，未在源卡片上重复叠加
- [x] 图片加载后轻微淡入
- [x] 删除平滑淡出
- [x] Sheet 原生过渡（本来就是原生 `.sheet`，未自造转场）
- [x] iPad Split View / Slide Over 适配
- [x] Dynamic Type 与 VoiceOver 检查
- [ ] 最终运行验证 iPhone + iPad —— **由用户手动完成**

> 详见图下方「2026-09-15 v0.7 — Phase 7 UI Polish」一节。

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

### 2026-09-14 Phase 7 UI Polish（第一次落地）：按压态 / 统一卡片表面 / 触觉反馈
- 本轮由 Codex 完成，**未新增任何产品功能**，只把散落各处的「视觉 / 交互细节」收敛成共用件，并把几处「像原生但不是原生」的写法换掉
- **`Constants.swift` 扩出三个共用件**（此前只有颜色 / 圆角 / 间距常量）。这与 `RankingMetrics` 的思路一致：凡是「多处各写各的、必须一致」的东西，收成一个唯一来源：
  - `LibraryCardSurface`：白底 + `continuous` 圆角 + 0.5pt 极细描边（黑 3.5%）+ **双层阴影**（大：黑 7% / 半径 10 / y 5；小：黑 3.5% / 半径 1 / y 1），带 `scale` 参数供排行榜按卡高传。此前首页卡与排行榜行**各写各的**（都是 `0.06 / 4 / y2` 单层），排行榜用的还是 `Color(.systemBackground)`，阴影偏「贴边」不像浮起
  - `cardShadowRadius` 4 → 10，配合双层阴影
  - `libraryBackground = #F5F4F3`（极浅暖灰）：首页此前是系统默认背景、排行榜是 `Color(.systemGroupedBackground)`，现在同源
  - `LibraryPressStyle`：原生 `ButtonStyle`，按下 0.975 缩放 + 0.88 透明度，尊重 Reduce Motion。此前只有搜索按钮挂 `.buttonStyle(.plain)`（等于没有按压态），卡片干脆用 `.onTapGesture`
  - `LibraryInteractionFeedback`：把散在两页的 `sensoryFeedback` 收成一个 `ViewModifier` —— 进出排序模式（selection）、打开编辑 Sheet（light impact）、拖动开始（medium impact）、跨组被拒（warning）、组内重排成功（selection，条件 = 数量不变 + 顺序变了 + 正在拖）
- `SakuraReelApp.swift` 加 `.preferredColorScheme(.light)`：把 CLAUDE.md 的「保持 Light Mode，不考虑深色模式」从约定落成代码（此前系统切深色时卡片 / 背景会跟着变）
- **卡片点击从 `.onTapGesture` 换成真正的 `Button`**：`MediaCard` 新增 `onOpen: (() -> Void)?`，海报区与片名各自成为 Button（`HomeView` 传 `{ sheetTarget = .edit(item) }`），`RankingsView` 的行同样换掉；`.allowsHitTesting(isInteractive && onOpen != nil)` 保持排序模式下不抢拖动的手势。理由：`.onTapGesture` 没有按压反馈，也不参与 VoiceOver 的「按钮」语义
- 拖动重排动画 `.easeInOut(0.2)` → `.snappy(0.25)`；两个 `DropDelegate` 新增 `reduceMotion` 参数，开启「减弱动态效果」时不做动画（此前无条件动画，与首页其它动画的处理不一致）
- `HomeView`：
  - 「···」资料库文件菜单从导航栏（挤在「排序」右边）挪到**分类行左端**，与右端放大镜分列两侧，导航栏回归「排序 / SakuraReel / 排行」各一个操作；菜单补 `.accessibilityLabel("资料库文件")`
  - 标题字号 26 → 20，并加 `lineLimit(1)` + `minimumScaleFactor(0.85)`（`.inline` 模式下 26pt 会被挤压）
  - `gridContent` 加 `.transition(.opacity)`，分类切换加 `.smooth(0.25)` 动画；搜索栏弹簧 `0.38/0.86` → `0.32/0.9`
  - 删除条目（首页与排行榜）包进 `withAnimation` 并尊重 `reduceMotion`
- `CategorySegmentedControl`：去掉片名尾部用来撑宽滑块的空格占位（`"     "`），搜索按钮补 44×44 热区 + `LibraryPressStyle()`
- **追加改动（用户要求）：「···」按钮内部改为主题粉**。这里有个坑值得记下来 —— 该按钮原本写的是 `.foregroundStyle(.primary)`，实际却渲染成**系统蓝**：`Menu` 的 label 由系统 button style 在**外层**套 `.foregroundStyle(.tint)`，标签内部自己写的 `foregroundStyle` 因为语义环境更靠内而被盖掉（截图实测确认，不是猜测）。**所以只把颜色常量换成 `Constants.accentPink` 不会生效**，必须同时在 `Menu` 上补 `.tint(Constants.accentPink)`。两处都保留：`.foregroundStyle` 是语义声明，`.tint` 才是真正生效的那条
- 上一条的取舍：`.tint` 加在 `Menu` 上会**一并染进弹层**，菜单项的三个图标（文件夹 / 导出 / 导入）跟着变粉，不再是系统蓝。已截图核对。若要保持弹层图标为系统蓝，得把标签换成烘焙好颜色的 `.alwaysOriginal` `UIImage`（不参与 tint），代价是引入 UIKit 图像代码 —— 当前按「品牌色一致」保留 tint 方案，此取舍待用户裁决
- **追加改动（用户要求）：导航栏左右两个按钮改成一样宽**。实测「排序」胶囊 178px、「排行」胶囊 142px（均为 3x，即 59.3pt vs 47.3pt），差 12pt。逐项排除后，根因不在容器而在**构造方式**：
  - 先怀疑左侧套的那层 `HStack(spacing: 18)`（当初是为了让同一 placement 上的多个 ToolbarItem 顺序可控）—— 拆掉后两张截图**逐像素完全一致**，不是它。该容器确实已成多余（菜单移到分类行后只剩一个 item），顺手删掉，注释同步改准确
  - 再把「排行」从 `NavigationLink` 临时换成 `Button` 做对照：左右都变成 178px。**根因是工具栏里的 `NavigationLink` 每侧比 `Button` 少 6pt 内边距**
  - 修法：「排行」改为 `Button` + 编程式跳转（新增 `@State showsRankings` + `.navigationDestination(isPresented:)`），仍然复用首页的 `NavigationStack`、不自建栈。修后实测 178px vs 178px，差 0
  - 为什么不用「给两边写死同一个宽度」：那是拿魔法数字盖住差异，系统改一次内边距就又错位；让两个按钮走同一种构造才是根上对齐
  - 已验证 Push 仍正常（临时用例点「排行」→ 断言 `navigationBars["评分排行榜"]` 出现，通过后已删除）
  - 注意：**这是 iOS 26 工具栏的行为，无文档说明**，结论来自实测对照（同一份代码只改构造方式，其余不动）
  - 排序模式下的「✕ / 完成」**没有**对齐：前者是纯图标按钮，两者内容本就不同宽，强行拉齐反而不像系统
- ⚠️ **本轮引入的真实回归：UI 测试由 15 绿变成 15 红**（`./Scripts/run-ui-tests.sh` 实测：第一轮 9 个用例 9 失败，第二轮 6 个 6 失败）。原因是**片名被包进了 `Button`** —— SwiftUI 的 `Button` 会把子元素合并成一个无障碍元素，片名不再作为 `staticText` 暴露，而全部用例都在用 `app.staticTexts["千与千寻"]` 定位卡片。已用探针用例确认：`staticTexts["千与千寻"] = false`、`buttons["千与千寻"] = true`、`buttons["编辑千与千寻"] = true`
  - 附带后果：**失败信息会误导人**。所有用例都停在 setUp 那句 `XCTAssertTrue(app.staticTexts["千与千寻"].waitForExistence(...), "首页没加载出测试数据")`，报出来是「首页没加载出测试数据 / 请先写入 JSON」—— 而数据其实好好地在那儿（同一张卡片的 `buttons["编辑千与千寻"]` 能查到）。排查时会把人往 fixture、容器路径那条错路上带
  - 待办：要么把用例的查询从 `staticTexts` 改成 `buttons`（并修掉断言文案），要么在 App 侧让步（例如给片名 Button 加 `.accessibilityElement(children: .contain)`）。**尚未处理**
- 另一处待商量的设计：一张卡片现在有**两个**指向同一动作的 Button（海报 + 片名），VoiceOver 会连读两次（「编辑千与千寻」/「千与千寻」）。更原生的做法是整张卡片一个按钮元素、内部控件单独成元素，但那样会和卡片内已有的评分按钮、以及排序模式的 `.onDrag` 抢手势
- 代码风格小瑕疵（未改）：`RankingsView` 里新增的 `.modifier(LibraryInteractionFeedback(...))` 与 `reduceMotion: reduceMotion` 两处缩进与上下文不齐

### 2026-09-15 v0.7 — Phase 7 UI Polish（第二次落地）：回归修复 / 宽度感知列数 / 淡入淡出 / 无障碍

本轮把 Phase 7 清单做完，并修掉上一轮留下的 UI 测试回归。**未新增任何产品功能**，未改已定规则
（评分范围与颜色、首页与排行榜排序、同组拖动限制、卡片布局、浅色樱花粉方向全部不动）。

#### 1. 修掉上一轮的回归：卡片合并成**一个** Button

- 上一轮把片名包进 `Button` 后，15 个 UI 用例全红。**探针实测**（临时用例打印无障碍树，跑完即删）才看清机制：
  - Button 的 label 是**单个 `Text`** 时，SwiftUI 把它合并进按钮，片名不再作为 `staticText` 暴露 → 旧写法全挂
  - Button 的 label 是 **`VStack`（海报 + 片名）** 时，SwiftUI 会**同时**暴露按钮和内部 Text
- 于是把海报与片名合并成**一个** Button（它们本来就是同一个动作：打开编辑），显式写
  `.accessibilityLabel(item.title)`。结果：`app.buttons["片名"]` 与 `app.staticTexts["片名"]` **都能命中**，
  **15 个用例一行都不用改就全绿**
- 顺带修掉 DEVLOG 里记的「一张卡片两个 Button、VoiceOver 连读两次」：现在一张卡片只有一个「打开编辑」按钮
- 卡片布局逐字不变（原文字区 `VStack(spacing: 8).padding(12)` 拆成「片名上方 12 / 左右 12 / 与评分行之间 8 / 评分行下 12」）。
  **实测核对过几何**：卡片宽 177（iPhone 17 Pro 屏宽 402，2 列），海报 177×265.5 正好 2:3 且贴卡片顶部，
  片名在其下 12pt、高 18pt，评分行再隔 8pt，卡片横坐标 16 / 209（间距 16）——与既定布局完全一致
- **踩到的坑**：给合并后的 Button 加 `.accessibilityIdentifier(片名)` 会让 `staticTexts[片名]` 变成**多匹配**
  （`XCUIElementQuery` 的 `.frame` 会直接抛 "Multiple matching elements"）。定位靠 label 就够，identifier 已删
- 另一处试过但**无效**的写法：`.accessibilityElement(children: .ignore)` 加在 `Button` 上不生效
  （实测 `buttons["评分 10 分"] = false`，标签没落上去）；加在**非 Button** 的容器上才生效。已按实测结论取舍，不留无效代码

#### 2. iPad Split View / Slide Over：按可用宽度动态减列

- 新增 `Utilities/GridColumns.swift`（**只 import CoreGraphics**，与 `RankingMetrics` 同构，
  能被 `Scripts/run-model-tests.sh` 单独 `swiftc` 编译跑断言）。`minCardWidth = 110pt`：
  列数先由尺寸类给上限（紧凑竖屏 3 / Regular 5 / 其余 2），再按可用宽度收窄
- `Constants.gridSpacing` 改为引用 `GridColumns.spacing` —— 间距的唯一来源挪进这个不依赖 SwiftUI 的文件，
  模型测试才读得到，两边也不会各写一个数
- 宽度测量放在 `HomeView`（`@State gridWidth` + `ZStack` 的 `.background { GeometryReader }` +
  `.onPreferenceChange`），**不能**放进 `AdaptiveGridLayout` —— 那里面存了一个非 `@Sendable` 的
  `content` 闭包，`onPreferenceChange` 的 `@Sendable` 闭包捕获它会过不了 Swift 6 隔离检查。
  不会死循环：所有 `GridItem` 都是 `.flexible()`，网格宽度由容器决定、与列数无关；宽度未知时退回尺寸类的答案，
  首帧与从前逐帧相同
- `GridWidthPreferenceKey.defaultValue` 必须是 `static let` —— `static var` 在 Swift 6 下是可变全局状态，编译不过
- **主动回退了一处计划内的改动**：原计划给 `RankingMetrics` 加「窄栏（< 600pt）当作 iPhone」的门槛。
  实现后发现门槛两侧卡高会从 **599pt → 172pt 跳到 600pt → 103pt**（拖动分栏分隔线经过门槛时卡片会瞬间跳 69pt），
  而且当初的理由（「320pt 宽会摊出 55pt 迷你卡」）**不成立** —— Slide Over 与 1/2 分栏都是 compact 宽度，
  `isPad` 本来就是 false；只有 2/3 档才是 regular，而那一档并不过窄。故**回退**，`RankingMetrics` 保持原样、
  64 项断言一条未动，改为在模型断言里把「分栏下卡高由宽度摊分」这个既定行为钉住

#### 3. 淡入 / 淡出 / 抬起态

- **海报淡入**（`PosterView`）：动画挂在「数据从无到有」这一刻，**不能**挂 `.onAppear` ——
  海报是同步解码的，卡片一重建就已经有 `Data`，而 `LazyVGrid` 回收单元格时会丢掉 `@State`，
  挂 `onAppear` 的话滚回来的卡片会先空一帧再淡入，那就是闪烁。动画值用 `Bool`（`imageData == nil`）
  而不是 `Data`，否则每次比较都要比整个 JPEG。0.22s，尊重 Reduce Motion
- **删除淡出**：排行榜的行**根本没有 `.transition`**，补上；首页的接线本来就是对的，
  但**看不见** —— `AddEditMediaView` 调完 `onDelete?()` 紧接着 `dismiss()`，0.25s 的淡出全程被 Sheet 的消失动画盖住。
  两个页面都改成「只记下 id，落盘推迟到 `.sheet(onDismiss:)`」，淡出才真的可见
- **拖动抬起态**：源卡片留在原位变淡（`.opacity(0.4)`），拖影跟着手指走。
  `.opacity` **必须挂在 `.onDrag` 之外** —— 拖影是 `.onDrag` 那一层的快照，挂在里面会把「变淡」一起烤进拖影
- **顺带修掉一个既有 bug**：`draggedItemID` 只在 DropDelegate 的 `performDrop` 里清空，
  手指在卡片空隙或最后一行下方空白处松开时没有任何卡片的 `.onDrop` 会被触发，状态就永远留着。
  加了变淡之后这会表现为**卡片一直挂着半透明幽灵态**。修法：给 `HomeView` 与 `RankingsView` 的 `ScrollView`
  各挂一个兜底 `.onDrop(of:[.text], isTargeted:nil) { _ in draggedItemID = nil; return false }`（返回 false 不抢内层落点）
  - 注意 `.onDrop(of:)` 的尾随闭包会解析到 `delegate:` 重载而编译报错，`isTargeted:` 必须显式写

#### 4. Dynamic Type 与 VoiceOver

- 网格封顶 `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)`，加在 `AdaptiveGridLayout.body`：
  两个首页网格都走它。**不能**加在 `NavigationStack` 上 —— `.sheet` 会继承呈现者的环境，
  那样会连 `AddEditMediaView` 一起封顶，而表单恰恰是最需要大字号的地方
- 卡片里日期那行加 `.lineLimit(1).minimumScaleFactor(0.8)`：卡片评分行在默认字号下已接近占满
  （卡宽 172.5 − 24 内边距 ≈ 148pt，而评分数字 30pt 与播放按钮 32pt 都不跟随动态字体，只有 `.caption` 日期会涨）
- **排行榜一行都没动**：`RankingRow` 用的是 `.system(size: 15 * scale)` 这类绝对字号，本就不跟随动态字体 ——
  那正是「一屏 5 张」的既定代价
- 排行榜整行合成**一句**朗读文本（「第 3 名，千与千寻，2024 年 3 月观看，10 分」/「未设置观看年月，未评分」），
  两种模式都合成同一个元素 —— 不写的话，正常模式下系统会把 `# 序号 / 片名 / 年月 / 评分` 拼成一串碎片读出来

#### 5. 验证与遗留

- 编译：Swift 6 语言模式 **0 error**。`PosterImagePicker.swift:42` 有一条
  「main actor-isolated property 'posterData' can not be referenced from a Sendable closure」的警告，
  已用「stash 掉全部改动、在 HEAD 上构建」**A/B 验证过是 HEAD 本来就有的**，非本轮引入（此前 DEVLOG 里
  「零警告」的说法只统计了被重新编译的文件，不准确）
- 模型层：`./Scripts/run-model-tests.sh` **89 项断言全过**（原 64 + 新增 25 项 `GridColumns` 与分栏断言）
- UI 层：本轮修复后 15 个用例**全绿**（含两次全量跑）
- ⚠️ **已知遗留：首页排序模式的两个拖动用例变得 flaky**。`testReorderWithinGroupThenCommitPersists` 与
  `testCancelRollsBackReorder` 做的是**同一个拖动**，失败信息都是「拖动后草稿顺序应已改变」，即顺序完全没动
  （`dropEntered` 没触发）。特征是**时序性**的：全量跑时两个都挂，单独跑该测试类时三轮里挂 1～2 轮且交替出现。
  - 已排除：新加的兜底 `.onDrop`（摘掉后照样 flaky）、拖动抬起态的 `.opacity`（摘掉后照样 flaky）
  - **对照实验**：把全部改动 stash 掉、在 HEAD（v0.6）上重复跑 3 轮 → **15/15 全过，一次没挂**。
    所以这个 flakiness **是本轮（或上一轮 Phase 7）引入的**，不是既有的
  - **用户手动验证：拖动重排功能本身正常工作**，因此判定为 XCUITest 的时序问题而非功能缺陷
  - **处置：按用户决定，删除 UI 测试**（见下），此遗留不再跟踪
- **按用户决定删除 UI 测试**：删掉 `SakuraReelUITests/`（3 个文件 / 15 个用例）与 `Scripts/run-ui-tests.sh`，
  并从 `project.pbxproj`（11 个块 + 10 条散行）与 `SakuraReel.xcscheme`（BuildActionEntry + TestableReference）
  中摘掉 `SakuraReelUITests` target。**模型层断言保留** —— 它们是唯一能脱离模拟器验证列数、合并、索引修正的手段
  - 手术用脚本按 ID 前缀（`AC…` / `AE…`）做**花括号配对**整块删除，而不是逐处手改。
    第一版脚本的正则写死了「两 tab 缩进」，漏掉了更深缩进的块（`targets = (…)` 里那个），只删掉了首行、
    留下悬空的方法体，`xcodebuild` 直接报 `Unable to read project`。改为**不限缩进**的配对删除 + `plutil -lint` 校验后通过
  - 删除后 `xcodebuild -list` 只剩 `SakuraReel` 一个 target，构建通过
- **UI 测试删掉后，本轮新增的 `GridColumns` 算术仍由模型层 25 项断言守着**；但**UI 层从此没有自动化回归网** ——
  这是明确接受的代价
# MAL 数据转换（2026-09-23）

- 新增 `Scripts/convert_mal_library.py`，从只读 SQLite 数据库和原海报目录生成独立的 SakuraReel 同步文件夹；重复转换使用固定 UUID，便于后续按 ID 合并导入。
- 生成 `/Users/zzf/code/MAL/SakuraReelSync/`：127 条元数据和 127 张海报。原始 `anime.db`、`posters/` 未修改。
- 映射 `watch_date`、分类、评分、短评、播放链接及创建时间；`home_position`、`leaderboard_position` 分别重编为同年月、同评分组内连续索引。

# 海报导入裁剪修复（2026-09-24）

- 修正 `PosterResizer` 的 2:3 居中 aspect-fill 计算：宽图按高度铺满并裁左右，窄图按宽度铺满并裁上下，避免导入后生成上下或左右白边。
- 只影响之后导入或重新选择的海报；已保存海报不自动处理。

# 首页卡片切换动画调整（2026-09-24）

- 移除首页网格随分类切换的隐式布局动画，卡片直接出现在目标位置，不再从下向上移动；删除时的淡出与搜索栏动画保留。

# UI 细节打磨（2026-09-24）

- 首页和排行榜的排序入口、首页排行入口加入带文字的 SF Symbols；添加／编辑表单的片名、分类、观看年月、评分、短评和播放链接加入对应图标。
- 首页标题增至 24 pt，并使用更深的樱花粉；导航栏沿用原有系统背景。
- 排行榜名次的 `#` 换为 SF Symbol，片名基准字号由 15 pt 降至 10 pt；卡片尺寸算法、排序与整行 VoiceOver 文案保持原有行为。
- iPhone 模拟器构建通过；模型层 89 项断言通过。

# 分类与排行榜动效重做（2026-09-24）

- 分类切换遵循「看过 → 在看 → 想看」的左右顺序：向右选时旧内容左移、新内容从右进入；反向则相反。卡片区与空态一起移动，分类选择器和悬浮按钮固定；切换时列表回到顶部。搜索与排序模式不触发横移。
- 排行榜正常浏览时卡片从右侧 24 pt 处按名次每隔 40ms 淡入；延迟按可见批次循环，不随整库条目数累计。排序模式即时显示，保留原有拖动与删除效果。
- 添加悬浮按钮按下放大至 1.1 倍，松开弹簧回弹，120ms 后打开表单；连续点击只响应一次。系统「减少动态效果」开启时跳过移动、缩放和等待。
- iPhone 模拟器构建及模型层 89 项断言通过；在 iPhone 17 和 iPad mini 模拟器中以临时样例数据检查首页卡片布局，随后恢复原模拟器库文件。

# 排行榜进场与首页工具栏微调（2026-09-24）

- 排行榜卡片等待导航推入稳定后，仅从右侧水平偏移 24 pt 淡入；单张时长由 0.32 秒增至 0.64 秒，逐张间隔由 40ms 增至 80ms。
- 首页左右工具栏改为纯图标；排序模式的完成按钮使用勾号，并为各图标按钮保留明确的无障碍名称。
- iPhone 模拟器构建通过，首页纯图标布局已通过模拟器截图检查。

# 首页标题字号调整（2026-09-24）

- `SakuraReel` 标题由 24 pt 增至 30 pt，保留深樱花粉和小屏幕缩放余量。

# 时光机（2026-09-24）

- 首页标题长按 0.5 秒后以轻微缩放弹回打开全屏暗色时光机；排序模式禁用入口，VoiceOver 可通过自定义操作进入。
- 按有完整观看年月的“看过”作品生成非空季度，1–3／4–6／7–9／10–12 月分别标为冬／春／夏／秋；季度代表封面与季度内顺序复用排行榜规则。
- 新增两层可复用 Cover Flow：最新季度或本季最高名次居中，其余卡片左右交替展开；支持侧卡选中、中央卡打开、水平拖动吸附、3D 倾斜、遮挡和渐隐海报倒影。作品层展示本季部数及精简只读信息。
- 模型层新增季度边界、过滤、同分封面和中心向外排列断言。iPhone 17、iPad Pro 13-inch 的隔离 QA 模拟器已用临时测试数据检查季度层、作品层及信息面板截图；iPad 优先检查了 1024×768 横屏尺寸下的布局和遮挡。当前无头模拟器拒绝程序化旋转，真实设备横屏交互尚待实机检查；临时调试入口已移除。
- Mac 上打开时光机出现 `No Observable object of type MediaRepository found` 的致命错误。改为由首页在呈现时直接传入库快照，时光机不再依赖全屏呈现跨视图树继承环境对象；季度分组也只在创建页面时计算一次。
- 季度舞台按从新到旧直接从左向右排列，默认定位去年的当前季度（为空时选之前最近的非空季度）。季节文字移至海报上方，春粉／夏绿／秋金／冬蓝，移除海报下缘文字蒙版并保留倒影；季度底部计数加大。作品到中央时直接显示片名、观看年月和醒目评分，无需再点海报。用隔离样例库检查了 iPad 横屏尺寸下两层布局与评分面板。
- 排行榜进场动画改由页面统一触发，仅进场时首屏可见的卡片依次渐入；滚动后才进入画面的卡片直接显示。
- 修正 Cover Flow 松手时手势位移先归零造成的回跳：拖动位移保持到吸附动画开始，按松手时的实际位置就近选卡。窗口尺寸变化时以当前容器宽高重新布局并重建舞台，返回原尺寸后重新计算卡片位置与大小。
- 按新的兼容性要求将最低系统版本从 iOS 17 提高到 iOS 18，窗口尺寸标识直接使用 `CGSize`。
- 时光机作品层中央海报可水平翻转查看短评；空短评不响应翻转，切换作品自动显示海报正面。背面采用深色卡片排版，长评可在卡片内滚动，并提供 VoiceOver 提示。
- 时光机入口改为自定义全屏覆盖层：iPhone 从顶部中央的灵动岛／刘海区域展开，iPad 与 Mac 从顶边滑入；关闭时反向收起，减少动态效果下立即显示。打开前保留库快照，覆盖期间首页从无障碍树隐藏。
- 入口动效统一为从顶部滑入。打开季度时，代表海报通过共享几何位置移动到作品舞台中央；本季其他海报从中央卡片后方渐显并向两侧展开，底部作品信息随之出现。减少动态效果下直接切换。
- 一级季度舞台松手后直接确定当前最近的卡片，取消松手后的二次吸附动画；作品舞台原有吸附动效保持不变。
- 从本季作品返回季度时，其他作品先收回代表海报背后，再让代表海报回到季度舞台；减少动态效果下直接切换。时光机标题及操作按钮下移至 iPhone 顶部安全区域下方，并相应缩减舞台高度，避开灵动岛和刘海。

### 2026-09-26 — 双顺序快照与整库覆盖导入
- 资料库 JSON 由条目数组升级为含 `items`、`homeOrder`、`rankingOrder` 的快照；旧数组按原索引与排序规则迁移，并在本机加载后保存为新格式。首页与排行榜拖动现在分别写入完整 ID 顺序，条目编辑时间不再影响顺序传播。
- 导入取消按 `updatedAt` 合并，确认后以同步文件夹的条目、两套顺序及海报整体覆盖本机；本机独有条目和孤儿海报会删除。导入确认展示云端、本机及待删除数量。现有导入前备份仍只含 JSON，不含海报。
- 模型测试覆盖旧版迁移、双顺序导出读回、旧条目仅调整位置、云端覆盖较新本机内容、空库与分组边界。

### 2026-10-02 — 首页分类动画与时光机手势修复
- 首页分类网格使用分类身份，并隔离内部布局的动画事务；横移与淡入淡出仍由外层控制，避免分类切换时卡片位置参与动画而向上浮动。
- 两层时光机舞台改为同时识别水平拖动，卡片按钮区域也可左右滑动；保留按钮点击行为，纵向拖动不切换卡片，便于滚动短评。
- iOS 模拟器 Debug 构建通过，差异格式检查通过；卡片点击、连续切换与短评滚动的实机交互仍需确认。

### 2026-10-02 — 交互修复跟进
- 根据反馈缩小首页动画隔离范围到单张卡片内部，将分类横移与透明度动画绑定到页面进度，恢复页面左右平移动画，避免整个布局被显式动画事务带动。
- 时光机水平拖动期间及松手后 150ms 忽略卡片按钮激活，避免同时识别的按钮松手事件选回拖动起点；普通点击保留。
- iOS 模拟器 Debug 构建与差异格式检查通过；触摸滑动及分类动画尚未完成运行时验证。

### 2026-10-02 — 分类横移动画作用域修正
- 移除单张卡片的动画事务覆盖，改用 SwiftUI 闭包式动画，只对页面 offset 与 opacity 生效；进度更新明确允许动画，内部网格布局不使用全局动画。
- iOS 模拟器 Debug 构建与差异格式检查通过；本次未完成动态效果的运行时验证。

### 2026-10-02 — 回退首页动画修改
- 按用户要求撤销本轮全部首页卡片动画修改，恢复原来的分类横移与淡入淡出实现；保留时光机手势修改。此前首页动画修复记录已被本次回退取代。

### 2026-10-02 — 1.0.1（Build 2）
- Debug / Release 的 App 版本统一更新为 1.0.1，构建号更新为 2。
- 提交当前时光机、双顺序快照与整库覆盖导入、图标及 UI 调整；首页卡片动画保持本轮修复前实现。
- iOS 模拟器 Debug 构建通过，模型层 95 项断言通过，差异格式检查通过。

### 2026-10-02 — 0.7.2（Build 3）
- 按用户要求将 Debug / Release 版本统一更新为 0.7.2，构建号递增至 3；本次仅更新版本与日志。

### 2026-10-02 — 1.0.0（Build 4）
- Debug / Release 版本统一更新为 1.0.0，构建号递增至 4，准备推送至 V-zZF/SakuraReel-on-iOS。
- iOS 模拟器 Debug 构建通过；保留远端初始化 README 并合并历史。

### 2026-10-02 — 仓库文档与开发配置
- 完善 README：功能、文件存储、覆盖导入和完整备份、构建命令、模型测试及项目结构。
- 新增贡献指南、Issue / PR 模板、GitHub Actions 模型测试与模拟器构建、Actions 依赖更新、编辑器与文件换行配置。
- 补齐本地缓存、凭据和导出产物忽略规则；模型测试脚本退出时清理临时产物；旧文档最低系统版本统一为 iOS 18。
- 本地 95 项模型断言、iOS 模拟器 Debug 构建、YAML 解析与差异格式检查通过。

### 2026-10-02 — TMDb 辅助录入：本地模型与附件
- 根据用户明确授权启用 TMDb，替代早期不接入外部数据源的限制。`MediaItem` 保持 Codable 值类型，新增可选来源身份及可编辑作品资料；电影、剧集和季度身份独立，语言不参与重复判断。
- 海报仍使用本地 UUID 和原 JPEG 规格；背景与 PNG Logo 保存到 `Documents/Artwork/<UUID>/`。JSON 不包含图片字节，旧数组、旧快照和旧导出目录继续兼容。
- 本机保存、导出及覆盖导入采用可恢复事务，失败回滚；启动时恢复中断保存，损坏 JSON 保留原文件并阻止普通保存覆盖。导入前增加完整附件备份，旧 JSON 备份名称继续保留。

### 2026-10-02 — TMDb 服务、鉴权与图片
- 使用 Foundation + URLSession，不引入 SDK 或 AniShelf 的 DataProvider、LibraryStore、SwiftData、LibrarySync。独立服务及 transport 可注入，搜索与详情 DTO 容忍可空字段；基本详情与可选演职员、图片目录分开处理。
- 支持电影／剧集分页、季度详情、演职员与季度／单集摘要，复用详情及图片配置、合并进行中请求，最后一个使用者取消后停止请求。429 最多重试两次，支持秒数和 HTTP 日期形式的 Retry-After，超过 30 秒提示稍后重试。
- API Key 仅保存在 Keychain；设置支持语言、验证、直连及用户指定的 HTTPS API 主机。验证使用当前草稿线路，不预置第三方代理，不向其他线路并发发送 Key，拒绝跨主机鉴权重定向。
- 图片后台降采样、裁剪与压缩；临时缓存预算 32 MB 内存、150 MB 磁盘、七天有效期，缓存键包含尺寸及处理类型。SVG Logo 尝试 PNG rendition，失败回退片名。详情图片解析不发送带 Key 的配置请求，缓存缺失的头像等可独立访问图片 CDN。

### 2026-10-02 — 搜索、导入预览与本地详情
- 添加／编辑页新增“作品资料”菜单，保留原表单顺序。独立草稿只初始化一次，搜索、选择、取消或失败不重置原表单；原有保存按钮才写入收藏库。
- 搜索页提供 TMDb／收藏库、语言及作品类型选择，电影和剧集分组独立分页、错误重试、季度选择和重复条目入口；移除动画类型限制，只导入单项。请求取消与身份检查防止旧搜索或图片覆盖新选择。
- 导入和主动重新获取均通过字段对比预览，默认仅填空字段；已有片名和海报需要勾选替换，海报失败可重试或只导入文本。TMDb 评分、简介、官网、上映日期不覆盖任何个人记录。
- 首页／排行榜普通点击进入本地详情，保留原排序交互。详情包含背景、Logo、个人记录、统计、简介、演职员及季度／单集摘要；手动条目也可展示。更多菜单支持个人记录编辑、作品资料编辑、主动获取、设置和确认删除。
- 作品资料编辑页支持文本、数值、制作公司、演职员、季度／单集摘要和本地图片。未保存关闭使用确认提示，保存失败保留草稿。新增集中 String Catalog、TMDb 官方署名资产及 AniShelf 来源许可说明；保持 iOS 18 和浅色原生 SwiftUI。

### 2026-10-02 — TMDb 验证与交付
- 模型脚本通过 122 项断言；无模拟器 TMDb 服务脚本通过 43 项检查，覆盖个人记录保护、资料／三种附件往返、旧文件、身份重复、乱序搜索和图片、分页取消及重试、合并请求取消、限流、线路切换、可选资源失败、保存失败及损坏文件恢复。
- Xcode 27.0 通用 iOS Simulator Debug 构建通过（无需签名）；差异格式检查与 CI YAML 解析通过。新文件显式加入 App target，CI 增加 TMDb 服务检查，README、AGENTS 和贡献指南已更新。
- 没有已启动模拟器，未启动新模拟器；未进行 UI 运行验证、真实 TMDb Key／API／图片请求、实机 Keychain 或第三方文件提供商验证。图片 CDN、SVG 的 PNG rendition、嵌套 Sheet 关闭与无障碍实际交互仍需运行确认。
- 完整剧集保存季度摘要，季度条目保存单集摘要；不包含批量添加、逐集追踪、提醒、自动刷新、云同步或新账号体系。未提交 Git commit 或推送。

### 2026-10-02 — 加号优先搜索与可跳过的 TMDb 指引
- 加号默认打开 TMDb 搜索；无 Key 时展示注册、登录和获取 API 的官方跳转按钮，下一步进入现有 Key／语言／线路设置表单。指引与填写均可跳过，或者直接手动添加。
- 用户授权的默认 Key 放在 Git 忽略的本机构建配置中，通过 Debug／Release 的可选 xcconfig 注入 App；点击跳过后存入 Keychain 并使用直连，不写入 Swift 源码、收藏库、导出或构建日志。其他构建环境不配置默认 Key 时仍支持填写自己的 Key 或手动添加。
- 移除搜索顶部 TMDb／收藏库选择器；保留语言、类型、分组分页、季度选择及重复条目入口。底部固定手动添加按钮；从搜索导入后将同一 UUID 的内存草稿交给原表单，只有保存才写库，仍提示放弃未保存内容。
- 设置凭据读写与偏好可注入测试；新增无 Key、默认凭据写入与后续请求可见、直连与请求代际变更、凭据写入失败保留配置的关键检查。模型 122 项断言、TMDb 47 项检查、通用 iOS Simulator Debug 构建与差异格式检查通过。确认默认值已进入构建包，未出现在源码、测试或构建日志。
- 没有已启动模拟器，未启动模拟器；官网跳转、Sheet 流转与实机 Keychain 仍未运行验证，未发送真实 TMDb 请求。未 commit 或推送。

### 2026-10-02 — 详情页布局调整
- 隐藏详情顶部导航栏背景，让背景图直接显示；更多操作移到左侧，完成按钮保留右侧。沿用原生工具栏和 iOS 18 最低版本。
- 统计卡片改为单行横向等宽，每张统一预留三行数值高度；制作公司最多展示三行并在末尾省略，避免长名称撑高单个卡片。
- 演员／职员缺少照片路径时只显示姓名和角色，不再创建照片占位或保留照片高度。
- 差异格式检查及通用 iOS Simulator Debug 构建通过；没有已启动模拟器，未启动模拟器，截图对应的实际滚动和布局未运行验证。未 commit 或推送。

### 2026-10-02 — 指引页直接填写 API
- 移除“下一步”和单独填写阶段；官网注册／登录／API 链接下方直接放置空的 SecureField，以樱花粉描边、浅色底和标题强调。点击“保存并搜索”才写入 Keychain 并进入搜索，保留手动添加及跳过入口。
- 跳过按钮简单标注“默认 API（不稳定）”。填写后关闭仍提示放弃未保存修改，保存失败保留输入。新增文案加入 String Catalog，并同步 README 和 AGENTS。
- 通用 iOS Simulator Debug 构建与差异格式检查通过；未进行模拟器运行验证，未 commit 或推送。

### 2026-10-02 — 1.1.0（Build 5）
- Debug／Release 版本统一更新为 1.1.0，构建号递增至 5。
- 本次提交包括 TMDb 辅助搜索、可跳过的 API 指引、本地作品详情和资料编辑、附件备份及相关验证；保留本机默认 API 配置的 Git 忽略规则，不提交凭据。
- 版本更新后模型 122 项断言、TMDb 47 项检查、通用 iOS Simulator Debug 构建及差异格式检查通过；构建产物版本确认 1.1.0（5）。仅创建本地 commit，不推送。

### 2026-10-02 — 背景对比与演职员统一布局
- 详情顶部更多／完成按钮分别根据背景图左右上部的明度选择黑色或白色，避免固定樱花粉文字在背景上不清晰。后台 ImageIO 降采样并按背景实际 aspect-fill 裁剪取样，任务取消后不应用旧结果；图片或宽度变化重新计算。滚动离开背景区域后使用适合浅色页面的深色按钮。
- 演员／职员各自按整组判断照片：只要一人有照片路径，所有条目保留同样照片区域（缺图为占位），统一姓名和角色位置；整组都没有照片时去除整个照片区域。
- 通用 iOS Simulator Debug 构建及差异格式检查通过。没有已启动模拟器，未启动新模拟器，按钮和滚动对比的实际视觉效果未运行验证。

### 2026-10-02 — 1.1.1（Build 6）
- Debug／Release 版本统一更新为 1.1.1，构建号递增至 6；提交详情页顶部按钮明度适配及演职员整组照片布局调整。
- 通用 iOS Simulator Debug 构建及差异格式检查通过，构建产物版本确认 1.1.1（6）。创建本地 commit，不推送。

## 2026-10-02 — 全新数据架构：模型与排序

- JSON 改为版本 1 的 LibraryDocument；本地 UUID 和类型化 TMDb 身份分离，不读取旧格式、不提供迁移。
- 条目拆分作品资料、个人记录、完整观看年月与附件描述，删除重复片名和旧排序索引。
- 首页保存年月组顺序，排行榜只保存手动评分组；集中校验数据和排序引用。
- 仓库与页面正在接入异步事务、按需附件和新测试，验证结果在后续里程碑记录。

## 2026-10-02 — 全新数据架构：存储与页面接入

- LibraryEntry 不含图片字节；编辑与传输使用独立 MediaItem 草稿，列表只发布轻量条目。
- LibraryStorage actor 串行执行文件工作；仓库串行候选变更，成功提交后发布并递增 revision，负责条目时间戳。
- 保留全目录回滚事务，普通保存检查磁盘身份与 revision；未知版本、坏数据与附件读取失败保留原文件。
- 导入备份与替换在同一仓库操作内串行完成；编辑、TMDb 预览、首页、排行榜、时光机及备份页面接入异步接口和按需图片。
- 更新开发说明及已有本地转换工具的新格式输出，不新增数据源。

## 2026-10-02 — 全新数据架构：验证完成

- 模型测试通过 129 项断言：版本拒绝、数据校验、身份判重、分组排序、年月／评分换组、草稿提交、完整附件往返和中断恢复。
- TMDb／仓库测试通过 57 项断言：并发保存不丢条目、失败保持原状态与 revision、仓库时间戳、导入前备份与外部文件替换保护。
- 本地转换工具使用临时 SQLite／图片夹验证，输出由 Swift LibraryDocument 成功解码与校验。
- 通用 iOS Simulator 构建成功，git diff --check 通过；未启动模拟器，未进行运行时界面验证。

## 2026-10-02 — 参考 AniShelf 优化 TMDb 网络

- 用户授权复用 AniShelf 网络方案；参考 RedirectingHTTPClient 的 API 主机重写与限流重试，以及 TMDbAPIKeyValidator 的两条 relay 主机。
- 默认保留直连；设置新增可选 AniShelf 代理，主机为 tmdb-api.konakona.dev / tmdb-api.konakona52.com，只在所选代理组内故障切换，成功线路缓存 5 分钟。自定义代理不自动向其他主机转发凭据。
- API／图片使用有期限的标准系统 URLSession 配置；API 凭据请求不使用磁盘 URL 缓存或 Cookie，保留 HTTPS、证书校验与同主机同端口重定向限制。
- 短暂断线有界重试；API 502／503／504 和 429 有界重试；取消、鉴权失败与限流不触发线路切换。错误区分超时、DNS、TLS、断网及代理层拒绝访问。
- 更新 AniShelf 开源归属说明。未引入其他数据源、第三方 UI 或额外依赖。
- 验证：TMDb／仓库测试通过 91 项断言，模型测试通过 129 项断言，通用 iOS Simulator 构建成功，git diff --check 通过；未启动模拟器。
- 使用本地构建凭据进行 Mac URLSession 实测：直连 configuration 与 search/movie 返回 HTTP 200（搜索得到 12 项），海报 CDN HTTP 200。两条 AniShelf 代理均返回非 TMDb 响应的 HTTP 403，新客户端按代理拒绝访问处理；未宣称代理可用或真机已验证，凭据未输出。

### 2026-10-02 — 1.1.2（Build 7）
- Debug／Release 版本统一更新为 1.1.2，构建号递增至 7。
- 本次版本包含全新本地数据架构、串行事务式存储、对应页面与备份接入，以及 TMDb 请求重试、可选 AniShelf relay 和网络诊断改进。
- 模型与 TMDb／仓库测试、通用 iOS Simulator 构建及差异格式检查通过；未启动模拟器。创建本地 commit，不推送。
