# SakuraReel 开发日志

## Phase 1 — 基础架构

- [x] 创建 Xcode 项目（iOS 17+，SakuraReel 名称）
- [x] 建立目录结构：App / Models / Views / Components / Services / Utilities
- [x] 创建 `Models/MediaStatus.swift`
- [x] 创建 `Models/MediaItem.swift`（含 `@Attribute(.externalStorage) poster`）
- [x] 创建 `Utilities/RatingColor.swift`（评分颜色唯一来源）
- [x] 创建 `Utilities/MediaSort.swift`（排序与拖动分组逻辑）
- [x] 创建 `Utilities/Constants.swift`（樱花粉、圆角、间距等常量）
- [x] 创建 `Services/CloudKitConfiguration.swift`
- [x] 配置 `App/SakuraReel.entitlements` 与 iCloud / CloudKit capability
- [x] 配置 `App/SakuraReelApp.swift` 的 `ModelContainer`
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

- [ ] 创建 `Services/MediaRepository.swift`（CRUD 与排序索引维护）
- [ ] 创建 `Services/PosterResizer.swift`（裁剪为 2:3、压缩 JPEG）
- [ ] 创建 `Components/PosterImagePicker.swift`（PhotosPicker 封装）
- [ ] 创建 `Components/YearMonthPickers.swift`
- [ ] 实现 `AddEditMediaView` Sheet 骨架
- [ ] 实现表单字段：片名、分类、观看年月、评分、短评、播放链接
- [ ] 实现添加模式底部按钮：[取消] [保存]
- [ ] 实现编辑模式底部按钮：[删除] [取消] [保存]
- [ ] 实现删除二次确认 Alert
- [ ] 实现未保存内容提示
- [ ] 实现保存 / 删除后自动关闭 Sheet
- [ ] 实现点击遮罩关闭与 ✕ 关闭P

## Phase 4 — 排序

- [ ] 首页默认排序：观看年月从新到旧
- [ ] 进入排序模式后卡片可拖动
- [ ] 实现同年同月内拖动重排并持久化 `sortIndex`
- [ ] 实现跨年月拖动时显示提示并阻止移动
- [ ] 点击「完成」退出排序模式

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

## Phase 7 — iCloud

- [ ] 确认 entitlements 与 CloudKit container ID
- [ ] 切换到非内存 `ModelContainer`
- [ ] 在两台设备/模拟器登录同一 iCloud 账号测试同步
- [ ] 验证片名、海报、分类、年月、评分、短评、链接、排序同步
- [ ] 处理无 iCloud 账户软提示

## Phase 8 — UI Polish

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
