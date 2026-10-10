#!/usr/bin/env bash
# SPDX-License-Identifier: BUSL-1.1
# Copyright 2026 Zyvor AI Labs Private Limited
# Package the native Mac app into release/:
#
#   scripts/package-mac.sh VERSION      (must match CFBundleShortVersionString in native/Info.plist)
#
#   Vytrix-VERSION.dmg (+ .sha256)   drag-to-Applications disk image
#   Vytrix-VERSION.pkg (+ .sha256)   installer into /Applications (Apple silicon, macOS 26+)
#
# Signed and notarized only when these are set; otherwise the app is ad-hoc signed, the pkg is
# unsigned, and Gatekeeper will block the first launch on other Macs. The script says which.
#   DEVELOPER_ID_APP        "Developer ID Application: NAME (TEAMID)"   signs the app and the DMG
#   DEVELOPER_ID_INSTALLER  "Developer ID Installer: NAME (TEAMID)"     signs the pkg
#   NOTARY_PROFILE          keychain profile from `xcrun notarytool store-credentials`
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ "$(uname -s)" == Darwin ]] || { echo "Run on macOS." >&2; exit 1; }
VERSION="${1:?usage: scripts/package-mac.sh VERSION}"
PLIST_VERSION="$(plutil -extract CFBundleShortVersionString raw native/Info.plist)"
[[ "$VERSION" == "$PLIST_VERSION" ]] || { echo "native/Info.plist is $PLIST_VERSION, not $VERSION" >&2; exit 2; }

APP_ID="${DEVELOPER_ID_APP:-}"
PKG_ID="${DEVELOPER_ID_INSTALLER:-}"
NOTARY="${NOTARY_PROFILE:-}"
OUT=release
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"
DMG="$OUT/Vytrix-$VERSION.dmg"
PKG="$OUT/Vytrix-$VERSION.pkg"
rm -f "$DMG" "$DMG.sha256" "$PKG" "$PKG.sha256"

./scripts/build-native.sh
APP=native/build/Vytrix.app
if [[ -n "$APP_ID" ]]; then
  codesign --force --options runtime --timestamp --sign "$APP_ID" "$APP"
fi
codesign --verify --deep --strict "$APP"

mkdir -p "$WORK/dmg"
ditto "$APP" "$WORK/dmg/Vytrix.app"
ln -s /Applications "$WORK/dmg/Applications"
hdiutil create -volname "Vytrix $VERSION" -srcfolder "$WORK/dmg" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
if [[ -n "$APP_ID" ]]; then
  codesign --force --timestamp --sign "$APP_ID" "$DMG"
fi

mkdir -p "$WORK/root/Applications" "$WORK/pkgs"
ditto "$APP" "$WORK/root/Applications/Vytrix.app"
pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist" >/dev/null
# Without this, Installer "relocates" the update into any other Vytrix.app it finds (e.g. a dev build).
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/component.plist"
pkgbuild --root "$WORK/root" --component-plist "$WORK/component.plist" --identifier dev.zyvor.vytrix.pkg \
  --version "$VERSION" --install-location / "$WORK/pkgs/Vytrix.pkg" >/dev/null
cat > "$WORK/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>Vytrix $VERSION</title>
    <allowed-os-versions><os-version min="26.0"/></allowed-os-versions>
    <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
    <choices-outline><line choice="default"><line choice="dev.zyvor.vytrix.pkg"/></line></choices-outline>
    <choice id="default"/>
    <choice id="dev.zyvor.vytrix.pkg" visible="false"><pkg-ref id="dev.zyvor.vytrix.pkg"/></choice>
    <pkg-ref id="dev.zyvor.vytrix.pkg" version="$VERSION" onConclusion="none">Vytrix.pkg</pkg-ref>
</installer-gui-script>
XML
sign_pkg=()
[[ -n "$PKG_ID" ]] && sign_pkg=(--sign "$PKG_ID" --timestamp)
productbuild --distribution "$WORK/distribution.xml" --package-path "$WORK/pkgs" "${sign_pkg[@]}" "$PKG" >/dev/null

notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY" --wait
  xcrun stapler staple "$1"
}
status="ad-hoc signed app, unsigned DMG and pkg, not notarized: Gatekeeper blocks the first launch on other Macs"
if [[ -n "$APP_ID" ]]; then
  status="Developer ID signed, not notarized (set NOTARY_PROFILE)"
  if [[ -n "$NOTARY" ]]; then
    notarize "$DMG"
    spctl -a -t open --context context:primary-signature -vv "$DMG"
    status="DMG signed and notarized"
    if [[ -n "$PKG_ID" ]]; then
      notarize "$PKG"
      spctl -a -t install -vv "$PKG"
      status="DMG and pkg signed and notarized"
    else
      status="$status; pkg unsigned (set DEVELOPER_ID_INSTALLER)"
    fi
  fi
fi

(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" && shasum -a 256 "$(basename "$PKG")" > "$(basename "$PKG").sha256")
echo "wrote $DMG and $PKG ($status)"
