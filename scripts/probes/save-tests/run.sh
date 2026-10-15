#!/usr/bin/env bash
set -eu
set -o pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
out="${1:?absolute output directory}"
mkdir -p "$out"
swiftc -target arm64-apple-macos13.0 -emit-library -emit-module -module-name CSVCore "$root"/Swift/CSVCore/Sources/CSVCore/*.swift -emit-module-path "$out/CSVCore.swiftmodule" -o "$out/libCSVCore.dylib"
swiftc -target arm64-apple-macos13.0 -I "$out" -L "$out" -lCSVCore -Xlinker -rpath -Xlinker "$out" "$root/Swift/TableToolApp/GridModel.swift" "$root/Swift/TableToolApp/GridViewController.swift" "$root/Swift/TableToolApp/CSVFileSafety.swift" "$root/Swift/TableToolApp/CSVDocument.swift" "$root/scripts/probes/save-tests/SaveProbe.swift" -o "$out/save-probe"
"$out/save-probe" "$out/fixtures"

swiftc -parse-as-library -target arm64-apple-macos13.0 -I "$out" -L "$out" -lCSVCore -Xlinker -rpath -Xlinker "$out" "$root/scripts/probes/save-tests/CoreReadProbe.swift" -o "$out/core-read-probe"
"$out/core-read-probe" "$root/Table ToolTests/Reading Test Documents/comma-separated.csv"
