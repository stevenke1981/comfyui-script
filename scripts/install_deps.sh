#!/usr/bin/env bash
# Install system-level dependencies on Ubuntu server.

set -euo pipefail

log()  { printf '\033[1;36m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR]\033[0m   %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    err "This step must run as root (use sudo)."
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

log "Updating apt index..."
apt-get update -y

log "Installing base packages..."
apt-get install -y --no-install-recommends \
    ca-certificates curl wget git aria2 \
    build-essential pkg-config cmake ninja-build \
    python3 python3-venv python3-pip python3-dev \
    ffmpeg libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    libjpeg-dev libpng-dev \
    ufw jq unzip tmux htop lsof pciutils net-tools

ok "System dependencies installed."
