#!/usr/bin/env bash
# Start (or restart) the ComfyUI systemd service and show its status.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "[ERR] This step must run as root (use sudo)." >&2
    exit 1
fi

if ! systemctl list-unit-files | grep -q '^comfyui.service'; then
    echo "[ERR] comfyui.service not installed. Run setup_service first." >&2
    exit 1
fi

systemctl restart comfyui.service
sleep 2
systemctl --no-pager status comfyui.service | head -n 20 || true

PORT="${COMFYUI_PORT:-8188}"
IP="$(hostname -I | awk '{print $1}')"
echo "[OK] ComfyUI service started."
echo "[INFO] Open http://$IP:$PORT from any LAN machine."
