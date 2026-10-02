# SakuraReel

一款使用 SwiftUI 构建的个人影视收藏库，适用于 iPhone 和 iPad。手动收藏作品、记录观看进度和感受，让自己的观影经历有处可寻。

[![CI](https://github.com/V-zZF/SakuraReel-on-iOS/actions/workflows/ci.yml/badge.svg)](https://github.com/V-zZF/SakuraReel-on-iOS/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-iOS%20%2F%20iPadOS%2018%2B-black)
![Swift](https://img.shields.io/badge/Swift-6-orange)

## 功能

- **个人收藏**：海报、片名、看过 / 在看 / 想看、观看年月、整数评分、短评与播放链接。
- **TMDb 辅助录入**：搜索所有电影、剧集或季度，预览并选择字段后填入添加表单；点击保存才入库。
- **作品详情**：本地背景与 Logo、个人评分、观看年月、总时长、短评、简介与作品资料，以及演职员和季度／单集摘要；个人记录与作品资料可分别编辑。
- **全库搜索**：按片名搜索全部分类，支持系统本地化匹配。
- **手动排序**：首页同观看年月内调整顺序；排行榜同评分内调整顺序，两套顺序独立保存。
- **排行榜**：按评分展示作品；`0` 表示未评分，评分范围为 `0–10`。
- **时光机**：长按首页标题进入，按季度回顾看过的作品。支持左右滑动、点选季度与卡片，以及点击中央海报翻面阅读短评。
- **本地文件与手动迁移**：资料库以 JSON 和独立海报文件保存，支持通过系统文件夹选择器导出、导入。

界面保持浅色，使用樱花粉作为强调色。支持手动添加与用户主动使用 TMDb 辅助录入。TMDb 是一次性数据源，打开详情不会自动更新资料；不接入社区、自建账号或自动云同步。

## 布局与排序

首页与排序网格以每张卡片连同分摊间隙约 **550 屏幕像素**作为宽度参考，通过当前显示比例换算为 SwiftUI 点数。网格直接使用当前窗口视口宽度，实时增减列数，至少一列，剩余宽度均分；没有固定五列上限。支持 iPad 窗口缩放、分栏及 iPhone／iPad 横竖屏切换。海报保持 2:3，片名预留两行。搜索结果使用满宽横向卡片。

首页按观看年份、月份从新到旧，再按年月组内顺序排列，只能在同年同月内拖动。排行榜按评分从高到低，同评分手动顺序优先，其余依次使用观看时间及首页组内顺序，只能在同评分内拖动。评分颜色统一来自 `RatingColor`。

排行榜通过 `RankingMetrics` 按可用区域计算卡高与内部缩放：iPhone 与 iPad 横屏以一屏五张为基准，iPad 竖屏以可用宽度计算卡高；iPad 横屏列表收窄并居中。

## 数据、备份与导入

主资料库保存在 App 沙盒的 `Documents` 目录：

```text
Documents/
├── SakuraReelLibrary.json
├── Posters/
│   └── <作品 UUID>.jpg
├── Artwork/
│   └── <作品 UUID>/
│       ├── backdrop.jpg
│       └── logo.png
├── 导入前完整备份/           # JSON、海报与作品图片，可作为导入目录恢复
└── 读取失败备份-<UUID>/     # 恢复不可读资料库前保留的原始文件
```

`SakuraReelLibrary.json` 使用全新版本 1 文档：`schemaVersion`、`libraryID`、`revision`、`items`、`homeGroups` 和 `rankingGroups`。条目拆为作品资料 `work`、个人记录 `personal`、类型化 TMDb 来源 `source`、附件描述 `attachments` 与时间戳。观看年月是完整的 `YearMonth`；本地 UUID 与 TMDb 身份独立。

首页持久化年月组内顺序，排行榜只持久化已手动排序的评分组；未手动组按观看年月及首页组内顺序排列。没有旧排序索引或重复片名。新格式不兼容旧快照和旧条目数组，也不提供迁移；无法读取时保留原文件，不自动清空。

海报、背景和 Logo 单独存储，不嵌入 JSON。列表不携带图片字节，附件按需加载并使用有上限的内存缓存。搜索缩略图与演职员头像位于可清理的 Caches，不进入备份。

在系统「文件」App 的「我的 iPhone / 我的 iPad → SakuraReel」中查看文件。完整备份需要同时复制 JSON、`Posters` 与 `Artwork` 文件夹。

首页「资料库文件」菜单可选择同步文件夹，随后手动导出或导入。文件夹可以来自本机或系统文件提供商；App 不使用 CloudKit，也不自动同步。云端文件是否可用由对应文件提供商管理。

**导入会用所选文件夹的整库数据覆盖本机**，包括作品资料、两套顺序和所有永久图片。本机独有作品会被删除；导入前会展示数量并要求确认。自动生成的「导入前完整备份」包含资料与永久图片，可通过选择此文件夹再导入恢复。导出也会更新目标文件夹中的资料库及附件，请选择专用文件夹。保存由独立串行存储执行器完成，采用暂存、完整回滚和提交标记；成功落盘后才发布界面状态并递增文档 revision。保存失败保持原库，读取损坏 JSON 不会自动清空原文件。普通保存检查磁盘资料库身份与 revision，避免覆盖在 App 外替换的文件。缺失图片显示占位并报告，已有但不可读的图片使保存失败。

## TMDb 使用

1. 点击首页加号，默认进入 TMDb 搜索；尚未配置 Key 时先展示使用指引，提供注册、登录、获取 API 的官网按钮。官网按钮下方直接提供高亮的 **v3 API Key** 输入框，点击「保存并搜索」继续。
2. 指引页可「跳过，使用默认 API」，默认 Key 写入本机 Keychain，并使用直连。搜索页底部保留「手动添加」；指引页也可以直接手动添加。顶部不再提供 TMDb／收藏库切换，已有作品仍可使用首页全库搜索。
3. 搜索页分类为番剧（默认）、节目、电影；空关键词显示热门作品，输入片名后搜索，支持分页。番剧热门筛选日本动画剧集，节目及电影热门按各自类型获取。结果采用横向卡片，左侧海报，右侧片名、完整日期与简介。右上角剧集显示「单季」，电影显示「选择」；点击剧集海报或文字可录入整部，点击「单季」进入季度选择（含特别篇），每次导入一个作品。语言菜单、分类、设置可在搜索页调整。首页「资料库文件」→「TMDb 设置」也可修改或删除 Key、验证线路。
4. 选择作品，预览字段和海报候选；默认只填空字段。应用后进入原表单，设置个人记录，再点击原有「保存」。取消不产生永久图片。海报失败可重试、继续文本录入或从相册选图。
5. 点击首页／排行榜卡片进入详情；更多菜单可编辑个人记录、编辑全部作品资料或主动重新获取。重新获取先预览，不自动替换已有字段。TMDb 评分与个人整数评分独立，官网、简介和上映日期不会写入播放链接、短评或观看年月。重复提示提供打开已有详情的入口。
6. 默认直连。在 TMDb 设置开启「使用 API 代理」后可选「AniShelf 代理」或自定义 HTTPS 主机。AniShelf 代理使用 `tmdb-api.konakona.dev`，连接失败时尝试 `tmdb-api.konakona52.com`，短期优先复用成功线路。API Key 会经过所选第三方主机；直连和自定义代理不会自动切到 AniShelf。图片仍直连 TMDb CDN。
7. API 与图片请求使用有期限的标准系统网络会话，保留系统代理／VPN 和 TLS 校验。短暂断线重试一次，API 临时服务错误与限流有界重试；鉴权失败、取消和限流不触发代理切换。错误提示区分超时、DNS、TLS 和断网。

用户填写的 Key 只保存在本机 Keychain，不进入源码、收藏库 JSON、备份、导出或日志。用户授权的默认凭据由 `Configuration/TMDb.local.xcconfig` 提供，此文件被 Git 忽略；`TMDb.xcconfig` 在 Debug／Release 中可选加载它，经构建占位符随 App 的 Info.plist 提供，点击跳过后写入 Keychain。默认凭据因此可从构建包提取，不能作为服务端秘密。其他电脑或 CI 如需默认 API，应自行提供同名本地配置中的 `TMDB_DEFAULT_API_KEY`；未配置的构建仍可填写个人 Key 或手动添加。

搜索及获取使用 Foundation + URLSession，没有额外 SDK。图片配置与进行中请求会复用；取消最后一个使用者会停止请求。SVG Logo 尝试 PNG 版本，失败回退片名。

背景与 Logo 导入成功后进入永久附件；演职员头像、季度海报和单集缩略图是可再获取缓存。完整剧集只保存季度摘要，季度条目保存单集摘要；不实现逐集追踪、提醒、批量添加或自动全库刷新。

## 构建与运行

当前版本为 **1.2.1（Build 10）**，最低系统版本为 **iOS / iPadOS 18**。

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

## 1.2.1 更新

- 修复 Mac 上以 iPad 兼容模式运行时，打开详情弹窗缺少仓库环境对象导致调试进程暂停。
- 首页直接读取视口尺寸，修复窗口放大后缩小时网格超出窗口，支持实时增减列数。
- 搜索结果改为横向海报简介卡片，「选择」／「单季」按钮位于右上角。
- 详情页单集／季度标题显式使用黑色，日期和展示图标使用品牌粉色。

这些变更已通过自动测试与通用模拟器构建；Mac 窗口缩放、旋转与颜色效果仍需运行时交互验收。

## 验证

```bash
./Scripts/run-model-tests.sh
./Scripts/run-tmdb-tests.sh
git diff --check
```

模型测试直接使用 `swiftc` 编译 Foundation 层，无需启动模拟器。覆盖快照导入导出、不兼容格式拒绝、双顺序维护、窗口宽度与显示比例下的网格列数、排行榜尺寸和时光机季度逻辑。当前包含 185 项模型断言及 113 项 TMDb／仓库检查。服务检查使用注入的虚构响应，不读取真实 Key；覆盖乱序搜索／图片、分页重试、取消、限流、配置切换、可选资源失败、重复拒绝及保存失败。测试不验证动画、手势、真实 TMDb 响应或真实文件提供商行为。

GitHub Actions 在推送和 Pull Request 时运行模型测试、TMDb 服务检查与模拟器构建。交互检查清单见 [贡献指南](CONTRIBUTING.md)。

## 项目结构

```text
SakuraReel/
├── App/             # App 入口与配置
├── Models/          # Codable 数据模型
├── Views/           # 首页、详情、添加编辑、TMDb流程、排行榜、时光机
├── Components/      # 卡片、网格、Cover Flow 等可复用视图
├── Services/        # 串行JSON存储、图片处理、导入导出、TMDb与Keychain
└── Utilities/       # 排序、评分颜色、尺寸与季度分组
Scripts/             # 模型测试及资料库转换工具
Tests/ModelTests/    # Foundation 层断言
Tests/TMDbTests/     # TMDb服务与仓库检查
```

维护入口：`MediaRepository` 管理本地读写；`MediaSort` 管理排序；`RatingColor` 管理评分颜色；`RankingMetrics` 管理排行榜卡片尺寸。

[开发日志](DEVLOG.md)记录已完成的变更；[开发计划](CodingPlan.md)保留阶段规划；[AGENTS.md](AGENTS.md)记录项目约定。

## 反馈与贡献

请通过 [Issues](https://github.com/V-zZF/SakuraReel-on-iOS/issues)反馈问题或建议，提交代码前阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。仓库目前未指定开源许可证。
