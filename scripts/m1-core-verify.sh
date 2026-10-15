#!/usr/bin/env bash
set -eu
set -o pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
ref="${1:?task ref}"
filter="${2:?test filter}"
case "$ref:$filter" in M1.T2:ReaderWriterTests|M1.T3:DetectorTests) ;; *) exit 2 ;; esac
out="tasks/$ref-build"
mkdir -p "$out"
if test -f "$out/verification.log"; then
    previous_logs="$(mktemp -d "$out/previous.XXXXXX")"
    cp "$out"/*.log "$previous_logs/"
fi
exec >"$out/verification.log" 2>&1
trap 'result=$?; if [ "$result" -ne 0 ]; then tail -n 20 "$out/core-test.log" >"$out/failure-tail.log" 2>/dev/null || true; fi; echo "verification_exit=$result"' EXIT
swift test --package-path Swift/CSVCore --scratch-path "$PWD/$out/CoreBuild" --filter "$filter" >"$out/core-test.log" 2>&1
printf 'core_test_exit=0\n'
git diff --exit-code -- 'Table Tool' 'Table Tool.xcodeproj' 'Table ToolTests' >"$out/legacy-diff.log"
printf 'legacy_unchanged=pass\n'
find Swift/CSVCore -type f -name '*.swift' -not -path '*/.build/*' -exec shasum -a 256 {} \; >"$out/source-sha256.log"
printf 'module_regression=pass\n'
