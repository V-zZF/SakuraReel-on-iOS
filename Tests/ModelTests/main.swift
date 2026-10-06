import Foundation

// 模型层断言的入口。由 Scripts/run-model-tests.sh 用 swiftc 直接编译运行，
// 不依赖 Xcode 工程、不依赖模拟器、不需要单元测试 target。
//
// 之所以能这样跑：LibraryArchive / MediaItem / MediaSort 都只依赖 Foundation。
// 那条约束要一直保持，否则这个脚本会先坏掉。

var checkCount = 0
var failureCount = 0

func expect(_ condition: Bool, _ message: String) {
    checkCount += 1
    if !condition {
        failureCount += 1
        print("  ❌ \(message)")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    expect(actual == expected, "\(label)：期望 \(expected)，实际 \(actual)")
}

runTMDbMetadataTests()
runArchiveTests()
runDocumentTests()
runSyncTests()
runRankingMetricsTests()
runGridColumnsTests()
runTimeMachineMomentsTests()

print("")
if failureCount == 0 {
    print("✅ 模型层测试全部通过（\(checkCount) 项断言）")
    exit(0)
} else {
    print("❌ \(failureCount) 项失败 / 共 \(checkCount) 项断言")
    exit(1)
}
