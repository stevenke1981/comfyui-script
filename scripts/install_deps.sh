#!/usr/bin/env bash
# Install system-level dependencies on Ubuntu server.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "[ERR] This step must run as root (use sudo)." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[INFO] Updating apt index..."
apt-get update -y

echo "[INFO] Installing base packages..."
apt-get install -y --no-install-recommends \
    ca-certificates curl wget git aria2 \
    build-essential pkg-config cmake ninja-build \
    python3 python3-venv python3-pip python3-dev \
    ffmpeg libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    libjpeg-dev libpng-dev \
    ufw jq unzip tmux htop lsof pciutils net-tools

# Ensure pip/venv for Python 3
python3 -m pip install --upgrade pip --break-system-packages || \
    python3 -m pip install --upgrade pip

echo "[OK] System dependencies installed."
