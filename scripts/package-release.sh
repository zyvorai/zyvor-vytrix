#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Package release archives from a finished `pnpm build` into release/.
#
#   scripts/package-release.sh [VERSION]      (default: version from package.json)
#
#   zyvor-vytrix-dashboard-VERSION.tar.gz   dist/ (Worker + static assets)
#   zyvor-vytrix-collector-VERSION.tar.gz   agent/vytrix.py, cluster worker and coordinator, installers, docs
#   SHA256SUMS
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
VERSION="${1:-$(python3 -c 'import json; print(json.load(open("package.json"))["version"])')}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.]+)?$ ]] || { echo "invalid version: $VERSION" >&2; exit 2; }
[[ -f dist/server/wrangler.json ]] || { echo "dist/ missing; run pnpm build first" >&2; exit 1; }

OUT=release
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
rm -rf "$OUT" && mkdir -p "$OUT"
TAR=(tar --owner=0 --group=0 --numeric-owner)
tar --version 2>/dev/null | grep -q GNU || TAR=(tar --no-mac-metadata --no-xattrs)
export COPYFILE_DISABLE=1

dash="zyvor-vytrix-dashboard-$VERSION"
mkdir -p "$STAGE/$dash"
cp -R dist "$STAGE/$dash/"
cp LICENSE NOTICE THIRD_PARTY.md "$STAGE/$dash/"
cat > "$STAGE/$dash/README.txt" <<EOF
Zyvor Vytrix dashboard $VERSION — built Cloudflare Worker (dist/server) and static assets (dist/client).

Deploy to Cloudflare:   npx wrangler@4 deploy --config dist/server/wrangler.json
Serve locally:          npx wrangler@4 dev --config dist/server/wrangler.json --local --ip 127.0.0.1 --port 8787

Then point the collector at it with --ui-upstream http://127.0.0.1:8787, or connect from the dashboard.
https://github.com/zyvorai/zyvor-vytrix
EOF

col="zyvor-vytrix-collector-$VERSION"
mkdir -p "$STAGE/$col/agent" "$STAGE/$col/cluster" "$STAGE/$col/scripts" "$STAGE/$col/docs"
cp agent/vytrix.py agent/cluster_worker.py "$STAGE/$col/agent/"
cp cluster/coordinator.py "$STAGE/$col/cluster/"
cp scripts/install-macos.sh scripts/install-linux.sh "$STAGE/$col/scripts/"
cp docs/API.md docs/CLUSTER.md "$STAGE/$col/docs/"
cp LICENSE NOTICE README.md CHANGELOG.md "$STAGE/$col/"

for name in "$dash" "$col"; do
  "${TAR[@]}" -C "$STAGE" -czf "$OUT/$name.tar.gz" "$name"
done
if command -v sha256sum >/dev/null; then SUM=(sha256sum); else SUM=(shasum -a 256); fi
(cd "$OUT" && "${SUM[@]}" ./*.tar.gz | sed 's# \./# #' > SHA256SUMS)
ls -l "$OUT"
cat "$OUT/SHA256SUMS"
