#!/bin/bash
# Builds File Explorer.app from source. Requires only the Xcode Command Line Tools.
set -e
cd "$(dirname "$0")"

APP="build/File Explorer.app"
NAME="File Explorer"
BUNDLE_ID="com.winexplorer.mac"
VERSION="1.0"

echo "==> Compiling"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -whole-module-optimization \
    -target arm64-apple-macos14.0 \
    Sources/*.swift \
    -o "$APP/Contents/MacOS/FileExplorer"

echo "==> Building icon"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
SRC="Resources/AppIcon.png"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" \
            "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
    set -- $spec
    sips -Z "$1" "$SRC" --out "$ICONSET/icon_$2.png" >/dev/null 2>&1
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp "$SRC" "$APP/Contents/Resources/AppIcon.png"

echo "==> Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$NAME</string>
    <key>CFBundleDisplayName</key>       <string>$NAME</string>
    <key>CFBundleExecutable</key>        <string>FileExplorer</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSQuitAlwaysKeepsWindows</key>  <false/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSDesktopFolderUsageDescription</key>
    <string>File Explorer needs access to show the contents of your Desktop.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>File Explorer needs access to show the contents of your Documents folder.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>File Explorer needs access to show the contents of your Downloads folder.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>File Explorer needs access to show the contents of connected drives.</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>File Explorer needs access to show photos in the Gallery.</string>
</dict>
</plist>
PLIST

echo "==> Signing"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "   (ad-hoc signing skipped)"

echo "==> Done: $APP"
