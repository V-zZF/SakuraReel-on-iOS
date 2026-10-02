# SakuraReel

一款使用 SwiftUI 构建的个人影视收藏库，适用于 iPhone 和 iPad。手动收藏作品、记录观看进度和感受，让自己的观影经历有处可寻。

[![CI](https://github.com/V-zZF/SakuraReel-on-iOS/actions/workflows/ci.yml/badge.svg)](https://github.com/V-zZF/SakuraReel-on-iOS/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-iOS%20%2F%20iPadOS%2018%2B-black)
![Swift](https://img.shields.io/badge/Swift-6-orange)

## 功能

- **个人收藏**：海报、片名、看过 / 在看 / 想看、观看年月、整数评分、短评与播放链接。
- **全库搜索**：按片名搜索全部分类，支持系统本地化匹配。
- **手动排序**：首页同观看年月内调整顺序；排行榜同评分内调整顺序，两套顺序独立保存。
- **排行榜**：按评分展示作品；`0` 表示未评分，评分范围为 `0–10`。
- **时光机**：长按首页标题进入，按季度回顾看过的作品。支持左右滑动、点选季度与卡片，以及点击中央海报翻面阅读短评。
- **本地文件与手动迁移**：资料库以 JSON 和独立海报文件保存，支持通过系统文件夹选择器导出、导入。

界面保持浅色，使用樱花粉作为强调色。内容由用户手动添加，不接入影视数据库、社区或自建账号服务。

## 数据、备份与导入

主资料库保存在 App 沙盒的 `Documents` 目录：

```text
Documents/
├── SakuraReelLibrary.json
├── Posters/
│   └── <作品 UUID>.jpg
└── 导入前备份.json          # 执行导入前生成，仅包含元数据
```

`SakuraReelLibrary.json` 保存作品信息和独立的 `homeOrder`、`rankingOrder` 顺序。海报单独存储，不嵌入 JSON；旧版条目数组格式可在加载时迁移。

在系统「文件」App 的「我的 iPhone / 我的 iPad → SakuraReel」中查看文件。完整备份需要同时复制 JSON 与 `Posters` 文件夹。

首页「资料库文件」菜单可选择同步文件夹，随后手动导出或导入。文件夹可以来自本机或系统文件提供商；App 不使用 CloudKit，也不自动同步。云端文件是否可用由对应文件提供商管理。

**导入会用所选文件夹的整库数据覆盖本机**，包括作品、两套顺序和海报。本机独有作品会被删除；导入前会展示数量并要求确认。自动生成的「导入前备份.json」不包含海报，因此导入前建议另做完整备份。导出也会更新目标文件夹中的资料库及海报，请为资料库选择专用文件夹。

## 构建与运行

当前版本为 **1.0.0（Build 4）**，最低系统版本为 **iOS / iPadOS 18**。

需要 macOS、Xcode 与 iOS SDK。工程使用 Swift 6 语言模式及 Icon Composer 图标；CI 使用 Xcode 26.6，本地已在 Xcode 27.0 验证构建。没有第三方 Swift 包依赖。

```bash
git clone https://github.com/V-zZF/SakuraReel-on-iOS.git
cd SakuraReel-on-iOS
open SakuraReel.xcodeproj
```

在 Xcode 中选择 `SakuraReel` scheme 和 iPhone / iPad 模拟器后运行。安装到实机时，在 **Signing & Capabilities** 中选择自己的开发团队，并根据需要修改 Bundle Identifier。

无需签名的模拟器构建：

```bash
xcodebuild \
  -project SakuraReel.xcodeproj \
  -scheme SakuraReel \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/SakuraReel-DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 验证

```bash
./Scripts/run-model-tests.sh
git diff --check
```

模型测试直接使用 `swiftc` 编译 Foundation 层，无需启动模拟器。覆盖快照导入导出、旧版迁移、双顺序维护、网格列数、排行榜尺寸和时光机季度逻辑。当前包含 95 项断言；这些测试不验证动画、手势或真实文件提供商行为。

GitHub Actions 在推送和 Pull Request 时运行模型测试与模拟器构建。交互检查清单见 [贡献指南](CONTRIBUTING.md)。

## 项目结构

```text
SakuraReel/
├── App/             # App 入口与配置
├── Models/          # Codable 数据模型
├── Views/           # 首页、添加编辑、排行榜、时光机
├── Components/      # 卡片、网格、Cover Flow 等可复用视图
├── Services/        # JSON 持久化、海报处理、文件夹导入导出
└── Utilities/       # 排序、评分颜色、尺寸与季度分组
Scripts/             # 模型测试及资料库转换工具
Tests/ModelTests/    # Foundation 层断言
```

维护入口：`MediaRepository` 管理本地读写；`MediaSort` 管理排序；`RatingColor` 管理评分颜色；`RankingMetrics` 管理排行榜卡片尺寸。

[开发日志](DEVLOG.md)记录已完成的变更；[开发计划](CodingPlan.md)保留阶段规划；[AGENTS.md](AGENTS.md)记录项目约定。

## 反馈与贡献

请通过 [Issues](https://github.com/V-zZF/SakuraReel-on-iOS/issues)反馈问题或建议，提交代码前阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。仓库目前未指定开源许可证。
