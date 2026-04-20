#!/usr/bin/env bash
# Clone ComfyUI and install Python dependencies in a venv.
# Runs as the current (non-root) user.

set -euo pipefail

log()  { printf '\033[1;36m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR]\033[0m   %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }

if [[ $EUID -eq 0 ]]; then
    err "This step must NOT run as root."
    exit 1
fi

COMFYUI_ROOT="${COMFYUI_ROOT:-$HOME/ComfyUI}"
VENDOR="$(cat /tmp/comfyui-gpu 2>/dev/null || echo cpu)"

log "Installing ComfyUI to: $COMFYUI_ROOT"
log "GPU vendor for torch selection: $VENDOR"

# Clone or update
if [[ ! -d "$COMFYUI_ROOT/.git" ]]; then
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_ROOT"
else
    log "ComfyUI repo already present, pulling latest..."
    git -C "$COMFYUI_ROOT" pull --ff-only
fi

# Create venv
if [[ ! -d "$COMFYUI_ROOT/venv" ]]; then
    python3 -m venv "$COMFYUI_ROOT/venv"
fi

PIP="$COMFYUI_ROOT/venv/bin/pip"
PY="$COMFYUI_ROOT/venv/bin/python"

"$PIP" install --upgrade pip wheel setuptools

# Install PyTorch per vendor
case "$VENDOR" in
    nvidia)
        log "Installing PyTorch CUDA 12.4 wheels..."
        "$PIP" install --upgrade torch torchvision torchaudio \
            --index-url https://download.pytorch.org/whl/cu124
        ;;
    amd)
        log "Installing PyTorch ROCm 6.1 wheels..."
        "$PIP" install --upgrade torch torchvision torchaudio \
            --index-url https://download.pytorch.org/whl/rocm6.1
        ;;
    intel)
        log "Installing PyTorch CPU wheels + IPEX..."
        "$PIP" install --upgrade torch torchvision torchaudio \
            --index-url https://download.pytorch.org/whl/cpu
        "$PIP" install --upgrade intel-extension-for-pytorch || true
        ;;
    cpu|*)
        log "Installing PyTorch CPU wheels..."
        "$PIP" install --upgrade torch torchvision torchaudio \
            --index-url https://download.pytorch.org/whl/cpu
        ;;
esac

"$PIP" install -r "$COMFYUI_ROOT/requirements.txt"

"$PY" -c 'import torch; print("torch:", torch.__version__, "cuda:", torch.cuda.is_available())'

ok "ComfyUI installed at $COMFYUI_ROOT"
