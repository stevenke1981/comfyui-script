#!/usr/bin/env bash
# ComfyUI remote management helper — run over SSH from a LAN workstation.
#
# Examples (run on the server, or via:  ssh user@server 'bash -s' < manage.sh <cmd>):
#   ./manage.sh status
#   ./manage.sh start|stop|restart
#   ./manage.sh logs
#   ./manage.sh update
#   ./manage.sh update-nodes
#   ./manage.sh download        # re-run model / LoRA / workflow download
#   ./manage.sh add-model checkpoints <url> [filename]
#   ./manage.sh add-lora <url> [filename]
#   ./manage.sh add-node <git-url>
#   ./manage.sh list-models
#   ./manage.sh gpu             # nvidia-smi / rocm-smi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMFYUI_ROOT="${COMFYUI_ROOT:-$HOME/ComfyUI}"
COMFYUI_USER="${COMFYUI_USER:-$USER}"

log()  { printf '\033[1;36m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR]\033[0m   %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }

cmd="${1:-}"; shift || true

sudo_needed() {
    if [[ $EUID -ne 0 ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

case "$cmd" in
    status)
        sudo_needed systemctl --no-pager status comfyui.service
        ;;
    start|stop|restart)
        sudo_needed systemctl "$cmd" comfyui.service
        ;;
    logs)
        sudo_needed journalctl -u comfyui.service -f --no-pager
        ;;
    update)
        log "Stopping service..."
        sudo_needed systemctl stop comfyui.service || true
        log "Pulling ComfyUI..."
        git -C "$COMFYUI_ROOT" pull --ff-only
        log "Updating Python deps..."
        "$COMFYUI_ROOT/venv/bin/pip" install -r "$COMFYUI_ROOT/requirements.txt"
        sudo_needed systemctl start comfyui.service
        ;;
    update-nodes)
        for d in "$COMFYUI_ROOT/custom_nodes"/*/; do
            [[ -d "$d/.git" ]] || continue
            log "Updating $d"
            git -C "$d" pull --ff-only || true
            [[ -f "$d/requirements.txt" ]] && "$COMFYUI_ROOT/venv/bin/pip" install -r "$d/requirements.txt" || true
        done
        sudo_needed systemctl restart comfyui.service
        ;;
    download)
        bash "$SCRIPT_DIR/scripts/download_models.sh"
        ;;
    add-model)
        subdir="${1:-}"; url="${2:-}"; fname="${3:-}"
        [[ -z "$subdir" || -z "$url" ]] && { err "Usage: manage.sh add-model <subdir> <url> [filename]"; exit 1; }
        echo "${subdir}|${url}|${fname}" >> "$SCRIPT_DIR/config/models.txt"
        bash "$SCRIPT_DIR/scripts/download_models.sh"
        ;;
    add-lora)
        url="${1:-}"; fname="${2:-}"
        [[ -z "$url" ]] && { err "Usage: manage.sh add-lora <url> [filename]"; exit 1; }
        echo "loras|${url}|${fname}" >> "$SCRIPT_DIR/config/loras.txt"
        bash "$SCRIPT_DIR/scripts/download_models.sh"
        ;;
    add-node)
        url="${1:-}"
        [[ -z "$url" ]] && { err "Usage: manage.sh add-node <git-url>"; exit 1; }
        echo "$url" >> "$SCRIPT_DIR/config/custom_nodes.txt"
        bash "$SCRIPT_DIR/scripts/install_custom_nodes.sh"
        sudo_needed systemctl restart comfyui.service
        ;;
    list-models)
        find "$COMFYUI_ROOT/models" -maxdepth 2 -type f -printf '%P\t%s bytes\n' | sort
        ;;
    gpu)
        if command -v nvidia-smi >/dev/null; then nvidia-smi
        elif command -v rocm-smi >/dev/null; then rocm-smi
        else warn "No GPU tool found."
        fi
        ;;
    ""|-h|--help)
        sed -n '1,30p' "$0"
        ;;
    *)
        err "Unknown command: $cmd"
        exit 1
        ;;
esac
