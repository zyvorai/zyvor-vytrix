#!/usr/bin/env bash
# SPDX-License-Identifier: BUSL-1.1
# Unit tests for the native app's pure logic (alert rules and notification hysteresis), compiled
# with swiftc against the real model files. macOS only; no app launch, no Accessibility needed.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo "Run on macOS." >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library -o "$tmp/logic" \
  native/App/Model/Snapshot.swift native/App/Model/Alerts.swift native/Tests/AlertTests.swift
"$tmp/logic"
