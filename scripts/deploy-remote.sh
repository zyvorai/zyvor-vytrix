#!/usr/bin/env bash
# SPDX-License-Identifier: BUSL-1.1
# Vytrix — remote deploy to a Linux host (SSH + rsync + systemd, no containers)
#
# Usage:
#   ./scripts/deploy-remote.sh HOST USER          e.g. 203.0.113.10 deploy
#   ./scripts/deploy-remote.sh user@host
#
# Flags:
#   --quick         Sync and restart only (skip Node/pnpm install and build)
#   --verify-only   Show service status and health; change nothing
#   --dry-run       Print what would run; no SSH
#
# On the host:
#   ~/.vytrix/app                 checkout (VYTRIX_REMOTE_SUBDIR overrides, relative to $HOME)
#   ~/.vytrix/node                private Node 22 when the system Node is older than 22.13
#   ~/.vytrix/env                 VYTRIX_TOKEN (0600, kept across deploys; VYTRIX_TOKEN overrides)
#   ~/.vytrix/tls.{crt,key}       self-signed certificate with the host as subjectAltName
#   vytrix-dashboard.service      dashboard (wrangler/workerd) on 127.0.0.1:8787
#   vytrix-collector.service      collector + dashboard proxy on https://HOST:30847
#
# VYTRIX_PORT changes the public HTTPS port (default 30847).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROFILE="full"
DRY_RUN=false
VERIFY_ONLY=false
POSITIONAL=()
# One multiplexed connection per run: every step otherwise pays a fresh handshake, which hurts on busy or slow hosts.
# ControlPath stays under /tmp because unix socket paths are limited to ~104 bytes.
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30
  -o ControlMaster=auto -o "ControlPath=/tmp/vytrix-ssh-%C" -o ControlPersist=120)

usage() {
  sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage ;;
    --quick) PROFILE="quick"; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --verify-only) VERIFY_ONLY=true; shift ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

