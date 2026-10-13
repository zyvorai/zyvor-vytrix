#!/usr/bin/env bash
# SPDX-License-Identifier: BUSL-1.1
# Copyright 2026 Zyvor AI Labs Private Limited
# Smoke test for the native app, driven like a person would: click each sidebar row and check the
# section changes, close the window and check the app keeps running (menu bar), reopen it, then quit
# and check the app and its bundled collector both exit.
# macOS only. The terminal needs Accessibility access (System Settings > Privacy & Security >
# Accessibility) to post clicks. It takes no screenshots. Quits any running Vytrix first.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo "Run on macOS." >&2; exit 1; }
[[ -d native/build/Vytrix.app ]] || ./scripts/build-native.sh
app="$PWD/native/build/Vytrix.app"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"; pkill -x Vytrix 2>/dev/null || true' EXIT
xcrun swiftc -O scripts/uiclick.swift -o "$tmp/uiclick"

failures=0
ok() { echo "ok   $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
ax() { osascript -e 'with timeout of 10 seconds' -e "tell application \"System Events\" to tell process \"Vytrix\" to $1" -e 'end timeout'; }
title() { ax 'get name of window 1' 2>/dev/null || true; }
gone() { for _ in $(seq 1 40); do pgrep -f "$1" >/dev/null || return 0; sleep 0.25; done; return 1; }

pkill -x Vytrix 2>/dev/null || true
while pgrep -x Vytrix >/dev/null; do sleep 0.2; done
open -n "$app" --args -ApplePersistenceIgnoreState YES
for i in $(seq 1 60); do
  [[ "$(ax 'count windows' 2>/dev/null || echo 0)" -ge 1 ]] && break
  # A launch event from a script can leave the app without a window; a reopen event brings it up.
  [[ "$i" == 12 ]] && open "$app"
  sleep 0.25
done
[[ "$(ax 'count windows' 2>/dev/null || echo 0)" -ge 1 ]] || { echo "FAIL no window" >&2; exit 1; }
osascript -e 'tell application "System Events" to set frontmost of process "Vytrix" to true'
for _ in $(seq 1 60); do [[ "$(title)" == *·* ]] && break; sleep 0.25; done
if [[ "$(title)" == *·* ]]; then ok "live telemetry loaded"; else fail "no snapshot after 15 s: $(title)"; fi
if pgrep -f "$app/Contents/Resources/vytrix.py" >/dev/null; then ok "bundled collector running"; else fail "bundled collector not running"; fi

sidebar='outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1'
# Rows are found by their label, so section headers and new sections do not shift the indexes.
row_index() {
  osascript -e 'tell application "System Events" to tell process "Vytrix"' \
    -e "set o to $sidebar" \
    -e 'set i to 0' \
    -e 'repeat with r in rows of o' \
    -e 'set i to i + 1' \
    -e 'try' \
    -e 'repeat with t in static texts of UI element 1 of r' \
    -e "if (value of t) is \"$1\" then return i" \
    -e 'end repeat' \
    -e 'end try' \
    -e 'end repeat' \
    -e 'return 0' \
    -e 'end tell'
}
names=(Applications Containers Projects Alerts CPU Memory Disk Network Battery Overview)
for name in "${names[@]}"; do
  i="$(row_index "$name")"
  if [[ "$i" == 0 ]]; then fail "sidebar has no $name row"; continue; fi
  geometry="$(ax "get {position, size} of row $i of $sidebar" | tr -d ' ')"
  IFS=, read -r x y w h <<<"$geometry"
  "$tmp/uiclick" $((x + w / 2)) $((y + h / 2))
  for _ in $(seq 1 20); do [[ "$(title)" == "$name"* ]] && break; sleep 0.25; done
  if [[ "$(title)" == "$name"* ]]; then ok "sidebar click opens $name"; else fail "sidebar click on $name left the window on: $(title)"; fi
done
[[ "$(ax "count rows of $sidebar")" == 13 ]] || fail "expected 3 section headers and 10 sidebar rows"

ax 'click (first button of window 1 whose subrole is "AXCloseButton")' >/dev/null
sleep 1
if pgrep -f "$app/Contents/MacOS/Vytrix" >/dev/null && pgrep -f "$app/Contents/Resources/vytrix.py" >/dev/null; then
  ok "closing the window keeps the app and collector running"
else
  fail "app or collector exited when its window closed"
fi
open "$app"
for _ in $(seq 1 40); do [[ "$(ax 'count windows' 2>/dev/null || echo 0)" -ge 1 ]] && break; sleep 0.25; done
if [[ "$(ax 'count windows' 2>/dev/null || echo 0)" -ge 1 ]]; then ok "reopening brings the window back"; else fail "no window after reopen"; fi

osascript -e 'tell application "Vytrix" to quit'
if gone "$app/Contents/MacOS/Vytrix"; then ok "quit stops the app"; else fail "app still running after quit"; fi
if gone "$app/Contents/Resources/vytrix.py"; then ok "bundled collector exits with the app"; else fail "bundled collector still running"; fi

if ((failures)); then echo "$failures failure(s)"; exit 1; fi
echo "native UI smoke test passed"
