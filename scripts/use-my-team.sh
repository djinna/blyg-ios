#!/bin/bash
# Point this project at your own Apple developer team and bundle ID, so you can run it on your phone
# and upload it to your own TestFlight. Apple ties bundle IDs to one team, so a fork can't keep net.jdbb.blyg.
#
#   scripts/use-my-team.sh <TEAM_ID> <BUNDLE_ID>
#   scripts/use-my-team.sh ABCDE12345 com.example.blyg
#
# Your team ID is the 10-character code in Xcode (Settings → Accounts) or at developer.apple.com/account.
# The Share extension gets <BUNDLE_ID>.share. Run it once on a fresh clone, then build in Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM=${1:-}; BUNDLE=${2:-}
[[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || { echo "Team ID should be 10 capital letters and digits, e.g. ABCDE12345." >&2; exit 1; }
[[ "$BUNDLE" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || { echo "Bundle ID should look like com.example.blyg." >&2; exit 1; }

OLD_TEAM=$(sed -n 's/.*"DEVELOPMENT_TEAM": "\([A-Z0-9]*\)".*/\1/p' Blyg.xcodeproj/project.xcproj | sort -u)
OLD_BUNDLE=$(sed -n 's/.*"PRODUCT_BUNDLE_IDENTIFIER": "\([^"]*\)".*/\1/p' Blyg.xcodeproj/project.xcproj | sort | head -1)
[ "$(wc -l <<<"$OLD_TEAM" | tr -d ' ')" = 1 ] || { echo "Targets disagree on DEVELOPMENT_TEAM: $OLD_TEAM" >&2; exit 1; }

# The app's own ID is the shortest; the tests and the extension extend it (…tests, …uitests, …share).
sed -i '' -e "s/\"DEVELOPMENT_TEAM\": \"$OLD_TEAM\"/\"DEVELOPMENT_TEAM\": \"$TEAM\"/g" \
          -e "s/\"PRODUCT_BUNDLE_IDENTIFIER\": \"$OLD_BUNDLE/\"PRODUCT_BUNDLE_IDENTIFIER\": \"$BUNDLE/g" \
          Blyg.xcodeproj/project.xcproj
sed -i '' "s#<key>teamID</key><string>$OLD_TEAM</string>#<key>teamID</key><string>$TEAM</string>#" scripts/ExportOptions.plist
sed -i '' "s/BUNDLE=$OLD_BUNDLE /BUNDLE=$BUNDLE /" scripts/phone.sh

echo "Team $OLD_TEAM → $TEAM"
sed -n 's/.*"PRODUCT_BUNDLE_IDENTIFIER": "\([^"]*\)".*/  \1/p' Blyg.xcodeproj/project.xcproj
echo "Now open Blyg.xcodeproj, or run: scripts/phone.sh"
echo "The Keychain group (\$(AppIdentifierPrefix)net.jdbb.blyg.shared) follows your team by itself; no change needed."
