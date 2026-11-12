#!/bin/sh
#
# Builds and runs the spreadsheet-import check against docs/import-test-files/.
# Run from anywhere:  scripts/import-check/run.sh
#
# The import logic is compiled with the same language settings as the app
# target (Swift 5 mode, MainActor default isolation, approachable concurrency,
# member import visibility), so code that would not be callable off the main
# actor in the app does not compile here either.
#
# Set SWIFTC to use a particular compiler; otherwise xcrun's (macOS) or the
# one on PATH (Linux) is used.

set -eu

root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${TMPDIR:-/tmp}/stash-import-check"

if [ -z "${SWIFTC:-}" ]; then
    if command -v xcrun >/dev/null 2>&1; then SWIFTC="xcrun swiftc"; else SWIFTC="swiftc"; fi
fi

$SWIFTC \
    -swift-version 5 \
    -default-isolation MainActor \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -enable-upcoming-feature InferIsolatedConformances \
    -enable-upcoming-feature InferSendableFromCaptures \
    -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
    -enable-upcoming-feature DisableOutwardActorInference \
    -enable-upcoming-feature MemberImportVisibility \
    -warnings-as-errors \
    "$root/Stash/Import/SpreadsheetParser.swift" \
    "$root/Stash/Import/ImportFieldParsing.swift" \
    "$root/Stash/Import/ImportMapping.swift" \
    "$root/Stash/Import/ImportPlanner.swift" \
    "$root/scripts/import-check/main.swift" \
    -o "$out"

"$out" "$root/docs/import-test-files"
