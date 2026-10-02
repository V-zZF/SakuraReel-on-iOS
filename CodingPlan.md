SakuraReel 开发计划

从零开发一款 iOS / iPadOS 个人影视收藏库应用 SakuraReel。核心不是功能多，而是数据可靠、交互正确、Apple 原生感、视觉精致。本计划覆盖从产品定义、技术选型、模块拆分、执行顺序到每阶段验收标准的完整路径。

已确认的关键决策
项目	决策
最低系统版本	iOS 18+（Observation / @Observable 所需）
技术栈	Swift / SwiftUI / 本地 JSON 文件存储（无 SwiftData、无 CloudKit）
数据存储	App 沙盒 Documents 目录，文件可在系统「文件」App 中直接查看 / 备份
海报存储	poster 不入 JSON；单独存为 Documents/Posters/<id>.jpg
数据同步	无 iCloud / CloudKit，数据只存在本机
海报选择	PhotosPicker（相册），Phase 1 仅支持相册
播放链接	同时支持 http/https 与自定义 URL Scheme
搜索交互	搜索胶囊变为可编辑搜索栏，实时过滤片名
删除确认	需要二次确认 Alert
评分	整数 0–10 步进
观看年月	两个独立 Picker（年 + 月）
iPad 网格	Adaptive 自适应，目标约 5 列，不硬编码设备型号
排行榜入口	Push 导航
平均评分	只统计已评分作品（rating > 0）
视觉方向	浅色 + 樱花粉强调 + Apple 原生感
项目目录结构
/Users/zhangzifan/code/SakuraReel
├── App/
│   ├── SakuraReelApp.swift
│   └── Info.plist
├── Models/
│   ├── MediaItem.swift
│   └── MediaStatus.swift
├── Views/
│   ├── ContentView.swift
│   ├── HomeView.swift
│   ├── RankingsView.swift
│   └── AddEditMediaView.swift
├── Components/
│   ├── MediaCard.swift
│   ├── RatingLabel.swift
│   ├── PosterView.swift
│   ├── PosterPlaceholderView.swift
│   ├── EmptyStateView.swift
│   ├── CategoryCapsule.swift
│   ├── SearchCapsule.swift
│   ├── AddButton.swift
│   ├── TopBarButton.swift
│   ├── PlayButtonOverlay.swift
│   ├── YearMonthPickers.swift
│   ├── PosterImagePicker.swift
│   └── UnsavedChangesHandler.swift
├── Services/
│   ├── MediaRepository.swift
│   └── PosterResizer.swift
└── Utilities/
    ├── RatingColor.swift
    ├── MediaSort.swift
    ├── WatchDateFormatter.swift
    ├── AdaptiveGridLayout.swift
    └── Constants.swift
核心数据模型
import Foundation

enum MediaStatus: String, Codable, CaseIterable, Identifiable {
    case watched
    case watching
    case wantToWatch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .watched: return "看过"
        case .watching: return "在看"
        case .wantToWatch: return "想看"
        }
    }
}

