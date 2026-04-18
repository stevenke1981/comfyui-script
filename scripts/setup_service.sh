#!/usr/bin/env bash
# Install a systemd service that runs ComfyUI bound to LAN.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "[ERR] This step must run as root (use sudo)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMFYUI_ROOT="${COMFYUI_ROOT:-/home/$USER/ComfyUI}"
COMFYUI_USER="${COMFYUI_USER:-$SUDO_USER}"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"
COMFYUI_BIND="${COMFYUI_BIND:-0.0.0.0}"
COMFYUI_EXTRA_ARGS="${COMFYUI_EXTRA_ARGS:-}"

if [[ -z "$COMFYUI_USER" || "$COMFYUI_USER" == "root" ]]; then
    echo "[ERR] COMFYUI_USER must be a non-root user. Set it via env or run via sudo as a normal user." >&2
    exit 1
fi

SERVICE_FILE=/etc/systemd/system/comfyui.service
TEMPLATE="$SCRIPT_DIR/systemd/comfyui.service"

if [[ ! -f "$TEMPLATE" ]]; then
    echo "[ERR] Service template missing: $TEMPLATE" >&2
    exit 1
fi

echo "[INFO] Writing $SERVICE_FILE"
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

echo "[OK] systemd service installed. Start with: systemctl start comfyui"
