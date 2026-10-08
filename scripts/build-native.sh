#!/usr/bin/env bash
# Builds native/build/Vytrix.app: the SwiftUI monitor, with the collector bundled. Ad-hoc signed, for development.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo "Build on macOS." >&2; exit 1; }
app="native/build/Vytrix.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp native/Info.plist "$app/Contents/Info.plist"
cp native/Vytrix.icns "$app/Contents/Resources/Vytrix.icns"
cp agent/vytrix.py "$app/Contents/Resources/vytrix.py"
sources=()
while IFS= read -r f; do sources+=("$f"); done < <(find native/App -name '*.swift' | sort)
xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -O -parse-as-library \
  -framework SwiftUI -framework AppKit -framework Charts \
  "${sources[@]}" -o "$app/Contents/MacOS/Vytrix"
codesign --force --sign - "$app"
echo "Built $app (ad-hoc signed developer build)."
