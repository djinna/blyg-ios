#!/bin/bash
# Archive the committed project and upload it to TestFlight (for internal and external testing).
# Ask Jenna before running. Bump CURRENT_PROJECT_VERSION in project.xcproj (every target) and commit first.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=Blyg OUT=DerivedData.noindex
LOG=$OUT/testflight.log; mkdir -p "$OUT"; : >"$LOG"
fail() { grep -E 'error:|ERROR:|FailureReason' "$LOG" | sort -u | head -20 || true; echo "$1 failed. Log: $LOG" >&2; exit 1; }

[ -z "$(git status --porcelain)" ] || { echo "Commit first, so the build matches a commit." >&2; exit 1; }
BUILD=$(sed -n 's/.*"CURRENT_PROJECT_VERSION": "\([0-9]*\)".*/\1/p' Blyg.xcodeproj/project.xcproj | sort -u)
[ "$(wc -l <<<"$BUILD" | tr -d ' ')" = 1 ] || { echo "Targets disagree on CURRENT_PROJECT_VERSION: $BUILD" >&2; exit 1; }
ARCHIVE=$OUT/$APP-$BUILD.xcarchive
echo "Archiving build $BUILD ($(git rev-parse --short HEAD))"

xcodebuild -scheme "$APP" -destination 'generic/platform=iOS' -derivedDataPath "$OUT" \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates archive >>"$LOG" 2>&1 || fail Archive
echo "Uploading build $BUILD (log: $LOG)"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$OUT/export-$BUILD" -allowProvisioningUpdates >>"$LOG" 2>&1 || {
  grep -q "Redundant Binary Upload" "$LOG" && { echo "Build $BUILD is already uploaded: bump CURRENT_PROJECT_VERSION." >&2; exit 1; }
  fail Upload; }
grep -E "Upload succeeded|EXPORT SUCCEEDED" "$LOG" | tail -2
echo "Build $BUILD uploaded. App Store Connect takes a few minutes to process it before TestFlight shows it."
