#!/bin/bash
# Builds a drag-to-Applications installer: dist/Cap-<version>.dmg
#
# Run from anywhere:  scripts/make-dmg.sh
#
# What it does: builds Cap, assembles + signs dist/Cap.app, lays out the installer window
# (background art, Cap icon, Applications shortcut), and compresses it into a .dmg.
# The window layout step drives Finder through AppleScript, so macOS may ask you once to
# let your terminal / Claude control Finder: click Allow.
#
# Signing is ad-hoc (no Apple Developer ID yet), so a *downloaded* copy shows macOS's
# "unidentified developer" warning. A copy made and opened on this Mac does not.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Cap.app/Contents/Info.plist)
VOL="Cap"
DIST="dist"
APP="$DIST/Cap.app"
STAGE="$DIST/stage"
RW="$DIST/Cap-rw.dmg"
FINAL="$DIST/Cap-$VERSION.dmg"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

say "1/7  Building the release binary"
swift build -c release 2>&1 | tail -2

say "2/7  Assembling and signing Cap.app"
mkdir -p "$DIST"
rm -rf "$APP"
ditto --norsrc --noextattr Cap.app "$APP"          # start from the bundle skeleton (Info.plist, icon)
rm -rf "$APP/Contents/_CodeSignature"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Cap "$APP/Contents/MacOS/Cap"    # a fresh binary, never the one that has been running
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "signed OK ($(lipo -archs "$APP/Contents/MacOS/Cap"))"

say "3/7  Drawing the installer background"
swift scripts/make-dmg-background.swift "$DIST/dmg-background.png"

say "4/7  Staging the disk contents"
rm -rf "$STAGE"
mkdir -p "$STAGE/.background"
ditto --norsrc --noextattr "$APP" "$STAGE/Cap.app"
ln -s /Applications "$STAGE/Applications"
cp "$DIST/dmg-background.png" "$STAGE/.background/background.png"
touch "$STAGE/.CapInstaller"                        # lets the app recognise its own installer disk
cp Cap.app/Contents/Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"

say "5/7  Creating and laying out the disk image"
hdiutil detach "/Volumes/$VOL" >/dev/null 2>&1 || true
rm -f "$RW"
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}')
echo "mounted at: $MOUNT"
"$(xcrun --find SetFile)" -a C "$MOUNT"             # use the custom volume icon

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 542}
    set theOptions to the icon view options of container window
    set arrangement of theOptions to not arranged
    set icon size of theOptions to 128
    set text size of theOptions to 13
    set background picture of theOptions to file ".background:background.png"
    set position of item "Cap.app" of container window to {165, 190}
    set position of item "Applications" of container window to {495, 190}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

sync; sleep 3; sync                                  # give Finder time to write the window layout (.DS_Store)
[ -f "$MOUNT/.DS_Store" ] || { echo "ERROR: the window layout was not saved"; hdiutil detach "$MOUNT" >/dev/null || true; exit 1; }
hdiutil detach "$MOUNT" >/dev/null

say "6/7  Compressing to $FINAL"
rm -f "$FINAL"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$FINAL" >/dev/null
rm -f "$RW"
shasum -a 256 "$FINAL" | tee "$FINAL.sha256"

say "7/7  Done"
ls -lh "$FINAL" | awk '{print $5, $9}'
