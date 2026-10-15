#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
out="${1:?output directory required}"
mkdir -p "$out"
# Compile independently of XCTest and the app; use the same public core module.
swiftc -emit-library -emit-module -module-name CSVCore "$root"/Swift/CSVCore/Sources/CSVCore/*.swift -emit-module-path "$out/CSVCore.swiftmodule" -o "$out/libCSVCore.dylib"
swiftc -I "$out" -L "$out" -lCSVCore -Xlinker -rpath -Xlinker "$out" "$root/Swift/TableToolApp/GridModel.swift" "$root/scripts/probes/grid-tests/main.swift" -o "$out/grid-tests"
"$out/grid-tests"

swiftc -I "$out" -L "$out" -lCSVCore -Xlinker -rpath -Xlinker "$out" "$root/Swift/TableToolApp/GridModel.swift" "$root/Swift/TableToolApp/GridViewController.swift" "$root/Swift/TableToolApp/CSVFileSafety.swift" "$root/Swift/TableToolApp/CSVDocument.swift" "$root/scripts/probes/grid-tests/DocumentProbe.swift" -o "$out/document-probe"
"$out/document-probe"
