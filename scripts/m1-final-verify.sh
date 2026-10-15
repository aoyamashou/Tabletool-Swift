#!/usr/bin/env bash
# 完整M1验证，不重跑已闭环的J5 dirty探针；新保存集成使用独立SaveProbe。
set -eu
set -o pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
out=tasks/M1.T5-build
mkdir -p "$out"
if test -f "$out/verification.log"; then
    previous_logs="$(mktemp -d "$out/previous.XXXXXX")"
    cp "$out"/*.log "$previous_logs/"
fi
exec >"$out/verification.log" 2>&1
trap 'result=$?; if [ "$result" -ne 0 ]; then tail -n 20 "$out/app-build.log" "$out/core-test.log" "$out/save-test.log" "$out/preflight.log" >"$out/failure-tail.log" 2>/dev/null || true; fi; echo "verification_exit=$result"' EXIT
xcodebuild -project Swift/TableToolSwift.xcodeproj -scheme TableToolSwift -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$PWD/$out/DerivedData" CODE_SIGNING_ALLOWED=NO build >"$out/app-build.log" 2>&1
printf 'app_build_exit=0\n'
app="$PWD/$out/DerivedData/Build/Products/Debug/TableToolSwift.app"
# Local ad-hoc identity only. No keychain identity, certificate, timestamp service or publication.
codesign --force --sign - --entitlements Swift/TableToolApp/TableToolSwift.entitlements --timestamp=none "$app" >"$out/local-sign.log" 2>&1
codesign --verify --strict "$app" >>"$out/local-sign.log" 2>&1
codesign -d --entitlements :- "$app" >"$out/entitlements.log" 2>&1
printf 'local_adhoc_signature=pass\n'
swift test --package-path Swift/CSVCore --scratch-path "$PWD/$out/CoreBuild" >"$out/core-test.log" 2>&1
printf 'core_test_exit=0\n'
bash scripts/probes/save-tests/run.sh "$PWD/$out/SaveProbe" >"$out/save-test.log" 2>&1
printf 'save_test_exit=0\n'
PREFLIGHT_BUILD_ROUTE=xcode PREFLIGHT_APP_PATH="$PWD/$out/DerivedData/Build/Products/Debug/TableToolSwift.app" PREFLIGHT_CORE_PROBE="$PWD/$out/SaveProbe/core-read-probe" bash scripts/preflight.sh >"$out/preflight.log" 2>&1
printf 'preflight_exit=0\n'
if PREFLIGHT_BUILD_ROUTE=xcode PREFLIGHT_APP_PATH="$PWD/$out/missing.app" bash scripts/preflight.sh >"$out/preflight-negative.log" 2>&1; then
    echo 'negative_preflight_unexpected_success'; exit 1
fi
rg -q '^check: config_match fail ' "$out/preflight-negative.log"
printf 'negative_preflight=pass\n'
git diff --exit-code -- 'Table Tool' 'Table Tool.xcodeproj' 'Table ToolTests' >"$out/legacy-diff.log"
printf 'legacy_unchanged=pass\n'
lipo -archs "$out/DerivedData/Build/Products/Debug/TableToolSwift.app/Contents/MacOS/TableToolSwift" >"$out/architectures.log"
test "$(cat "$out/architectures.log")" = arm64
printf 'app_arm64=pass\n'
git status --short >"$out/git-status.log"
find Swift scripts -type f \( -name '*.swift' -o -name '*.pbxproj' -o -name '*.sh' -o -name '*.plist' -o -name '*.entitlements' \) -not -path '*/.build/*' -not -path '*/xcuserdata/*' -exec shasum -a 256 {} \; >"$out/source-sha256.log"
