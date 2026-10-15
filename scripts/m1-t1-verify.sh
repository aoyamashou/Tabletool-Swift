#!/usr/bin/env bash
# M1.T1：仅构建/测试独立Swift骨架，不启动GUI、不安装、不签名发布。
set -eu
set -o pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p tasks/M1.T1-build
if test -f tasks/M1.T1-build/verification.log; then
    previous_logs="$(mktemp -d tasks/M1.T1-build/previous.XXXXXX)"
    cp tasks/M1.T1-build/*.log "$previous_logs/"
fi
exec >tasks/M1.T1-build/verification.log 2>&1
trap 'result=$?; if [ "$result" -ne 0 ]; then tail -n 20 tasks/M1.T1-build/app-build.log tasks/M1.T1-build/core-test.log 2>/dev/null >tasks/M1.T1-build/failure-tail.log || true; fi; echo "verification_exit=$result"' EXIT
xcodebuild -version >tasks/M1.T1-build/toolchain.log
uname -m >tasks/M1.T1-build/host-architecture.log
git rev-parse HEAD >tasks/M1.T1-build/base-commit.log
git diff --exit-code -- 'Table Tool' 'Table Tool.xcodeproj' 'Table ToolTests' >tasks/M1.T1-build/legacy-diff.log
printf 'legacy_unchanged=pass\n'
plutil -lint Swift/TableToolApp/Info.plist Swift/TableToolApp/TableToolSwift.entitlements Swift/TableToolSwift.xcodeproj/project.pbxproj >tasks/M1.T1-build/plist.log
xcodebuild -project Swift/TableToolSwift.xcodeproj -scheme TableToolSwift -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$PWD/tasks/M1.T1-build/DerivedData" CODE_SIGNING_ALLOWED=NO build >tasks/M1.T1-build/app-build.log 2>&1
printf 'app_build_exit=0\n'
swift test --package-path Swift/CSVCore --scratch-path "$PWD/tasks/M1.T1-build/CoreBuild" >tasks/M1.T1-build/core-test.log 2>&1
printf 'core_test_exit=0\n'
app_binary="$PWD/tasks/M1.T1-build/DerivedData/Build/Products/Debug/TableToolSwift.app/Contents/MacOS/TableToolSwift"
file "$app_binary" >tasks/M1.T1-build/architecture.log
lipo -archs "$app_binary" >tasks/M1.T1-build/architectures.log
test "$(cat tasks/M1.T1-build/architectures.log)" = arm64
printf 'app_arm64=pass\n'
otool -L "$app_binary" >tasks/M1.T1-build/linkage.log
# 新目标仅Swift源文件+本地CSVCore依赖，保留可复查的配置与源码摘要。
xcodebuild -project Swift/TableToolSwift.xcodeproj -scheme TableToolSwift -showBuildSettings CODE_SIGNING_ALLOWED=NO >tasks/M1.T1-build/build-settings.log 2>&1
find Swift -type f \( -name '*.swift' -o -name '*.plist' -o -name '*.pbxproj' -o -name '*.entitlements' \) -not -path '*/.build/*' -not -path '*/xcuserdata/*' -exec shasum -a 256 {} \; >tasks/M1.T1-build/source-sha256.log
printf 'contract_and_skeleton=pass\n'
