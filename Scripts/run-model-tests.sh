#!/bin/zsh
# 跑模型层的断言：快照导出 / 导入 / 旧版迁移 / 双顺序。
#
# 直接 swiftc 编译那几个只依赖 Foundation 的文件，不经过 Xcode 工程、不需要模拟器、
# 也不需要单元测试 target。被测代码一旦 import 了 SwiftUI 或 Observation，这个脚本
# 就会编译失败 —— 那正是它该失败的时候。
#
#   ./Scripts/run-model-tests.sh
#
set -e

cd "$(dirname "$0")/.."

OUT="$(mktemp -d)/model-tests"

# 顺序无关，swiftc 会一起编。main.swift 提供顶部代码入口（Swift 只允许它写顶层语句）。
swiftc -O -o "$OUT" \
  SakuraReel/Models/MediaItem.swift \
  SakuraReel/Models/MediaStatus.swift \
  SakuraReel/Utilities/MediaSort.swift \
  SakuraReel/Utilities/RankingMetrics.swift \
  SakuraReel/Utilities/GridColumns.swift \
  SakuraReel/Utilities/TimeMachineMoments.swift \
  SakuraReel/Services/LibraryArchive.swift \
  Tests/ModelTests/main.swift \
  Tests/ModelTests/LibraryArchiveTests.swift \
  Tests/ModelTests/RankingMetricsTests.swift \
  Tests/ModelTests/GridColumnsTests.swift \
  Tests/ModelTests/TimeMachineMomentsTests.swift

"$OUT"
