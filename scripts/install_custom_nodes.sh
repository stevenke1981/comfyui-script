#!/usr/bin/env bash
# Install custom nodes from config/custom_nodes.txt (one git URL per line).

set -euo pipefail

log()  { printf '\033[1;36m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR]\033[0m   %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMFYUI_ROOT="${COMFYUI_ROOT:-$HOME/ComfyUI}"
COMFYUI_USER="${COMFYUI_USER:-$USER}"
NODES_DIR="$COMFYUI_ROOT/custom_nodes"
CONFIG="$SCRIPT_DIR/config/custom_nodes.txt"
PIP="$COMFYUI_ROOT/venv/bin/pip"

run_as_user() {
    if [[ $EUID -eq 0 ]]; then
        sudo -u "$COMFYUI_USER" -H bash -c "$*"
    else
        bash -c "$*"
    fi
}

if [[ ! -d "$NODES_DIR" ]]; then
    err "custom_nodes dir missing: $NODES_DIR. Did you run install_comfyui?"
    exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
    warn "No custom_nodes.txt found at $CONFIG. Skipping."
    exit 0
fi

log "Installing custom nodes from $CONFIG"

while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip comments and trim
    url="${line%%#*}"
    url="$(echo "$url" | xargs || true)"
    [[ -z "$url" ]] && continue

    name="$(basename "$url" .git)"
    target="$NODES_DIR/$name"

    if [[ -d "$target/.git" ]]; then
        log "Updating $name"
        run_as_user "git -C '$target' pull --ff-only" || warn "pull failed for $name"
    else
        log "Cloning $name"
        run_as_user "git clone --depth=1 '$url' '$target'" || { warn "clone failed for $url"; continue; }
    fi

    # Install node requirements if present
    if [[ -f "$target/requirements.txt" ]]; then
        log "Installing Python deps for $name"
        run_as_user "$PIP install -r '$target/requirements.txt'" || warn "pip install failed for $name"
    fi
done < "$CONFIG"

ok "Custom nodes installed."
