#!/usr/bin/env bash
# Captures the native app on its built-in simulated telemetry (host zyvor-dev-01) into docs/ux/native-*.png.
# Never capture the app on real telemetry for public images: it shows real process names (AGENTS.md).
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -d native/build/Vytrix.app ]] || ./scripts/build-native.sh
out="docs/ux"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"; pkill -x Vytrix 2>/dev/null || true' EXIT
xcrun swiftc -O scripts/windowid.swift -o "$tmp/windowid"
for mode in light dark; do
  for section in overview applications containers projects; do
    id=""
    for attempt in 1 2 3; do
      open -n native/build/Vytrix.app --args -ApplePersistenceIgnoreState YES --demo --appearance "$mode" --section "$section"
      for i in $(seq 1 40); do
        id="$("$tmp/windowid" Vytrix || true)"
        [[ -n "$id" ]] && break
        # A launch event from a script can leave the app without a window; a reopen event brings it up.
        [[ "$i" == 12 ]] && open native/build/Vytrix.app
        sleep 0.25
      done
      [[ -n "$id" ]] && break
      echo "retrying $mode/$section (attempt $attempt)" >&2
      pkill -x Vytrix || true
      while pgrep -x Vytrix >/dev/null; do sleep 0.2; done
    done
    [[ -n "$id" ]] || { echo "no window for $mode/$section" >&2; exit 1; }
    sleep 2
    screencapture -x -o -l "$id" "$out/native-$mode-$section.png"
    pkill -x Vytrix || true
    while pgrep -x Vytrix >/dev/null; do sleep 0.2; done
  done
done
echo "wrote 8 native screenshots to $out"
