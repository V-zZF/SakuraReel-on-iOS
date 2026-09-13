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

- [ ] 创建 `RankingsView`，从首页 Push 进入
- [ ] 顶部：返回 / 评分排行榜 / 排序
- [ ] 第二行：共 N 部 / 平均 N 分（仅统计已评分）
- [ ] 实现排行榜横向列表条目（排名、海报、片名、评分、年月）
- [ ] 实现排行榜排序：评分 > 观看时间 > sortIndex
- [ ] 实现同评分内手动排序
- [ ] 实现跨评分拖动提示并阻止移动

## Phase 6 — 搜索

- [ ] 点击「搜索」胶囊变为可编辑搜索栏
- [ ] 实时按片名过滤
- [ ] 搜索结果复用 `MediaCard` 与 adaptive 网格
- [ ] 处理空搜索状态与取消恢复

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
- 编译通过（Swift 6 语言模式，无警告）；模拟器安装启动、正常模式渲染验证通过
- **未验证**：排序模式的拖动重排、跨组提示弹窗、落盘结果 —— 需要在模拟器 / 真机上手动拖一遍确认
