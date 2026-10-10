#!/usr/bin/env bash
# SPDX-License-Identifier: BUSL-1.1
# Copyright 2026 Zyvor AI Labs Private Limited
# Smoke test for the native app, driven like a person would: click each sidebar row and check the
# section changes, then close the window and check the app and its bundled collector both exit.
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

rows='rows of outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1'
names=(Overview Applications Containers Projects)
for i in 2 3 4 1; do
  name="${names[$((i - 1))]}"
  geometry="$(ax "get {position, size} of row $i of outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1" | tr -d ' ')"
  IFS=, read -r x y w h <<<"$geometry"
  "$tmp/uiclick" $((x + w / 2)) $((y + h / 2))
  for _ in $(seq 1 20); do [[ "$(title)" == "$name"* ]] && break; sleep 0.25; done
  if [[ "$(title)" == "$name"* ]]; then ok "sidebar click opens $name"; else fail "sidebar click on $name left the window on: $(title)"; fi
done
[[ "$(ax "count $rows")" == 4 ]] || fail "expected 4 sidebar rows"

ax 'click (first button of window 1 whose subrole is "AXCloseButton")' >/dev/null
if gone "$app/Contents/MacOS/Vytrix"; then ok "closing the window quits the app"; else fail "app still running after its window closed"; fi
if gone "$app/Contents/Resources/vytrix.py"; then ok "bundled collector exits with the app"; else fail "bundled collector still running"; fi

if ((failures)); then echo "$failures failure(s)"; exit 1; fi
echo "native UI smoke test passed"