TARGET=""
if [[ ${#POSITIONAL[@]} -eq 1 && "${POSITIONAL[0]}" == *@* ]]; then
  TARGET="${POSITIONAL[0]}"
elif [[ ${#POSITIONAL[@]} -eq 2 ]]; then
  if [[ "${POSITIONAL[0]}" == *@* ]]; then TARGET="${POSITIONAL[0]}"
  elif [[ "${POSITIONAL[1]}" == *@* ]]; then TARGET="${POSITIONAL[1]}"
  else TARGET="${POSITIONAL[1]}@${POSITIONAL[0]}"
  fi
fi
if [[ -z "$TARGET" ]]; then
  echo "usage: $0 HOST USER   or   $0 user@host   [--quick|--verify-only|--dry-run]" >&2
  exit 2
fi

PUBLIC_HOST="${TARGET#*@}"
PORT="${VYTRIX_PORT:-30847}"
# Not ~/.deployments: other projects there rsync --delete into the shared parent and can wipe a sibling mid-run.
SUBDIR="${VYTRIX_REMOTE_SUBDIR:-.vytrix/app}"
if [[ ! "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1024 || PORT > 65535 )); then
  echo "VYTRIX_PORT must be 1024–65535" >&2; exit 2
fi
if [[ ! "$PUBLIC_HOST" =~ ^[A-Za-z0-9.:-]+$ || ! "$SUBDIR" =~ ^[A-Za-z0-9._/-]+$ || "$SUBDIR" == /* || "$SUBDIR" == *..* ]]; then
  echo "invalid host or VYTRIX_REMOTE_SUBDIR" >&2; exit 2
fi
if [[ -n "${VYTRIX_TOKEN:-}" && ( ${#VYTRIX_TOKEN} -lt 24 || ! "$VYTRIX_TOKEN" =~ ^[A-Za-z0-9_-]+$ ) ]]; then
  echo "VYTRIX_TOKEN must be at least 24 URL-safe characters" >&2; exit 2
fi

log() { printf '[vytrix-deploy] %s\n' "$*"; }
cleanup() {
  if [[ -n "${TARGET:-}" ]]; then
    ssh "${SSH_OPTS[@]}" -O exit "$TARGET" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
# shellcheck disable=SC2029 # remote commands are built from validated values on purpose
ssh_host() { ssh "${SSH_OPTS[@]}" "$TARGET" "$@"; }

# Values are validated above, so they are safe to splice into the remote environment.
remote_env="PROFILE=$PROFILE PUBLIC_HOST=$PUBLIC_HOST PORT=$PORT SUBDIR=$SUBDIR TOKEN_OVERRIDE=${VYTRIX_TOKEN:-}"

verify_script=$(cat <<'EOF'
set -euo pipefail
systemctl --no-pager --lines=5 status vytrix-dashboard vytrix-collector || true
curl -skf "https://127.0.0.1:${PORT}/healthz" && echo
code="$(curl -sk -o /dev/null -w '%{http_code}' "https://127.0.0.1:${PORT}/")"
echo "dashboard via collector: HTTP ${code}"
[[ "$code" == 200 ]]
EOF
)

remote_script=$(cat <<'EOF'
set -euo pipefail
DIR="$HOME/$SUBDIR"
STATE="$HOME/.vytrix"
mkdir -p "$STATE" && chmod 700 "$STATE"
cd "$DIR"
say() { printf '[vytrix-remote] %s\n' "$*"; }

node_ok() {
  "$1" -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>22||(a===22&&b>=13)?0:1)' 2>/dev/null
}
NODE="$(command -v node || true)"
if [[ -z "$NODE" ]] || ! node_ok "$NODE"; then
  NODE="$STATE/node/bin/node"
  if [[ ! -x "$NODE" ]] || ! node_ok "$NODE"; then
    case "$(uname -m)" in
      x86_64) arch=x64 ;;
      aarch64|arm64) arch=arm64 ;;
      *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
    esac
    base="https://nodejs.org/dist/latest-v22.x"
    sums="$(curl -fsSL "$base/SHASUMS256.txt")"
    file="$(awk -v a="linux-$arch.tar.xz" '$2 ~ a"$" {print $2; exit}' <<<"$sums")"
    [[ -n "$file" ]] || { echo "no Node 22 build for linux-$arch" >&2; exit 1; }
    say "installing $file into $STATE/node (system Node is older than 22.13)"
    tmp="$(mktemp -d)"
    curl -fsSL "$base/$file" -o "$tmp/$file"
    (cd "$tmp" && grep " $file\$" <<<"$sums" | sha256sum -c --quiet -)
    rm -rf "$STATE/node" && mkdir -p "$STATE/node"
    tar -xJf "$tmp/$file" -C "$STATE/node" --strip-components=1
    rm -rf "$tmp"
  fi
fi
export PATH="$(dirname "$NODE"):$PATH"
say "node $("$NODE" --version) at $NODE"

if [[ "$PROFILE" == full ]]; then
  say "installing dependencies and building"
  npx -y pnpm@11.25.0 install --frozen-lockfile
  npx -y pnpm@11.25.0 build
fi
[[ -f dist/server/wrangler.json ]] || { echo "dist/server/wrangler.json missing; run without --quick" >&2; exit 1; }

if [[ -n "$TOKEN_OVERRIDE" ]]; then
  TOKEN="$TOKEN_OVERRIDE"
elif [[ -f "$STATE/env" ]] && grep -q '^VYTRIX_TOKEN=' "$STATE/env"; then
  TOKEN="$(sed -n 's/^VYTRIX_TOKEN=//p' "$STATE/env")"
else
  TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
fi
umask 077
printf '# Written by deploy-remote.sh\nVYTRIX_TOKEN=%s\nVYTRIX_URL=https://%s:%s\n' "$TOKEN" "$PUBLIC_HOST" "$PORT" > "$STATE/env"
umask 022

if [[ "$PUBLIC_HOST" =~ ^[0-9.]+$ || "$PUBLIC_HOST" == *:* ]]; then
  san="IP:$PUBLIC_HOST" want="IP Address:$PUBLIC_HOST"
else
  san="DNS:$PUBLIC_HOST" want="DNS:$PUBLIC_HOST"
fi
san="$san,DNS:localhost,IP:127.0.0.1"
for ip in $(hostname -I); do [[ "$ip" == "$PUBLIC_HOST" ]] || san="$san,IP:$ip"; done
if [[ ! -f "$STATE/tls.crt" ]] || ! openssl x509 -in "$STATE/tls.crt" -noout -ext subjectAltName 2>/dev/null | grep -qF "$want"; then
  say "creating self-signed certificate for ${san%%,*}"
  openssl req -x509 -nodes -days 3650 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "$STATE/tls.key" -out "$STATE/tls.crt" -subj "/CN=vytrix/O=Zyvor AI Labs" \
    -addext "subjectAltName=$san" 2>/dev/null
  chmod 600 "$STATE/tls.key" "$STATE/tls.crt"
fi

USER_NAME="$(id -un)"
sudo tee /etc/systemd/system/vytrix-dashboard.service >/dev/null <<UNIT
[Unit]
Description=Vytrix dashboard (workerd, loopback only)
After=network-online.target
Wants=network-online.target

[Service]
User=$USER_NAME
WorkingDirectory=$DIR
Environment=PATH=$(dirname "$NODE"):/usr/local/bin:/usr/bin:/bin
Environment=CI=1
ExecStart=$NODE --import ./scripts/runtime-env.mjs ./node_modules/wrangler/bin/wrangler.js dev --config dist/server/wrangler.json --local --persist-to .wrangler/state --ip 127.0.0.1 --port 8787 --inspector-port 0
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

sudo tee /etc/systemd/system/vytrix-collector.service >/dev/null <<UNIT
[Unit]
Description=Vytrix read-only collector (HTTPS :$PORT, proxies the dashboard)
After=network-online.target vytrix-dashboard.service
Wants=network-online.target vytrix-dashboard.service

[Service]
User=$USER_NAME
WorkingDirectory=$DIR
EnvironmentFile=$STATE/env
ExecStart=/usr/bin/python3 $DIR/agent/vytrix.py --bind 0.0.0.0 --port $PORT --tls-cert $STATE/tls.crt --tls-key $STATE/tls.key --ui-upstream http://127.0.0.1:8787 --allow-origin https://$PUBLIC_HOST:$PORT
Restart=on-failure
RestartSec=3
# No NoNewPrivileges: rootless Podman needs the setuid newuidmap helper.
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
UNIT

if command -v ufw >/dev/null && sudo ufw status 2>/dev/null | grep -q '^Status: active'; then
  sudo ufw allow "$PORT/tcp" >/dev/null
fi

sudo systemctl daemon-reload
sudo systemctl enable vytrix-dashboard vytrix-collector >/dev/null 2>&1
sudo systemctl restart vytrix-dashboard vytrix-collector

say "waiting for services"
for _ in $(seq 1 90); do
  code="$(curl -sk -o /dev/null -w '%{http_code}' "https://127.0.0.1:$PORT/" || true)"
  [[ "$code" == 200 ]] && break
  sleep 1
done
if [[ "$code" != 200 ]]; then
  echo "dashboard did not become ready (last HTTP $code)" >&2
  sudo journalctl -u vytrix-dashboard -u vytrix-collector -n 40 --no-pager >&2
  exit 1
fi
curl -skf "https://127.0.0.1:$PORT/healthz" >/dev/null
curl -skf -H "Authorization: Bearer $TOKEN" "https://127.0.0.1:$PORT/v1/snapshot" \
  | python3 -c 'import json,sys; s=json.load(sys.stdin); h=s["host"]; print("[vytrix-remote] snapshot ok:", h["name"], "("+h["os"]+"),", len(s["processes"]), "processes")'
echo "VYTRIX_URL=https://$PUBLIC_HOST:$PORT"
echo "VYTRIX_TOKEN=$TOKEN"
EOF
)

if $VERIFY_ONLY; then
  if $DRY_RUN; then log "dry-run verify on ${TARGET}:"; echo "$verify_script"; exit 0; fi
  ssh_host "PORT=$PORT bash -s" <<<"$verify_script"
  exit 0
fi

log "sync → ${TARGET}:~/${SUBDIR} (profile: ${PROFILE})"
if $DRY_RUN; then
  log "dry-run: rsync -az --delete ${ROOT}/ ${TARGET}:${SUBDIR}/"
  log "dry-run remote script (env: ${remote_env/TOKEN_OVERRIDE=*/TOKEN_OVERRIDE=…}):"
  echo "$remote_script"
  exit 0
fi

ssh_host "mkdir -p '$SUBDIR'"
rsync -az --delete -e "ssh ${SSH_OPTS[*]}" \
  --exclude '.git' --exclude 'node_modules' --exclude 'dist' --exclude '.wrangler' \
  --exclude '.vinext' --exclude '.next' --exclude 'test-results' \
  --exclude 'playwright-report' --exclude '.cursor' --exclude '.DS_Store' \
  --exclude '__pycache__' --exclude 'tsconfig.tsbuildinfo' --exclude 'lib/.*-test.mjs' \
  "${ROOT}/" "${TARGET}:${SUBDIR}/"

ssh_host "$remote_env bash -s" <<<"$remote_script"
log "done — open https://${PUBLIC_HOST}:${PORT} (self-signed certificate) and connect with the token above"
