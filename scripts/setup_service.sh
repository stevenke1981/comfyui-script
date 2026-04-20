#!/usr/bin/env bash
# Install a systemd service that runs ComfyUI bound to LAN.

set -euo pipefail

log()  { printf '\033[1;36m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR]\033[0m   %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    err "This step must run as root (use sudo)."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMFYUI_USER="${COMFYUI_USER:-${SUDO_USER:-}}"
COMFYUI_ROOT="${COMFYUI_ROOT:-/home/$COMFYUI_USER/ComfyUI}"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"
COMFYUI_BIND="${COMFYUI_BIND:-0.0.0.0}"
COMFYUI_EXTRA_ARGS="${COMFYUI_EXTRA_ARGS:-}"

if [[ -z "$COMFYUI_USER" || "$COMFYUI_USER" == "root" ]]; then
    err "COMFYUI_USER must be a non-root user. Pass it via: sudo COMFYUI_USER=yourname bash setup_service.sh"
    exit 1
fi

SERVICE_FILE=/etc/systemd/system/comfyui.service
TEMPLATE="$SCRIPT_DIR/systemd/comfyui.service"

if [[ ! -f "$TEMPLATE" ]]; then
    err "Service template missing: $TEMPLATE"
    exit 1
fi

log "Writing $SERVICE_FILE"
sed \
    -e "s|__USER__|$COMFYUI_USER|g" \
    -e "s|__ROOT__|$COMFYUI_ROOT|g" \
    -e "s|__PORT__|$COMFYUI_PORT|g" \
    -e "s|__BIND__|$COMFYUI_BIND|g" \
    -e "s|__EXTRA__|$COMFYUI_EXTRA_ARGS|g" \
    "$TEMPLATE" > "$SERVICE_FILE"

chmod 644 "$SERVICE_FILE"
systemctl daemon-reload
systemctl enable comfyui.service

ok "systemd service installed. Start with: systemctl start comfyui"
