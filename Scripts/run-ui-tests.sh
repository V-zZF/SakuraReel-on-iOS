#!/bin/zsh
# 跑 UI 测试：Phase 4 首页排序模式 + Phase 6 搜索 + Phase 5 排行榜。
#
# 两组测试类依赖**不同**的库数据，所以分两轮各写各的 fixture：
# - Phase 4 断言 2024.03 组三条的顺序，且靠库里唯一的「10」定位评分按钮；
#   Phase 6 搜索也用这份数据，两个类在同一轮里一起跑
# - Phase 5 需要同一评分横跨不同观看年月的条目，会引入额外的 10 分条目
# 合成一份会让 Phase 4 的「10」变成多匹配、网格变高导致卡片不可点。
#
#   ./Scripts/run-ui-tests.sh [模拟器名称]
#
set -e

cd "$(dirname "$0")/.."

DEVICE_NAME="${1:-iPhone 17 Pro}"
PROJECT="SakuraReel.xcodeproj"
SCHEME="SakuraReel"
DERIVED="build/DerivedData"

BUNDLE_ID="com.yourdomain.SakuraReel"

# 1. 找到并启动模拟器
UDID=$(xcrun simctl list devices available | awk -v name="$DEVICE_NAME" \
  '$0 ~ name && $0 ~ /\(Shutdown\)|\(Booted\)/ {gsub(/[()]/, "", $0); print $(NF-1); exit}')
if [ -z "$UDID" ]; then
  echo "找不到模拟器：$DEVICE_NAME" >&2
  exit 1
fi
echo "模拟器：$DEVICE_NAME ($UDID)"
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null

# 2. 先构建并安装，才有数据容器可以写
#
# 构建失败必须**当场中止**：`xcodebuild ... | tail -1` 配 `set -e` 是抓不到失败码的
# （管道的退出码取自 tail），脚本会拿着上一次的旧测试包接着跑，结果全是假的。
BUILD_LOG="$(mktemp)"
if ! xcodebuild build-for-testing \
  -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED" > "$BUILD_LOG" 2>&1; then
  echo "❌ 构建测试包失败，已中止（继续跑只会拿旧包，结果不可信）：" >&2
  grep -E "error:" "$BUILD_LOG" | head -20 >&2
  rm -f "$BUILD_LOG"
  exit 1
fi
tail -1 "$BUILD_LOG"
rm -f "$BUILD_LOG"

xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/SakuraReel.app"

# 3. 写 fixture（每次运行都重置，保证可重复）
#
# 容器路径必须每次现取：test-without-building 会重装 App，重装后数据容器的 UUID
# 会变，开机时取的那份就失效了（表现为 FileNotFoundError）。
write_fixture() {
  local container
  container="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
  mkdir -p "$container/Documents/Posters"
  python3 - "$container" "$1" <<'PY'
import json, sys, uuid, os
c, phase = sys.argv[1], sys.argv[2]
now = "2026-09-13T12:00:00Z"

def mk(title, status, year, month, rating, sort_index):
    # 刻意不写 rankIndex：旧库文件就是这个样子，顺带验证向后兼容能正常解码
    return {"id": str(uuid.uuid4()).upper(), "title": title, "status": status,
            "watchYear": year, "watchMonth": month, "rating": rating,
            "review": None, "playURL": None, "sortIndex": sort_index,
            "createdAt": now, "updatedAt": now}

if phase == "home":
    # 2024.03 三条（组内可拖动）、2024.01 一条（跨组落点）、未设年份一条
    items = [
        mk("千与千寻", "watched", 2024, 3, 10, 0),
        mk("星际穿越", "watched", 2024, 3, 9, 1),
        mk("你想活出怎样的人生", "watched", 2024, 3, 8, 2),
        mk("沙丘2", "watched", 2024, 1, 7, 0),
        mk("阿诺拉", "wantToWatch", None, None, 0, 0),
    ]
else:
    # 10 分组三条横跨两个观看年月：同评分跨年月拖动是 Phase 5 的关键场景
    items = [
        mk("千与千寻", "watched", 2024, 3, 10, 0),
        mk("星际穿越", "watched", 2024, 3, 9, 1),
        mk("你想活出怎样的人生", "watched", 2024, 3, 8, 2),
        mk("沙丘2", "watched", 2024, 1, 7, 0),
        mk("阿诺拉", "wantToWatch", None, None, 0, 0),
        mk("攻壳机动队", "watched", 2024, 5, 10, 0),
        mk("千年女优", "watched", 2024, 5, 10, 1),
    ]

path = os.path.join(c, "Documents", "SakuraReelLibrary.json")
with open(path, "w") as f:
    json.dump(items, f, ensure_ascii=False, indent=2, sort_keys=True)
print("已写入 %s fixture（%d 条）：%s" % (phase, len(items), path))
PY
}

# 跑测试类，接受多个 -only-testing 参数（同一份 fixture 的几个类一起跑），
# 返回 xcodebuild 的退出码（失败会让脚本以非零退出）
run_test_class() {
  # 变量不能叫 status：zsh 里 $status 是只读的特殊变量
  local log exit_code=0
  log="$(mktemp)"
  xcodebuild test-without-building \
    -project "$PROJECT" -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED" \
    "$@" > "$log" 2>&1 || exit_code=$?
  grep -E "Test Case .* (passed|failed)|Executed .* tests|TEST (EXECUTE )?(SUCCEEDED|FAILED)|error:" "$log" || true
  rm -f "$log"
  return $exit_code
}

HOME_OK=0
RANK_OK=0

# 4. Phase 4 首页排序模式 + Phase 6 搜索（共用同一份 home fixture）
write_fixture home
if run_test_class "-only-testing:SakuraReelUITests/HomeSortModeUITests" \
                  "-only-testing:SakuraReelUITests/SearchUITests"; then
  echo "✅ Phase 4 首页排序模式 + Phase 6 搜索：全部通过"
  HOME_OK=1
else
  echo "❌ Phase 4 首页排序模式 / Phase 6 搜索：有失败用例"
fi

# 5. Phase 5 — 排行榜
write_fixture ranking
if run_test_class "-only-testing:SakuraReelUITests/RankingsUITests"; then
  echo "✅ Phase 5 排行榜：全部通过"
  RANK_OK=1
else
  echo "❌ Phase 5 排行榜：有失败用例"
fi

if [ "$HOME_OK" = 1 ] && [ "$RANK_OK" = 1 ]; then
  echo "全部通过"
  exit 0
else
  echo "有失败用例"
  exit 1
fi
