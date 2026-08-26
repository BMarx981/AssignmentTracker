#!/usr/bin/env bash
# Build, sign, and notarize a distributable macOS release.
#
# One-time setup (see README):
#   1. Create a "Developer ID Application" certificate
#        Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application
#   2. Store notarization credentials in the Keychain
#        xcrun notarytool store-credentials assignment-tracker \
#          --apple-id <your-apple-id> --team-id 6W3F7S8Q67 \
#          --password <app-specific-password from appleid.apple.com>
set -euo pipefail

TEAM_ID="${TEAM_ID:-6W3F7S8Q67}"
NOTARY_PROFILE="${NOTARY_PROFILE:-assignment-tracker}"
APP_NAME="Assignment Tracker"

cd "$(dirname "$0")/.."
ROOT="$PWD"
ARCHIVE="$ROOT/build/macos/Runner.xcarchive"
OUT="$ROOT/build/dist"
APP="$OUT/$APP_NAME.app"
ZIP="$OUT/AssignmentTracker-macos.zip"

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "error: no 'Developer ID Application' certificate in the Keychain." >&2
  echo "       Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application" >&2
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "error: no notarytool credentials stored under profile '$NOTARY_PROFILE'." >&2
  echo "       xcrun notarytool store-credentials $NOTARY_PROFILE \\" >&2
  echo "         --apple-id <your-apple-id> --team-id $TEAM_ID --password <app-specific-password>" >&2
  exit 1
fi

echo "==> Configuring Flutter build"
rm -rf "$ARCHIVE" "$OUT"
flutter build macos --release --config-only

echo "==> Archiving (Developer ID, hardened runtime)"
xcodebuild archive \
  -workspace macos/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

cat > "$ROOT/build/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
PLIST

echo "==> Exporting"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$ROOT/build/ExportOptions.plist" \
  -exportPath "$OUT"

echo "==> Notarizing (this uploads to Apple and waits)"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Verifying"
spctl -a -vvv -t exec "$APP"
xcrun stapler validate "$APP"

echo
echo "Done: $ZIP"
