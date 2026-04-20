#!/usr/bin/env bash
# Start (or restart) the ComfyUI systemd service and show its status.

set -euo pipefail

log()  { printf '\033[1;36m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR]\033[0m   %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    err "This step must run as root (use sudo)."
    exit 1
fi

if ! systemctl list-unit-files | grep -q '^comfyui.service'; then
    err "comfyui.service not installed. Run setup_service first."
    exit 1
fi

systemctl restart comfyui.service
sleep 2
systemctl --no-pager status comfyui.service | head -n 20 || true

PORT="${COMFYUI_PORT:-8188}"
IP="$(hostname -I | awk '{print $1}')"
ok "ComfyUI service started."
log "Open http://$IP:$PORT from any LAN machine."
