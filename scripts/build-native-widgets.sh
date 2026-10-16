#!/usr/bin/env bash
# SPDX-License-Identifier: BUSL-1.1
# Builds the native app with the WidgetKit extension and App Intents, through an Xcode project that
# xcodegen generates from native/project.yml. Output: native/build/Vytrix.app, ad-hoc signed.
# The extension takes its version from the app's Info.plist, so a release bump touches one file.
#
# scripts/build-native.sh builds the same app without widgets and needs no Xcode project or xcodegen.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo "Build on macOS." >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "xcodegen is required (brew install xcodegen)." >&2; exit 1; }
marketing="$(plutil -extract CFBundleShortVersionString raw native/Info.plist)"
build="$(plutil -extract CFBundleVersion raw native/Info.plist)"
out="native/build"
rm -rf "$out/Vytrix.xcodeproj" "$out/dd" "$out/Vytrix.app"
mkdir -p "$out"
xcodegen generate --spec native/project.yml --project "$out" --quiet
xcodebuild -project "$out/Vytrix.xcodeproj" -scheme Vytrix -configuration Release -derivedDataPath "$out/dd" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO MARKETING_VERSION="$marketing" CURRENT_PROJECT_VERSION="$build" build -quiet
ditto "$out/dd/Build/Products/Release/Vytrix.app" "$out/Vytrix.app"
rm -rf "$out/dd"
codesign --verify --deep --strict "$out/Vytrix.app"
[[ -d "$out/Vytrix.app/Contents/PlugIns/VytrixWidgets.appex" ]] || { echo "The widget extension was not embedded." >&2; exit 1; }
[[ -d "$out/Vytrix.app/Contents/Resources/Metadata.appintents" ]] || { echo "App Intents metadata is missing." >&2; exit 1; }
echo "Built $out/Vytrix.app with widgets and App Intents (ad-hoc signed developer build)."
