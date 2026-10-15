#!/usr/bin/env bash
# 本地Mac构建/业务预检；GUI验收另行进行。不启动服务、不修改系统配置。
set -u
set -o pipefail
cd "$(dirname "$0")/.." || exit 2
mkdir -p logs || exit 2
PREFLIGHT_LOG="logs/preflight-$(date +%Y%m%d-%H%M%S)-$$.log"
FAILED=0
check() {
  local name="$1" fn="$2" msg
  if msg="$("$fn" 2>&1)"; then
    printf 'check: %s pass %s\n' "$name" "$msg" | tee -a "$PREFLIGHT_LOG" || FAILED=1
  else
    printf 'check: %s fail %s\n' "$name" "$msg" | tee -a "$PREFLIGHT_LOG"
    FAILED=1
  fi
}
c_git_identity() {
  local n e
  n="$(git config user.name)" && e="$(git config user.email)" &&
    test -n "$n" && test -n "$e" || { echo 'Git身份缺失或为空；需单独授权配置'; return 1; }
  echo 'Git姓名与邮箱均已配置（不输出个人信息）'
}
c_native_host() {
  test "$(uname -s)" = Darwin && test "$(uname -m)" = arm64 || {
    echo '要求原生arm64 macOS进程，不能用Rosetta代替'; return 1;
  }
  echo "原生arm64 macOS $(sw_vers -productVersion)"
}
c_xcode() {
  local version
  version="$(xcodebuild -version 2>&1)" || { echo "$version"; return 1; }
  xcrun --find swiftc >/dev/null && xcrun --find ibtool >/dev/null &&
    xcrun --sdk macosx --show-sdk-path >/dev/null || return 1
  echo "${version//$'\n'/; }"
}
c_build_toolchain() {
  local version route="${PREFLIGHT_BUILD_ROUTE:-clt}"
  if test "$route" = xcode; then c_xcode; return $?; fi
  test "$route" = clt || { echo "未知构建路线：$route"; return 1; }
  version="$(xcrun swiftc --version 2>&1)" && xcrun --find clang >/dev/null &&
    xcrun --sdk macosx --show-sdk-path >/dev/null &&
    swift package --version >/dev/null || return 1
  echo "CLT/纯代码AppKit路线；${version//$'\n'/; }"
}
c_config_match() {
  local app="${PREFLIGHT_APP_PATH:-$PWD/tasks/M1.T5-build/DerivedData/Build/Products/Debug/TableToolSwift.app}"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes:0:NSDocumentClass' Swift/TableToolApp/Info.plist)" = CSVDocument &&
    test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' Swift/TableToolApp/TableToolSwift.entitlements)" = true &&
    test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-write' Swift/TableToolApp/TableToolSwift.entitlements)" = true &&
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes:0:NSDocumentClass' "$app/Contents/Info.plist")" = CSVDocument &&
    test -f Swift/CSVCore/Package.swift && test -f Swift/TableToolSwift.xcodeproj/project.pbxproj || return 1
  test "$(lipo -archs "$app/Contents/MacOS/TableToolSwift")" = arm64 || return 1
  echo 'Swift源配置与构建应用文档类一致；arm64；沙盒仅用户选中文件读写；无mock或登录配置'
}
c_service_alive() {
  test -f Swift/TableToolApp/Application.swift && test -f Swift/TableToolApp/CSVDocument.swift || return 1
  echo '不适用：本地NSApplication/NSDocument应用无后台服务；脱离终端启动及窗口操作按M2独立GUI验收'
}
c_login_ok() {
  test -f Swift/TableToolApp/AppDelegate.swift || return 1
  echo '不适用：本地应用无账号或登录；不代表GUI验收'
}
c_data_readable() {
  local probe="${PREFLIGHT_CORE_PROBE:-$PWD/tasks/M1.T5-build/SaveProbe/core-read-probe}" result
  test -x "$probe" || { echo "缺少已构建的Swift CSVCore业务探针：$probe"; return 1; }
  result="$("$probe" 'Table ToolTests/Reading Test Documents/comma-separated.csv' 2>&1)" || {
    echo "核心实际读取失败：$result"; return 1;
  }
  echo "${result}；磁盘保存失败保护及完整回归见tasks/M1.T5-build/"
}
check git_identity c_git_identity
check native_host c_native_host
check build_toolchain c_build_toolchain
if xcodebuild -version >/dev/null 2>&1; then
  printf 'info: full_xcode available; build_route=%s\n' "${PREFLIGHT_BUILD_ROUTE:-clt}" | tee -a "$PREFLIGHT_LOG"
else
  printf 'info: full_xcode unavailable_in_active_directory; legacy_xcode_project=blocked; build_route=%s\n' "${PREFLIGHT_BUILD_ROUTE:-clt}" | tee -a "$PREFLIGHT_LOG"
fi
check config_match c_config_match
check service_alive c_service_alive
check login_ok c_login_ok
check data_readable c_data_readable
printf 'log: %s\n' "$PREFLIGHT_LOG"
exit "$FAILED"
