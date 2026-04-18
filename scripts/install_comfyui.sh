#!/usr/bin/env bash
# Clone ComfyUI and install Python dependencies in a venv.

set -euo pipefail

COMFYUI_ROOT="${COMFYUI_ROOT:-$HOME/ComfyUI}"
COMFYUI_USER="${COMFYUI_USER:-$USER}"
VENDOR="$(cat /tmp/comfyui-gpu 2>/dev/null || echo cpu)"

echo "[INFO] Installing ComfyUI to: $COMFYUI_ROOT"
echo "[INFO] GPU vendor for torch selection: $VENDOR"

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
    echo "[INFO] ComfyUI repo already present, pulling latest..."
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
        echo "[INFO] Installing PyTorch CUDA 12.4 wheels..."
        run_as_user "$PIP install --upgrade torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124"
        ;;
    amd)
        echo "[INFO] Installing PyTorch ROCm 6.1 wheels..."
        run_as_user "$PIP install --upgrade torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.1"
        ;;
    intel)
        echo "[INFO] Installing PyTorch CPU wheels + IPEX..."
        run_as_user "$PIP install --upgrade torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu"
        run_as_user "$PIP install --upgrade intel-extension-for-pytorch || true"
        ;;
    cpu|*)
        echo "[INFO] Installing PyTorch CPU wheels..."
        run_as_user "$PIP install --upgrade torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu"
        ;;
esac

# ComfyUI requirements
run_as_user "$PIP install -r '$COMFYUI_ROOT/requirements.txt'"

# Sanity check
run_as_user "$PY -c 'import torch; print(\"torch:\", torch.__version__, \"cuda:\", torch.cuda.is_available())'"

echo "[OK] ComfyUI installed at $COMFYUI_ROOT"
