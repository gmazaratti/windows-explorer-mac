#!/bin/bash
# Builds File Explorer.app from source. Requires only the Xcode Command Line Tools.
set -e
cd "$(dirname "$0")"

APP="build/File Explorer.app"
NAME="File Explorer"
BUNDLE_ID="com.winexplorer.mac"
VERSION="1.0"

# Pass --universal to build a binary that also runs on Intel Macs.
UNIVERSAL=0
[ "$1" = "--universal" ] && UNIVERSAL=1

echo "==> Compiling"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

compile() {  # <target-triple> <output>
    swiftc -O -whole-module-optimization -target "$1" Sources/*.swift -o "$2"
}

if [ "$UNIVERSAL" = "1" ]; then
    compile arm64-apple-macos14.0 build/FileExplorer-arm64
    compile x86_64-apple-macos14.0 build/FileExplorer-x86_64
    lipo -create -output "$APP/Contents/MacOS/FileExplorer" \
        build/FileExplorer-arm64 build/FileExplorer-x86_64
    rm -f build/FileExplorer-arm64 build/FileExplorer-x86_64
    echo "    universal: $(lipo -archs "$APP/Contents/MacOS/FileExplorer")"
else
    compile arm64-apple-macos14.0 "$APP/Contents/MacOS/FileExplorer"
fi

echo "==> Building icon"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
swiftc -O Tools/MakeIcon.swift -o build/makeicon
# Each size is drawn at its own resolution rather than downscaled, so the small
# variants can use the simplified artwork.
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" \
            "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
    set -- $spec
    build/makeicon "$ICONSET/icon_$2.png" "$1" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
build/makeicon "$APP/Contents/Resources/AppIcon.png" 1024 >/dev/null
rm -f build/makeicon

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
