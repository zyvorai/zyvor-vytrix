#!/usr/bin/env bash
# SPDX-License-Identifier: BUSL-1.1
# Install the Vytrix collector as a systemd service on Linux.
#
#   scripts/install-linux.sh [--system] [--allow-origin URL]... [--port N] [--no-containers] [--dry-run]
#   scripts/install-linux.sh --uninstall [--system] [--dry-run]
#
# Default is a user service (~/.config/systemd/user), which can see your own
# rootless Podman containers and Docker if you are in the docker group.
# --system installs a hardened system service with a dynamic user (needs root).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/agent/vytrix.py"
DRY_RUN=0 UNINSTALL=0 SYSTEM=0 PORT=9847 CONTAINERS=1
ORIGINS=()

usage() { sed -n '3,11p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --system) SYSTEM=1; shift ;;
    --allow-origin) ORIGINS+=("${2:?--allow-origin needs a value}"); shift 2 ;;
    --port) PORT="${2:?--port needs a value}"; shift 2 ;;
    --no-containers) CONTAINERS=0; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 2 ;;
  esac
done

run() { if [[ $DRY_RUN == 1 ]]; then printf '[dry-run]'; printf ' %q' "$@"; echo; else "$@"; fi; }
write_file() { # path mode <<content
  local path="$1" mode="$2" content; content="$(cat)"
  if [[ $DRY_RUN == 1 ]]; then echo "[dry-run] write $path (mode $mode)"; printf '%s\n' "$content" | sed 's/^/    /'; return; fi
  (umask 077; printf '%s\n' "$content" > "$path"); chmod "$mode" "$path"
}

if [[ "$(uname -s)" != "Linux" && $DRY_RUN == 0 ]]; then
  echo "This installer is for Linux. On macOS use scripts/install-macos.sh." >&2; exit 1
fi

if [[ $SYSTEM == 1 ]]; then
  [[ $DRY_RUN == 1 || $EUID -eq 0 ]] || { echo "--system needs root (try sudo)." >&2; exit 1; }
  APP_DIR=/opt/vytrix CONF_DIR=/etc/vytrix UNIT_DIR=/etc/systemd/system
  DB=/var/lib/vytrix/history.sqlite
  SYSTEMCTL=(systemctl)
else
  APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/vytrix"
  CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/vytrix"
  UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  DB="$APP_DIR/history.sqlite"
  SYSTEMCTL=(systemctl --user)
fi
UNIT="$UNIT_DIR/vytrix.service"
ENV_FILE="$CONF_DIR/env"

if [[ $UNINSTALL == 1 ]]; then
  run "${SYSTEMCTL[@]}" disable --now vytrix.service 2>/dev/null || true
  run rm -f "$UNIT" "$APP_DIR/vytrix.py" "$ENV_FILE"
  run "${SYSTEMCTL[@]}" daemon-reload
  echo "Vytrix service removed. History kept in: $DB (delete it manually if unwanted)."
  exit 0
fi

PYTHON="$(command -v python3 || true)"
if [[ -z "$PYTHON" ]] || ! "$PYTHON" -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
  echo "Python 3.10+ is required (apt install python3 / dnf install python3)." >&2; exit 1
fi

[[ ${#ORIGINS[@]} -gt 0 ]] || ORIGINS=("http://localhost:5173")
for origin in "${ORIGINS[@]}"; do
  [[ "$origin" =~ ^https?://[^/]+$ ]] || { echo "Invalid origin '$origin': use an exact origin such as https://dash.example.com" >&2; exit 2; }
done
[[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1 && "$PORT" -le 65535 ]] || { echo "Invalid port: $PORT" >&2; exit 2; }

ARGS="--port $PORT --database \"$DB\""
for origin in "${ORIGINS[@]}"; do ARGS+=" --allow-origin $origin"; done
# A system service would need the docker group or root to read container stats; keep it least-privileged.
[[ $CONTAINERS == 1 && $SYSTEM == 0 ]] || ARGS+=" --no-containers"

run mkdir -p "$APP_DIR" "$CONF_DIR" "$UNIT_DIR"
run chmod 700 "$CONF_DIR"
run install -m 0755 "$SRC" "$APP_DIR/vytrix.py"

if [[ $DRY_RUN == 1 ]]; then
  echo "[dry-run] generate token into $ENV_FILE (mode 0600)"
elif [[ ! -s "$ENV_FILE" ]]; then
  TOKEN="$("$PYTHON" -c 'import secrets; print(secrets.token_urlsafe(32))')"
  write_file "$ENV_FILE" 0600 <<<"VYTRIX_TOKEN=$TOKEN"
  NEW_TOKEN=1
fi

if [[ $SYSTEM == 1 ]]; then
write_file "$UNIT" 0644 <<EOF
[Unit]
Description=Zyvor Vytrix read-only telemetry collector
Documentation=file://$APP_DIR
After=network.target

[Service]
Type=simple
EnvironmentFile=$ENV_FILE
ExecStart="$PYTHON" "$APP_DIR/vytrix.py" $ARGS
Restart=on-failure
RestartSec=5
DynamicUser=yes
StateDirectory=vytrix
StateDirectoryMode=0700
UMask=0077
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
SystemCallArchitectures=native
SystemCallFilter=@system-service
CapabilityBoundingSet=
# Listening-port and project attribution for other users' processes needs
# /proc/<pid>/fd access. Uncomment to grant it (broad read access to /proc):
#AmbientCapabilities=CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
#CapabilityBoundingSet=CAP_SYS_PTRACE CAP_DAC_READ_SEARCH

[Install]
WantedBy=multi-user.target
EOF
else
write_file "$UNIT" 0644 <<EOF
[Unit]
Description=Zyvor Vytrix read-only telemetry collector
After=default.target

[Service]
Type=simple
EnvironmentFile=$ENV_FILE
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart="$PYTHON" "$APP_DIR/vytrix.py" $ARGS
Restart=on-failure
RestartSec=5
UMask=0077
# No NoNewPrivileges: rootless Podman needs the setuid newuidmap helper.

[Install]
WantedBy=default.target
EOF
fi

run "${SYSTEMCTL[@]}" daemon-reload
run "${SYSTEMCTL[@]}" enable --now vytrix.service

if [[ $DRY_RUN == 1 ]]; then echo; echo "Dry run complete: nothing was changed."; exit 0; fi
echo
echo "Vytrix collector installed as $([[ $SYSTEM == 1 ]] && echo 'system' || echo 'user') service 'vytrix.service'."
echo "  Endpoint : http://127.0.0.1:$PORT/v1/snapshot (loopback only)"
echo "  Origins  : ${ORIGINS[*]}"
echo "  Status   : ${SYSTEMCTL[*]} status vytrix   ·   journalctl $([[ $SYSTEM == 1 ]] || echo '--user ')-u vytrix -f"
[[ $SYSTEM == 1 ]] || echo "  Tip      : run 'loginctl enable-linger $USER' to keep it running while logged out."
if [[ ${NEW_TOKEN:-0} == 1 ]]; then echo "  Token    : $TOKEN  (stored in $ENV_FILE)"; else echo "  Token    : see $ENV_FILE"; fi
