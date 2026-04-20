#!/usr/bin/env bash
# Open ComfyUI port to the local network only (not the public internet).

set -euo pipefail

log()  { printf '\033[1;36m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR]\033[0m   %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    err "This step must run as root (use sudo)."
    exit 1
fi

COMFYUI_PORT="${COMFYUI_PORT:-8188}"
LAN_CIDR="${LAN_CIDR:-}"

detect_lan() {
    # Pick the default route's subnet in CIDR form.
    ip -o -4 addr show scope global | awk '{print $4}' | head -n1
}

if [[ -z "$LAN_CIDR" ]]; then
    LAN_CIDR="$(detect_lan || true)"
fi

if [[ -z "$LAN_CIDR" ]]; then
    warn "Could not detect LAN subnet. Falling back to 192.168.0.0/16"
    LAN_CIDR="192.168.0.0/16"
fi

log "Allowing TCP $COMFYUI_PORT from $LAN_CIDR via UFW"

if ! command -v ufw >/dev/null 2>&1; then
    apt-get install -y ufw
fi

# Make sure SSH stays open before enabling UFW.
ufw allow OpenSSH >/dev/null 2>&1 || ufw allow 22/tcp >/dev/null 2>&1 || true
ufw allow from "$LAN_CIDR" to any port "$COMFYUI_PORT" proto tcp
ufw --force enable

ufw status verbose | sed 's/^/[UFW] /'

ok "Firewall configured. ComfyUI is reachable on port $COMFYUI_PORT from $LAN_CIDR only."
