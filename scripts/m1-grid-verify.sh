#!/usr/bin/env bash
set -eu
set -o pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
out=tasks/M1.T4-build
mkdir -p "$out"
if test -f "$out/verification.log"; then
    previous_logs="$(mktemp -d "$out/previous.XXXXXX")"
    cp "$out"/*.log "$previous_logs/"
fi
exec >"$out/verification.log" 2>&1
trap 'result=$?; if [ "$result" -ne 0 ]; then tail -n 20 "$out/app-build.log" "$out/grid-test.log" >"$out/failure-tail.log" 2>/dev/null || true; fi; echo "verification_exit=$result"' EXIT
xcodebuild -project Swift/TableToolSwift.xcodeproj -scheme TableToolSwift -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$PWD/$out/DerivedData" CODE_SIGNING_ALLOWED=NO build >"$out/app-build.log" 2>&1
printf 'app_build_exit=0\n'
bash scripts/probes/grid-tests/run.sh "$PWD/$out/GridProbe" >"$out/grid-test.log" 2>&1
printf 'grid_test_exit=0\n'
git diff --exit-code -- 'Table Tool' 'Table Tool.xcodeproj' 'Table ToolTests' >"$out/legacy-diff.log"
printf 'legacy_unchanged=pass\n'
lipo -archs "$out/DerivedData/Build/Products/Debug/TableToolSwift.app/Contents/MacOS/TableToolSwift" >"$out/architectures.log"
test "$(cat "$out/architectures.log")" = arm64
printf 'app_arm64=pass\n'
find Swift -type f \( -name '*.swift' -o -name '*.pbxproj' \) -not -path '*/.build/*' -not -path '*/xcuserdata/*' -exec shasum -a 256 {} \; >"$out/source-sha256.log"
