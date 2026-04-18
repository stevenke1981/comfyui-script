#!/usr/bin/env bash
# Install custom nodes from config/custom_nodes.txt (one git URL per line).

set -euo pipefail

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
    echo "[ERR] custom_nodes dir missing: $NODES_DIR. Did you run install_comfyui?" >&2
    exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
    echo "[WARN] No custom_nodes.txt found at $CONFIG. Skipping."
    exit 0
fi

echo "[INFO] Installing custom nodes from $CONFIG"

while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip comments and trim
    url="${line%%#*}"
    url="$(echo "$url" | xargs || true)"
    [[ -z "$url" ]] && continue

    name="$(basename "$url" .git)"
    target="$NODES_DIR/$name"

    if [[ -d "$target/.git" ]]; then
        echo "[INFO] Updating $name"
        run_as_user "git -C '$target' pull --ff-only" || echo "[WARN] pull failed for $name"
    else
        echo "[INFO] Cloning $name"
        run_as_user "git clone --depth=1 '$url' '$target'" || { echo "[WARN] clone failed for $url"; continue; }
    fi

    # Install node requirements if present
    if [[ -f "$target/requirements.txt" ]]; then
        echo "[INFO] Installing Python deps for $name"
        run_as_user "$PIP install -r '$target/requirements.txt'" || echo "[WARN] pip install failed for $name"
    fi
done < "$CONFIG"

echo "[OK] Custom nodes installed."
