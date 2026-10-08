#!/usr/bin/env bash
# Render the social images and icons from their HTML sources. Needs Google Chrome and macOS `sips`; installs nothing.
#   ./docs/social/build.sh
# Run `pnpm shots` first: the hero embeds docs/ux/*.png (simulated telemetry only).
# Outputs:
#   docs/social/vytrix-hero-dark.jpg    2400x1260  README hero, GitHub social preview
#   docs/social/vytrix-social-card.jpg  1600x900   LinkedIn / X card
#   public/og.jpg                       1200x630   og:image / twitter:image
#   public/apple-touch-icon.png         180x180
# GitHub's social preview is uploaded by hand: Settings > General > Social preview.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[[ -x "$CHROME" ]] || { echo "Google Chrome not found (set CHROME=...)" >&2; exit 1; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/vytrix-social.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

shoot() { # html scale w h out
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor="$2" \
    --window-size="$3,$4" --screenshot="$TMP/shot.png" "file://$1" >/dev/null 2>&1
  cp "$TMP/shot.png" "$5"
}
jpeg() { sips -s format jpeg -s formatOptions "${3:-90}" "$1" --out "$2" >/dev/null; }

shoot "$HERE/vytrix-hero-dark.html" 2 1200 630 "$TMP/hero.png"
jpeg "$TMP/hero.png" "$HERE/vytrix-hero-dark.jpg" 90
shoot "$HERE/vytrix-hero-dark.html" 1 1200 630 "$TMP/og.png"
jpeg "$TMP/og.png" "$ROOT/public/og.jpg" 85
shoot "$HERE/vytrix-social-card.html" 1 1600 900 "$TMP/card.png"
jpeg "$TMP/card.png" "$HERE/vytrix-social-card.jpg" 90

cat > "$TMP/icon.html" <<HTML
<body style="margin:0;background:#1d1d1f"><img src="file://$ROOT/public/favicon.svg" width="180" height="180" style="display:block"></body>
HTML
shoot "$TMP/icon.html" 1 180 180 "$ROOT/public/apple-touch-icon.png"
echo "wrote the hero, share card, public/og.jpg and public/apple-touch-icon.png"
