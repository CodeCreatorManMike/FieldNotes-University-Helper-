#!/bin/bash
# Builds the release binary and wraps it in a minimal .app bundle
# (FieldnotesIsland.app) — needed for notification authorization and
# SMAppService (launch-at-login) to work reliably; a loose binary via
# `swift run` can't register either with Launch Services.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release

APP="FieldnotesIsland.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/FieldnotesIsland "$APP/Contents/MacOS/FieldnotesIsland"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>FieldnotesIsland</string>
	<key>CFBundleIdentifier</key>
	<string>com.fieldnotes.island</string>
	<key>CFBundleName</key>
	<string>Fieldnotes Island</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>LSUIElement</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSHumanReadableCopyright</key>
	<string>Local, personal use.</string>
</dict>
</plist>
EOF

echo "Built: $(pwd)/$APP"
echo "Run:   open \"$(pwd)/$APP\""
