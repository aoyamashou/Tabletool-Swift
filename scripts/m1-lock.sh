#!/usr/bin/env bash
# N041/N045授权：仅固定本地实现提交。不推送、不改Git身份/远程/系统。
set -eu
set -o pipefail
cd "$(dirname "$0")/.."
mkdir -p tasks/M1-lock tasks/M1-evidence
exec >tasks/M1-lock/verification.log 2>&1
trap 'result=$?; echo "lock_exit=$result"' EXIT
rg -q '^completion_exit=0$' tasks/M1.T5-build/preflight-completion.log
rg -q '^final_verification=pass$' tasks/M1.T5-build/preflight-completion.log
rg -q 'Executed 55 tests, with 0 failures' tasks/M1.T5-build/core-test.log
rg -q '^save_probe=pass;' tasks/M1.T5-build/save-test.log
if rg -q '^FAIL ' tasks/M1.T5-build/save-test.log; then exit 1; fi
shasum -a 256 --check tasks/M1.T5-build/source-sha256.log >tasks/M1-lock/source-check.log
# Do not incorporate another contributor's already-staged changes.
git diff --cached --quiet
git diff --exit-code -- 'Table Tool' 'Table Tool.xcodeproj' 'Table ToolTests' >tasks/M1-lock/legacy-diff.log
python3 - <<'EVIDENCE'
from pathlib import Path
import shutil
root = Path('tasks/M1.T5-build')
out = Path('tasks/M1-evidence')
for name in ['app-build.log','local-sign.log','entitlements.log','core-test.log','save-test.log','preflight-completion.log','preflight.log','preflight-negative.log','signature-verify.log','architectures.log','legacy-diff.log','source-sha256.log','verification.log']:
    shutil.copyfile(root/name, out/name)
shutil.copyfile('tasks/M1.T4-build/grid-test.log',out/'T4-grid-document-historical.log')
(out/'README.md').write_text('最终证据链：K026业务构建/核心55/保存19通过 + 已批准定点预检补完。verification.log保留后置工具失败的历史exit1，最终状态见preflight-completion.log的completion_exit=0与分项原始日志。T4历史探针不是最终GUI验收；M2另行执行。所有日志为原样复制。\n')
EVIDENCE
git add -- .gitignore Swift/README.md Swift/CSVCore/Package.swift Swift/CSVCore/CONTRACT.md Swift/CSVCore/Sources Swift/CSVCore/Tests Swift/TableToolApp Swift/TableToolSwift.xcodeproj/project.pbxproj scripts/preflight.sh scripts/m1-t1-verify.sh scripts/m1-core-verify.sh scripts/m1-grid-verify.sh scripts/m1-final-verify.sh scripts/m1-preflight-complete.sh scripts/m1-lock.sh scripts/probes/grid-tests scripts/probes/save-tests tasks/M1-plan.md tasks/M1.T1-report.md tasks/M1.T2-report.md tasks/M1.T3-report.md tasks/M1.T4-report.md tasks/M1.T5-report.md tasks/M1.T3-design.md tasks/M1.T4-design.md tasks/M1.T4-dirty-diagnosis.md tasks/M1.T5-preflight-diagnosis.md tasks/M1.T5-static-review.md tasks/M2-acceptance-checklist.md tasks/M2-fixtures tasks/M1-evidence
# Explicit product/docs list above excludes local binaries, package caches, messages and user memory.
git diff --cached --name-only >tasks/M1-lock/staged-files.log
git diff --cached --check -- . ':!tasks/M1-evidence' >tasks/M1-lock/whitespace.log
git commit -F tasks/M1-commit-message.txt >tasks/M1-lock/commit-output.log 2>&1
git rev-parse HEAD >tasks/M1-fixed-commit.txt
git show --format=fuller --stat HEAD >tasks/M1-lock/commit.log
git diff --exit-code -- Swift scripts/preflight.sh scripts/m1-t1-verify.sh scripts/m1-core-verify.sh scripts/m1-grid-verify.sh scripts/m1-final-verify.sh scripts/m1-preflight-complete.sh scripts/m1-lock.sh scripts/probes/grid-tests scripts/probes/save-tests >tasks/M1-lock/product-diff.log
git status --short >tasks/M1-lock/final-status.log
printf 'local_commit=pass\n'
