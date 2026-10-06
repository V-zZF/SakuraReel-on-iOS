#!/bin/zsh
# 跑模型层的断言：新文档校验 / 分组顺序 / 文件事务 / 完整备份。
#
# 直接 swiftc 编译那几个只依赖 Foundation / CryptoKit 的文件，不经过 Xcode 工程、不需要模拟器、
# 也不需要单元测试 target。被测代码一旦 import 了 SwiftUI 或 Observation，这个脚本
# 就会编译失败 —— 那正是它该失败的时候。
#
#   ./Scripts/run-model-tests.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

MODEL_TEST_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "$MODEL_TEST_DIRECTORY"' EXIT
OUT="$MODEL_TEST_DIRECTORY/model-tests"

# 顺序无关，swiftc 会一起编。main.swift 提供顶部代码入口（Swift 只允许它写顶层语句）。
swiftc -O -o "$OUT" \
  SakuraReel/Models/MediaMetadata.swift \
  SakuraReel/Models/MediaItem.swift \
  SakuraReel/Models/MediaStatus.swift \
  SakuraReel/Utilities/MediaSort.swift \
  SakuraReel/Utilities/RankingMetrics.swift \
  SakuraReel/Utilities/GridColumns.swift \
  SakuraReel/Utilities/TimeMachineMoments.swift \
  SakuraReel/Services/LibraryArchive.swift SakuraReel/Services/LibrarySync.swift SakuraReel/Services/LibrarySyncDisk.swift SakuraReel/Services/LibrarySyncCoordinator.swift \
  Tests/ModelTests/TMDbMetadataTests.swift \
  Tests/ModelTests/main.swift \
  Tests/ModelTests/LibraryArchiveTests.swift Tests/ModelTests/LibrarySyncTests.swift \
  Tests/ModelTests/RankingMetricsTests.swift \
  Tests/ModelTests/GridColumnsTests.swift \
  Tests/ModelTests/TimeMachineMomentsTests.swift

"$OUT"
