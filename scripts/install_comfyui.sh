#!/usr/bin/env bash
# Clone ComfyUI and install Python dependencies in a venv.

set -euo pipefail

log()  { printf '\033[1;36m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR]\033[0m   %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }

COMFYUI_ROOT="${COMFYUI_ROOT:-$HOME/ComfyUI}"
COMFYUI_USER="${COMFYUI_USER:-$USER}"
VENDOR="$(cat /tmp/comfyui-gpu 2>/dev/null || echo cpu)"

log "Installing ComfyUI to: $COMFYUI_ROOT"
log "GPU vendor for torch selection: $VENDOR"

# Create install dir with correct ownership
if [[ $EUID -eq 0 ]]; then
    install -d -o "$COMFYUI_USER" -g "$COMFYUI_USER" "$(dirname "$COMFYUI_ROOT")"
fi

run_as_user() {
    if [[ $EUID -eq 0 ]]; then
        sudo -u "$COMFYUI_USER" -H bash -c "$*"
    else
        bash -c "$*"
    fi
}

# Clone or update
if [[ ! -d "$COMFYUI_ROOT/.git" ]]; then
    run_as_user "git clone https://github.com/comfyanonymous/ComfyUI.git '$COMFYUI_ROOT'"
else
    log "ComfyUI repo already present, pulling latest..."
    run_as_user "git -C '$COMFYUI_ROOT' pull --ff-only"
fi

# Create venv
if [[ ! -d "$COMFYUI_ROOT/venv" ]]; then
    run_as_user "python3 -m venv '$COMFYUI_ROOT/venv'"
fi

PIP="$COMFYUI_ROOT/venv/bin/pip"
PY="$COMFYUI_ROOT/venv/bin/python"

run_as_user "$PIP install --upgrade pip wheel setuptools"

# Install PyTorch per vendor
case "$VENDOR" in
    nvidia)
        log "Installing PyTorch CUDA 12.4 wheels..."
        run_as_user "$PIP install --upgrade torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124"
        ;;
    amd)
        log "Installing PyTorch ROCm 6.1 wheels..."
        run_as_user "$PIP install --upgrade torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.1"
        ;;
    intel)
        log "Installing PyTorch CPU wheels + IPEX..."
        run_as_user "$PIP install --upgrade torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu"
        run_as_user "$PIP install --upgrade intel-extension-for-pytorch || true"
        ;;
    cpu|*)
        log "Installing PyTorch CPU wheels..."
        run_as_user "$PIP install --upgrade torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu"
        ;;
esac

# ComfyUI requirements
run_as_user "$PIP install -r '$COMFYUI_ROOT/requirements.txt'"

# Sanity check
run_as_user "$PY -c 'import torch; print(\"torch:\", torch.__version__, \"cuda:\", torch.cuda.is_available())'"

ok "ComfyUI installed at $COMFYUI_ROOT"
