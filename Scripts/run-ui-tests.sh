#!/bin/zsh
# 跑 Phase 4 排序模式的 UI 测试。
#
# SakuraReelUITests 依赖首页存在一组固定的测试数据，这个脚本先写进模拟器的
# Documents 目录，再执行 xcodebuild test。每次运行都会重置数据，保证可重复。
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
xcodebuild build-for-testing \
  -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED" \
  | tail -1

xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/SakuraReel.app"

# 3. 写入测试数据：2024.03 三条（可组内拖动）、2024.01 一条（跨组落点）、
#    未设年份一条（验证排序模式显示全部条目）
CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
mkdir -p "$CONTAINER/Documents/Posters"
python3 - "$CONTAINER" <<'PY'
import json, sys, uuid, os
c = sys.argv[1]
now = "2026-09-13T12:00:00Z"

def mk(title, status, year, month, rating, sort_index):
    return {"id": str(uuid.uuid4()).upper(), "title": title, "status": status,
            "watchYear": year, "watchMonth": month, "rating": rating,
            "review": None, "playURL": None, "sortIndex": sort_index,
            "createdAt": now, "updatedAt": now}

items = [
    mk("千与千寻", "watched", 2024, 3, 10, 0),
    mk("星际穿越", "watched", 2024, 3, 9, 1),
    mk("你想活出怎样的人生", "watched", 2024, 3, 8, 2),
    mk("沙丘2", "watched", 2024, 1, 7, 0),
    mk("阿诺拉", "wantToWatch", None, None, 0, 0),
]
path = os.path.join(c, "Documents", "SakuraReelLibrary.json")
with open(path, "w") as f:
    json.dump(items, f, ensure_ascii=False, indent=2, sort_keys=True)
print("已写入测试数据：%s" % path)
PY

# 4. 跑测试
xcodebuild test-without-building \
  -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED" \
  -only-testing:SakuraReelUITests/HomeSortModeUITests \
  | grep -E "Test Case .* (passed|failed)|Executed .* tests|TEST (EXECUTE )?(SUCCEEDED|FAILED)|error:"
