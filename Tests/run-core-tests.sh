#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
source_file=PantryScanner/Pantry/SimpleNewsApp.swift
# Compile the production lookup and filters with small model fixtures; no iOS SDK needed.
awk '/^actor BarcodeLookupService / { copy=1 } /^\/\/ MARK: - Notification Manager/ { copy=0 } copy' "$source_file" > "$workdir/Core.swift"
awk '/^enum InventoryCategory:/ { copy=1 } /^struct ItemRow:/ { copy=0 } copy' "$source_file" >> "$workdir/Core.swift"
cat Tests/CoreChecks.swift "$workdir/Core.swift" > "$workdir/Checks.swift"
swiftc -swift-version 5 -parse-as-library "$workdir/Checks.swift" -o "$workdir/checks"
"$workdir/checks"
