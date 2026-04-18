#!/usr/bin/env bash
# Detect GPU vendor and install appropriate drivers / runtime.
# Writes vendor to /tmp/comfyui-gpu for later steps.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "[ERR] This step must run as root (use sudo)." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

VENDOR="cpu"

lspci_out="$(lspci -nn 2>/dev/null || true)"

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    VENDOR="nvidia"
elif echo "$lspci_out" | grep -Ei 'VGA|3D|Display' | grep -qi nvidia; then
    VENDOR="nvidia"
elif echo "$lspci_out" | grep -Ei 'VGA|3D|Display' | grep -qi 'Advanced Micro Devices\|AMD\|ATI'; then
    VENDOR="amd"
elif echo "$lspci_out" | grep -Ei 'VGA|3D|Display' | grep -qi intel; then
    VENDOR="intel"
fi

echo "[INFO] Detected GPU vendor: $VENDOR"
echo "$VENDOR" > /tmp/comfyui-gpu

case "$VENDOR" in
    nvidia)
        if ! command -v nvidia-smi >/dev/null 2>&1; then
            echo "[INFO] Installing NVIDIA driver + CUDA toolkit..."
            apt-get update -y
            # ubuntu-drivers picks the recommended driver
            apt-get install -y ubuntu-drivers-common
            ubuntu-drivers autoinstall || {
                echo "[WARN] ubuntu-drivers autoinstall failed. Falling back to nvidia-driver-535."
                apt-get install -y nvidia-driver-535
            }
            apt-get install -y nvidia-cuda-toolkit || \
                echo "[WARN] nvidia-cuda-toolkit not installed from apt. PyTorch ships its own CUDA runtime."
            echo "[WARN] NVIDIA driver installed. A REBOOT may be required before ComfyUI can use the GPU."
        fi
        nvidia-smi || echo "[WARN] nvidia-smi not yet working; reboot required."
        ;;
    amd)
        echo "[INFO] Installing ROCm dependencies (AMD)..."
        apt-get install -y libnuma-dev || true
        # We rely on PyTorch's ROCm wheels at the install_comfyui step.
        echo "[WARN] AMD: PyTorch ROCm wheels will be used. Full ROCm stack install is left to the admin."
        ;;
    intel)
        echo "[INFO] Intel GPU detected. ComfyUI will run with IPEX or CPU fallback."
        apt-get install -y intel-opencl-icd || true
        ;;
    cpu)
        echo "[WARN] No discrete GPU detected. ComfyUI will run on CPU (very slow)."
        ;;
esac

echo "[OK] GPU detection finished: $VENDOR"
