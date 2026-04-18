#!/usr/bin/env bash
# ComfyUI Auto-Installer for Ubuntu Server (no GUI)
# Detects GPU, installs dependencies, ComfyUI, models, and exposes to LAN.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export COMFYUI_ROOT="${COMFYUI_ROOT:-$HOME/ComfyUI}"
export COMFYUI_PORT="${COMFYUI_PORT:-8188}"
export COMFYUI_BIND="${COMFYUI_BIND:-0.0.0.0}"
export COMFYUI_USER="${COMFYUI_USER:-$USER}"

log()  { printf '\033[1;36m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR]\033[0m   %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }

require_ubuntu() {
    if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
        warn "This script is tested on Ubuntu. Continue at your own risk."
    fi
}

usage() {
    cat <<EOF
ComfyUI Auto-Installer

Usage:
  sudo bash install.sh [--all | --step NAME]

Steps (run in order with --all):
  deps        Install system packages (python, git, build tools, etc.)
  gpu         Detect GPU and install drivers + CUDA / ROCm
  comfyui     Clone ComfyUI and install Python requirements
  nodes       Install custom nodes (ComfyUI-Manager, etc.)
  models      Download models / LoRA / workflows from config/
  service     Install systemd service (binds to LAN)
  firewall    Open port $COMFYUI_PORT on UFW for LAN access
  start       Start ComfyUI service

Environment overrides:
  COMFYUI_ROOT=$COMFYUI_ROOT
  COMFYUI_PORT=$COMFYUI_PORT
  COMFYUI_BIND=$COMFYUI_BIND
  COMFYUI_USER=$COMFYUI_USER

Example:
  sudo COMFYUI_ROOT=/opt/ComfyUI bash install.sh --all
EOF
}

run_step() {
    local step="$1"
    local script="$SCRIPT_DIR/scripts/$step.sh"
    if [[ ! -x "$script" ]]; then
        chmod +x "$script" 2>/dev/null || true
    fi
    if [[ ! -f "$script" ]]; then
        err "Step script not found: $script"
        exit 1
    fi
    log "=== Running step: $step ==="
    bash "$script"
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
            --all) all=1; shift ;;
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

    ok "Done. ComfyUI should be available at http://<server-ip>:$COMFYUI_PORT"
}

main "$@"
