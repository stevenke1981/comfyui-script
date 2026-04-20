#!/usr/bin/env bash
# ComfyUI Auto-Installer for Ubuntu Server (no GUI)
# Run as a normal user: ./install.sh --all
# The script calls sudo internally only for steps that need root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export COMFYUI_ROOT="${COMFYUI_ROOT:-$HOME/ComfyUI}"
export COMFYUI_PORT="${COMFYUI_PORT:-8188}"
export COMFYUI_BIND="${COMFYUI_BIND:-0.0.0.0}"
export COMFYUI_USER="${USER}"

log()  { printf '\033[1;36m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR]\033[0m   %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }

if [[ $EUID -eq 0 ]]; then
    err "Do NOT run this script as root. Run as a normal user: ./install.sh --all"
    err "The script will call sudo automatically where needed."
    exit 1
fi

require_ubuntu() {
    if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
        warn "This script is tested on Ubuntu. Continue at your own risk."
    fi
}

usage() {
    cat <<EOF
ComfyUI Auto-Installer

Usage:
  ./install.sh [--all | --step NAME]

Steps (run in order with --all):
  deps        Install system packages  (needs sudo)
  gpu         Detect GPU and install drivers + CUDA / ROCm  (needs sudo)
  comfyui     Clone ComfyUI and install Python requirements
  nodes       Install custom nodes
  models      Download models / LoRA / workflows from config/
  service     Install systemd service  (needs sudo)
  firewall    Open port $COMFYUI_PORT on UFW  (needs sudo)
  start       Start ComfyUI service  (needs sudo)

Environment overrides:
  COMFYUI_ROOT=$COMFYUI_ROOT
  COMFYUI_PORT=$COMFYUI_PORT
  COMFYUI_BIND=$COMFYUI_BIND
  HF_TOKEN=<your token>       (for gated HuggingFace models)
  CIVITAI_TOKEN=<your token>  (for CivitAI models)

Example:
  COMFYUI_ROOT=~/ComfyUI ./install.sh --all
EOF
}

# Steps that must run as root — install.sh invokes them with sudo.
ROOT_STEPS="install_deps detect_gpu setup_service setup_firewall start_comfyui"

needs_root() {
    local step="$1"
    for s in $ROOT_STEPS; do
        [[ "$s" == "$step" ]] && return 0
    done
    return 1
}

run_step() {
    local step="$1"
    local script="$SCRIPT_DIR/scripts/$step.sh"

    if [[ ! -f "$script" ]]; then
        err "Step script not found: $script"
        exit 1
    fi
    chmod +x "$script"

    log "=== Running step: $step ==="
    if needs_root "$step"; then
        sudo --preserve-env=COMFYUI_ROOT,COMFYUI_PORT,COMFYUI_BIND,COMFYUI_USER \
            bash "$script"
    else
        bash "$script"
    fi
    ok "Step $step finished"
}

main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi

    require_ubuntu

    local all=0
    local steps=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)  all=1; shift ;;
            --step) steps+=("$2"); shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) err "Unknown argument: $1"; usage; exit 1 ;;
        esac
    done

    if [[ $all -eq 1 ]]; then
        steps=(install_deps detect_gpu install_comfyui install_custom_nodes download_models setup_service setup_firewall start_comfyui)
    fi

    if [[ ${#steps[@]} -eq 0 ]]; then
        err "No steps selected. Use --all or --step NAME."
        exit 1
    fi

    for s in "${steps[@]}"; do
        run_step "$s"
    done

    ok "Done. ComfyUI should be available at http://$(hostname -I | awk '{print $1}'):$COMFYUI_PORT"
}

main "$@"
