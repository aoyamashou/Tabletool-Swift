#!/usr/bin/env bash
# K026业务构建/55核心/19保存断言已通过，只补尚未执行的业务探针编译与预检。
set -eu
set -o pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
out=tasks/M1.T5-build
if test -f "$out/preflight-completion.log"; then
    previous_logs="$(mktemp -d "$out/previous-preflight.XXXXXX")"
    cp "$out"/preflight*.log "$previous_logs/"
fi
exec >"$out/preflight-completion.log" 2>&1
trap 'result=$?; echo "completion_exit=$result"' EXIT
rg -q '^app_build_exit=0$' "$out/verification.log"
rg -q '^core_test_exit=0$' "$out/verification.log"
rg -q 'Executed 55 tests, with 0 failures' "$out/core-test.log"
rg -q '^save_probe=pass;' "$out/save-test.log"
if rg -q '^FAIL ' "$out/save-test.log"; then exit 1; fi
probe="$PWD/$out/SaveProbe"
swiftc -parse-as-library -target arm64-apple-macos13.0 -I "$probe" -L "$probe" -lCSVCore -Xlinker -rpath -Xlinker "$probe" scripts/probes/save-tests/CoreReadProbe.swift -o "$probe/core-read-probe" >"$out/core-read-build.log" 2>&1
"$probe/core-read-probe" 'Table ToolTests/Reading Test Documents/comma-separated.csv'
app="$PWD/$out/DerivedData/Build/Products/Debug/TableToolSwift.app"
PREFLIGHT_BUILD_ROUTE=xcode PREFLIGHT_APP_PATH="$app" PREFLIGHT_CORE_PROBE="$probe/core-read-probe" bash scripts/preflight.sh >"$out/preflight.log" 2>&1
printf 'preflight_exit=0\n'
if PREFLIGHT_BUILD_ROUTE=xcode PREFLIGHT_APP_PATH="$PWD/$out/missing.app" PREFLIGHT_CORE_PROBE="$probe/core-read-probe" bash scripts/preflight.sh >"$out/preflight-negative.log" 2>&1; then
    echo 'negative_preflight_unexpected_success'; exit 1
fi
rg -q '^check: config_match fail ' "$out/preflight-negative.log"
printf 'negative_preflight=pass\n'
codesign --verify --strict "$app" >"$out/signature-verify.log" 2>&1
printf 'local_adhoc_signature=pass\n'
lipo -archs "$app/Contents/MacOS/TableToolSwift" >"$out/architectures.log"
test "$(cat "$out/architectures.log")" = arm64
printf 'app_arm64=pass\n'
git diff --exit-code -- 'Table Tool' 'Table Tool.xcodeproj' 'Table ToolTests' >"$out/legacy-diff.log"
printf 'legacy_unchanged=pass\n'
git status --short >"$out/git-status.log"
find Swift -type f \( -name '*.swift' -o -name '*.pbxproj' -o -name '*.plist' -o -name '*.entitlements' \) -not -path '*/.build/*' -not -path '*/xcuserdata/*' -exec shasum -a 256 {} \; >"$out/source-sha256.log"
printf 'final_verification=pass\n'
