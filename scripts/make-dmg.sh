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
# Two ways to sign:
#
#   scripts/make-dmg.sh
#       Ad-hoc. For building on your own Mac. A *downloaded* copy shows macOS's
#       "unidentified developer" warning.
#
#   SIGN_IDENTITY="Developer ID Application" scripts/make-dmg.sh
#       For releases. Signs with your Developer ID certificate, sends the disk image to
#       Apple's notary service, staples the approval to it and checks the result.
#       Needs the certificate in your Keychain and, once, a saved notary profile:
#           xcrun notarytool store-credentials "cap-notary" --apple-id ... --team-id ...
#       Use NOTARY_PROFILE=name if you saved it under another name.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Cap.app/Contents/Info.plist)
VOL="Cap"
DIST="dist"
APP="$DIST/Cap.app"
STAGE="$DIST/stage"
RW="$DIST/Cap-rw.dmg"
FINAL="$DIST/Cap-$VERSION.dmg"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"                  # empty = ad-hoc
NOTARY_PROFILE="${NOTARY_PROFILE:-cap-notary}"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# Fail before the slow build if the release certificate is not there.
if [ -n "$SIGN_IDENTITY" ]; then
  security find-identity -v -p codesigning | grep -F -- "$SIGN_IDENTITY" >/dev/null \
    || { echo "ERROR: no signing identity matching \"$SIGN_IDENTITY\" in your Keychain"; exit 1; }
fi

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
if [ -n "$SIGN_IDENTITY" ]; then
  # Hardened runtime and a secure timestamp are both required for notarization.
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "signed OK ($(lipo -archs "$APP/Contents/MacOS/Cap"), ${SIGN_IDENTITY:-ad-hoc})"

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

if [ -n "$SIGN_IDENTITY" ]; then
  say "Signing the disk image"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$FINAL"

  say "Sending it to Apple's notary service (usually a few minutes)"
  LOG="$DIST/notary-$VERSION.log"
  xcrun notarytool submit "$FINAL" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | tee "$LOG" || true
  if ! grep -q "status: Accepted" "$LOG"; then
    ID=$(awk '$1=="id:"{print $2; exit}' "$LOG")
    echo "ERROR: Apple did not accept the disk image. Do not publish it."
    [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE"
    exit 1
  fi

  say "Stapling Apple's approval and checking it"
  xcrun stapler staple "$FINAL"
  xcrun stapler validate "$FINAL"
  spctl --assess --type open --context context:primary-signature -vv "$FINAL"
fi

# Last, because signing and stapling both change the file.
shasum -a 256 "$FINAL" | tee "$FINAL.sha256"

say "7/7  Done"
[ -n "$SIGN_IDENTITY" ] || echo "Ad-hoc build: not notarized."
ls -lh "$FINAL" | awk '{print $5, $9}'
