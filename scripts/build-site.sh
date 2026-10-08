#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Assemble the Pages site into _site/:
#   /        site/ (landing) + shared images from docs/social and docs/ux
#   /demo/   the REAL dashboard on its simulated telemetry, as static files
# The demo is the app's own production build (VYTRIX_BASE_PATH makes every asset URL start with the sub-path),
# with its server-rendered HTML captured from the built worker. The page is a client component on built-in
# demo data and makes no server calls in that mode, so it hydrates from static hosting.
# Same command locally: ./scripts/build-site.sh && node scripts/site-check.mjs      (leaves dist/ built with the base path:
# run `pnpm build` again before `pnpm start`)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/_site}"
BASE="${VYTRIX_SITE_BASE:-/zyvor-vytrix}"
PNPM=(pnpm)
command -v pnpm >/dev/null 2>&1 || PNPM=(npx -y pnpm@11.25.0)
TMP="$(mktemp -d "${TMPDIR:-/tmp}/vytrix-site.XXXXXX")"
WORKER_PID=""
# shellcheck disable=SC2329 # invoked through the EXIT trap below
cleanup() {
  if [[ -n "$WORKER_PID" ]]; then kill "$WORKER_PID" 2>/dev/null || true; fi
  rm -rf "$TMP"
}
trap cleanup EXIT

rm -rf "$OUT" && mkdir -p "$OUT/social" "$OUT/ux" "$OUT/demo"
cp -R "$ROOT"/site/. "$OUT/"
cp "$ROOT/public/favicon.svg" "$ROOT/public/apple-touch-icon.png" "$OUT/"
cp "$ROOT"/docs/social/*.jpg "$OUT/social/"
cp "$ROOT"/docs/ux/*.png "$ROOT"/docs/ux/*.jpg "$ROOT"/docs/ux/*.gif "$OUT/ux/"
touch "$OUT/.nojekyll"

echo "building the dashboard with base path $BASE/demo"
(cd "$ROOT" && VYTRIX_BASE_PATH="$BASE/demo" "${PNPM[@]}" build >"$TMP/build.log" 2>&1) || { tail -20 "$TMP/build.log" >&2; exit 1; }

PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
(cd "$ROOT" && CI=1 node --import ./scripts/runtime-env.mjs ./node_modules/wrangler/bin/wrangler.js dev \
  --config dist/server/wrangler.json --local --persist-to "$TMP/state" --ip 127.0.0.1 --port "$PORT" --inspector-port 0 \
  >"$TMP/worker.log" 2>&1) &
WORKER_PID=$!
URL="http://127.0.0.1:$PORT$BASE/demo/"
for _ in $(seq 1 120); do
  [[ "$(curl -s -o /dev/null -w '%{http_code}' "$URL" || true)" == 200 ]] && break
  sleep 0.5
done
curl -fsS "$URL" -o "$OUT/demo/index.html" || { tail -20 "$TMP/worker.log" >&2; exit 1; }
kill "$WORKER_PID"; WORKER_PID=""

# The demo page must not compete with the landing page in search results.
sed -i.bak 's#</head>#<meta name="robots" content="noindex"/></head>#' "$OUT/demo/index.html" && rm -f "$OUT/demo/index.html.bak"
cp -R "$ROOT/dist/client$BASE/demo/." "$OUT/demo/"
cp "$ROOT/public/favicon.svg" "$ROOT/public/apple-touch-icon.png" "$OUT/demo/"

# Every local reference must exist: in the landing page, and in the demo page (where URLs carry the base path).
status=0
refs() { grep -oE '(src|href)="[^"]+"' "$1" | sed -E 's/^(src|href)="//; s/"$//'; }
while IFS= read -r ref; do
  case "$ref" in http*|mailto:*|\#*|"") continue ;; esac
  [[ -e "$OUT/${ref%%[?#]*}" || "${ref%%[?#]*}" == "./" ]] || { echo "broken reference in site/index.html: $ref" >&2; status=1; }
done < <(refs "$ROOT/site/index.html")
while IFS= read -r ref; do
  case "$ref" in http*|mailto:*|\#*|"") continue ;; esac
  if [[ "$ref" == "$BASE/"* ]]; then target="$OUT/${ref#"$BASE"/}"; else echo "demo reference outside $BASE: $ref" >&2; status=1; continue; fi
  [[ -e "${target%%[?#]*}" || "${target%%[?#]*}" == "$OUT/demo/" ]] || { echo "broken reference in demo/index.html: $ref" >&2; status=1; }
done < <(refs "$OUT/demo/index.html")
[[ $status -eq 0 ]] && echo "site built in $OUT"
exit $status