struct MediaItem: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var status: MediaStatus
    var watchYear: Int?
    var watchMonth: Int?
    var rating: Int        // 0 = 未评分
    var review: String?
    var playURL: String?
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date

    // 海报不入库 JSON，单独存为 Documents/Posters/<id>.jpg
    var poster: Data?

    init(
        id: UUID = UUID(),
        title: String,
        poster: Data? = nil,
        status: MediaStatus,
        watchYear: Int? = nil,
        watchMonth: Int? = nil,
        rating: Int = 0,
        review: String? = nil,
        playURL: String? = nil,
        sortIndex: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.poster = poster
        self.status = status
        self.watchYear = watchYear
        self.watchMonth = watchMonth
        self.rating = max(0, min(10, rating))
        self.review = review
        self.playURL = playURL
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
评分颜色统一方案
import SwiftUI

struct RatingColor {
    static func color(for rating: Int) -> Color {
        switch rating {
        case 0:      return Color(hex: "E5E5EA")
        case 1...3:  return Color(hex: "C7C7CC")
        case 4...5:  return Color(hex: "F8A5B6")
        case 6...7:  return Color(hex: "F08080")
        case 8...9:  return Color(hex: "E88398")
        case 10:     return Color(hex: "E2556B")
        default:     return Color.gray
        }
    }
}

struct RatingForegroundModifier: ViewModifier {
    let rating: Int
    func body(content: Content) -> some View {
        content.foregroundStyle(RatingColor.color(for: rating))
    }
}

extension View {
    func ratingColor(rating: Int) -> some View {
        modifier(RatingForegroundModifier(rating: rating))
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        _ = scanner.scanString("#")
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}
排序逻辑独立封装
import Foundation

enum HomeSortMode {
    case `default`   // 观看时间从新到旧
    case manual      // 同年同月内按 sortIndex
}

enum MediaSort {
    static func homeSorted(_ items: [MediaItem], mode: HomeSortMode) -> [MediaItem] {
        switch mode {
        case .default:
            return items.sorted {
                if $0.watchYear != $1.watchYear { return ($0.watchYear ?? -1) > ($1.watchYear ?? -1) }
                if $0.watchMonth != $1.watchMonth { return ($0.watchMonth ?? -1) > ($1.watchMonth ?? -1) }
                return $0.sortIndex < $1.sortIndex
            }
        case .manual:
            return items.sorted { $0.sortIndex < $1.sortIndex }
        }
    }

    static func rankingSorted(_ items: [MediaItem]) -> [MediaItem] {
        items.sorted {
            if $0.rating != $1.rating { return $0.rating > $1.rating }
            if $0.watchYear != $1.watchYear { return ($0.watchYear ?? -1) > ($1.watchYear ?? -1) }
            if $0.watchMonth != $1.watchMonth { return ($0.watchMonth ?? -1) > ($1.watchMonth ?? -1) }
            return $0.sortIndex < $1.sortIndex
        }
    }

    static func homeGroupKey(year: Int?, month: Int?) -> Int {
        guard let year = year, let month = month else { return -1 }
        return year * 100 + month
    }

    static func rankingGroupKey(rating: Int) -> Int {
        return rating
    }
}
拖动限制：

首页：源与目标必须具有相同的 homeGroupKey
排行榜：源与目标必须具有相同的 rankingGroupKey
本地文件存储（替代 SwiftData + CloudKit）
目标：数据保存在 App 沙盒 Documents 目录，用户能在「文件」App 中直接查看 / 备份。

文件结构（「文件」App > 我的 iPhone > SakuraReel）
- SakuraReelLibrary.json：所有条目元数据，prettyPrinted + iso8601 日期
- Posters/：海报图片，<条目 id>.jpg

Info.plist 配置
UIFileSharingEnabled = YES
LSSupportsOpeningDocumentsInPlace = YES

MediaRepository（@MainActor @Observable）
- items: [MediaItem]：内存中的全部条目，视图通过 @Environment(MediaRepository.self) 读取
- load() / save()：读写 Documents/SakuraReelLibrary.json，并管理 Posters/ 下的海报文件
- upsert(_:) / delete(_:)：新增 / 更新 / 删除，操作后立即落盘
- posterURL(for:)：Documents/Posters/<id>.jpg
- 排序索引维护（Phase 4）：每次重排后重新分配连续 sortIndex
模块化执行方案
按 7 个 Phase 推进，每个 Phase 内部再拆成若干可独立交付的小里程碑。每完成一个里程碑就更新 DEVLOG.md，保证上下文不膨胀。

Phase 1 — 基础架构
目标：让项目能编译运行，数据能存取。

1.1 创建 Xcode 项目

项目名 SakuraReel
iOS 18 Deployment Target
开启文件共享（Info.plist：UIFileSharingEnabled、LSSupportsOpeningDocumentsInPlace）
建立目录结构
1.2 数据模型

MediaStatus.swift
MediaItem.swift（Codable 结构体）
1.3 设计系统

RatingColor.swift
Constants.swift（樱花粉强调色、圆角、间距）
1.4 本地文件数据层

MediaRepository.swift 读写 Documents/SakuraReelLibrary.json 与 Posters/
SakuraReelApp.swift 创建 MediaRepository，通过 .environment 注入
移除 CloudKitConfiguration.swift 与 SakuraReel.entitlements（无 CloudKit / iCloud）
1.5 基础导航

ContentView.swift 作为根视图
HomeView.swift 空壳
RankingsView.swift 空壳
验收：App 在 iPhone 模拟器启动无崩溃，能读取 / 写入本地 JSON 文件。

Phase 2 — 首页
目标：完成首页核心 UI 与空状态。

2.1 顶部导航

正常模式：排序 / SakuraReel / 排行
排序模式：✕ / SakuraReel / 完成
2.2 分类胶囊

看过 / 在看 / 想看 / 搜索
当前选中樱花粉
2.3 影视卡片

PosterView + 2:3 占位符
MediaCard：海报、片名（最多两行）、评分、观看年月、播放按钮
2.4 自适应网格

AdaptiveGridLayout
iPhone 约 2 列，iPad 约 5 列
2.5 空状态

EmptyStateView
添加作品入口
2.6 添加按钮

AddButton 樱花粉圆形
验收：首页能切换分类、显示卡片、适配 iPhone/iPad、空状态正常。

Phase 3 — 添加 / 编辑
目标：完整表单与保存/删除逻辑。

3.1 Sheet 骨架

AddEditMediaView：添加 / 编辑两种模式
底部按钮：添加 [取消 / 保存]；编辑 [删除 / 取消 / 保存]
3.2 海报选择

PosterImagePicker + PosterResizer
相册选择后裁剪为 2:3、压缩为 JPEG，写入 Documents/Posters/<id>.jpg
3.3 表单字段

片名（必填）
分类 Picker
观看年月（两个 Picker）
评分（0–10 步进）
短评
播放链接
3.4 保存与删除

MediaRepository.upsert / delete 封装 CRUD（操作后立即落盘）
删除二次确认
未保存内容提示
保存/删除后自动关闭 Sheet
验收：能新增、编辑、删除作品；未保存时弹窗提示；海报正确压缩；「文件」App 中可见 SakuraReelLibrary.json 与 Posters/。

Phase 4 — 排序
目标：首页默认排序与手动排序。

4.1 默认排序

观看时间从新到旧
同年同月按 sortIndex
4.2 排序模式

点击顶部「排序」进入
卡片可拖动
完成退出
4.3 同年月拖动限制

只能调整相同 homeGroupKey 内顺序
跨组拖动显示提示：「无法移动 只能调整相同观看年月内的作品顺序。」
验收：手动排序持久化到 JSON，跨组拖动不修改数据并弹出提示。

Phase 5 — 排行榜
目标：排行榜页面与评分排序。

5.1 排行榜 UI

顶部：返回 / 评分排行榜 / 排序
第二行：共 N 部 / 平均 N 分
横向列表条目
5.2 评分排序

第一优先级：评分高到低
第二优先级：观看时间近到远
第三优先级：sortIndex
5.3 同分手动排序

排序模式下同 rating 内可拖动
跨评分拖动提示：「无法移动 只能调整相同评分内的作品顺序。」
验收：排行榜顺序正确，同分内可排序，跨分有提示。

Phase 6 — 搜索
目标：按片名搜索。

6.1 搜索胶囊

点击「搜索」胶囊变为输入框
实时过滤
6.2 搜索结果

复用 MediaCard + adaptive 网格
空搜索状态
验收：搜索实时过滤，取消后回到原分类。

Phase 7 — UI Polish
目标：动画、细节、iPad 适配、无障碍。

卡片点击轻微缩放
分类切换平滑
排序拖动抬起/缩放/阴影/触觉反馈
图片加载淡入
删除淡出
Sheet 原生过渡
Dynamic Type / VoiceOver 检查
iPad Split View / Slide Over
验收：整体体验精致、动画轻量、无视觉/交互明显问题。

关键复用组件
组件	职责
MediaCard	影视卡片
PosterView	海报解码与占位
PosterPlaceholderView	樱花占位
RatingLabel	评分显示（大字+小字）
CategoryCapsule	分类胶囊
SearchCapsule	搜索胶囊/搜索栏
AddButton	添加按钮
TopBarButton	顶部工具按钮
PlayButtonOverlay	播放按钮
YearMonthPickers	年月选择
PosterImagePicker	海报选择器
EmptyStateView	空状态
UnsavedChangesHandler	未保存检测
AdaptiveGridLayout	自适应网格
CLAUDE.md 草案
# SakuraReel — Claude 工作记忆

## 项目定位
个人影视收藏与观看记录 App。不要做成影视资讯或社区。数据存于本地文件，可在「文件」App 查看。

## 核心原则
1. 数据正确 > 视觉效果
2. 优先原生 SwiftUI
3. 不擅自增加功能
4. 不改变已定规则（评分、颜色、排序、拖动限制、卡片布局、视觉方向）
5. 发现技术冲突先指出，再给原生方案

## 技术栈
- Swift / SwiftUI / 本地 JSON 文件存储（无 SwiftData、无 CloudKit）
- iOS 18+
- 无第三方 UI 框架
- 无第三方影视 API

## 关键文件
- Models/MediaItem.swift：核心数据模型（Codable 结构体）
- Utilities/RatingColor.swift：评分颜色唯一来源
- Utilities/MediaSort.swift：排序逻辑唯一来源
- Services/MediaRepository.swift：本地 JSON 读写与海报文件管理
- Services/PosterResizer.swift：海报压缩

## 视觉方向
- 浅色背景、白色卡片、樱花粉强调
- 柔和圆角、极轻阴影、大量留白
- 海报是视觉中心

## 注意事项
- 数据文件在 Documents/SakuraReelLibrary.json，海报在 Documents/Posters/
- 评分 0 表示未评分
- 首页同年同月内可拖动排序
- 排行榜同评分内可拖动排序
- 播放链接通过 UIApplication.shared.open 打开
DEVLOG.md 初始模板
# SakuraReel 开发日志

## Phase 1 — 基础架构
- [ ] 创建 Xcode 项目
- [ ] MediaItem 数据模型
- [ ] 设计系统（颜色、评分）
- [ ] 本地文件数据层（MediaRepository + 文件共享）
- [ ] 基础导航

## Phase 2 — 首页
- [ ] 顶部导航
- [ ] 分类胶囊
- [ ] 影视卡片
- [ ] 自适应网格
- [ ] 空状态
- [ ] 添加按钮

## Phase 3 — 添加/编辑
- [ ] Sheet 骨架
- [ ] 海报选择
- [ ] 表单字段
- [ ] 保存/删除

## Phase 4 — 排序
- [ ] 默认排序
- [ ] 排序模式
- [ ] 同年月拖动限制

## Phase 5 — 排行榜
- [ ] 排行榜 UI
- [ ] 评分排序
- [ ] 同分手动排序

## Phase 6 — 搜索
- [x] 搜索胶囊变搜索栏
- [x] 实时过滤

> 2026-09-14 验收：这两项在 Phase 2 重做分类选择器时就已经实现了 —— 现在是
> 「Segmented Picker + 右端独立放大镜按钮」，点放大镜在胶囊行下方滑出搜索栏、
> 边打边按片名过滤。本次**只补了 UI 用例**（`SakuraReelUITests/SearchUITests.swift`），
> 未改动任何行为。
>
> ⚠️ 注意：**这里不是进度的事实来源**。本文件的 Phase 1–7 是一份早期的
> `DEVLOG.md` 模板副本，复选框从未维护（Phase 1–5 全未勾选，而 DEVLOG 里均为 `[x]`）。
> 实际进度、以及 Phase 6 的完整四项清单，看 `DEVLOG.md`。

## Phase 7 — UI Polish
- [ ] 动画与触觉
- [ ] iPad 适配
- [ ] 无障碍
验证方式
每完成一个 Phase 的里程碑后：

Cmd+B 编译通过
在 iPhone 15 Pro1 模拟器运行
在 iPad Pro 模拟器运行
检查当前 Phase 的验收点
更新 DEVLOG.md
风险与应对
海报体积：通过压缩（600x900 JPEG 0.85）与单独文件存储（Posters/）控制。
JSON 文件被用户手动修改 / 损坏：加载失败时回退为空库并重建文件，保证 App 不崩溃。
排序索引维护：每次重排后由 MediaRepository 重新分配连续 sortIndex。
iPad 分屏：adaptive 网格会优雅降级到更少列。
未保存检测：使用独立 MediaDraft 与原始快照比较。
下一步行动
已移除 iCloud / CloudKit 同步（2026-08-22）。数据改为本地 JSON 文件存储，可在「文件」App 中查看。当前进度：Phase 1 与 Phase 2 已完成，Phase 3 待开发。后续按 Phase 顺序推进，每完成一个里程碑更新 DEVLOG.md。
