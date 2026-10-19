#!/bin/bash
# macOS 單元測試（不啟動 Simulator）：只印通過、失敗、略過的數量與每個失敗的訊息（包括 crash）。
# 額外的參數交給 xcodebuild，例如 tools/test.sh -only-testing:voice_todoTests/NarratorTests
set -u
cd "$(dirname "$0")/.."

# 交給其他 module 保存的 closure 用 [weak self]：對方可能比 self 活得久，unowned 的對象先釋放時會 crash。
if grep -rn "unowned self" voice_todo/; then
    echo "❌ 上面的 closure 改用 [weak self]"
    exit 1
fi
# 專案檔以 Signing.xcconfig 為基礎設定：不在 git 裡時，clone 的人建置失敗（見 .gitignore）。
if ! git ls-files --error-unmatch Signing.xcconfig >/dev/null 2>&1; then
    echo "❌ Signing.xcconfig 不在 git 裡"
    exit 1
fi

# 有本機的 Team 就用它簽章：ad-hoc 簽章每次 build 都不同，系統會一直重新詢問權限（見 Signing.xcconfig）。
signing=()
[ -f Signing.local.xcconfig ] && signing=(-xcconfig Signing.local.xcconfig)

dir=$(mktemp -d)
xcodebuild test -scheme voice_todo -destination 'platform=macOS' -skip-testing:voice_todoUITests \
    ${signing[@]+"${signing[@]}"} -resultBundlePath "$dir/result.xcresult" "$@" > "$dir/build.log" 2>&1

if ! summary=$(xcrun xcresulttool get test-results summary --path "$dir/result.xcresult" 2>/dev/null); then
    echo "❌ 沒有測試結果（建置失敗？）完整紀錄：$dir/build.log"
    grep -E "error:" "$dir/build.log" | sort -u | head -20
    exit 1
fi

echo "$summary" | python3 -c '
import json, sys
s = json.load(sys.stdin)
passed, failed, skipped = s["passedTests"], s["failedTests"], s["skippedTests"]
print(f"通過 {passed}、失敗 {failed}、略過 {skipped}")
for f in s["testFailures"]:
    name, text = f["testIdentifierString"], f["failureText"].strip()
    print(f"❌ {name}\n   {text}")
sys.exit(1 if failed else 0)
'
