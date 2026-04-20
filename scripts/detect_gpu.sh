#!/usr/bin/env bash
# Detect GPU vendor and install appropriate drivers / runtime.
# Writes vendor to /tmp/comfyui-gpu for later steps.

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

log "Detected GPU vendor: $VENDOR"
echo "$VENDOR" > /tmp/comfyui-gpu

case "$VENDOR" in
    nvidia)
        if ! command -v nvidia-smi >/dev/null 2>&1; then
            log "Installing NVIDIA driver + CUDA toolkit..."
            apt-get update -y
            # ubuntu-drivers picks the recommended driver
            apt-get install -y ubuntu-drivers-common
            ubuntu-drivers autoinstall || {
                warn "ubuntu-drivers autoinstall failed. Falling back to nvidia-driver-535."
                apt-get install -y nvidia-driver-535
            }
            apt-get install -y nvidia-cuda-toolkit || \
                warn "nvidia-cuda-toolkit not installed from apt. PyTorch ships its own CUDA runtime."
            warn "NVIDIA driver installed. A REBOOT may be required before ComfyUI can use the GPU."
        fi
        nvidia-smi || warn "nvidia-smi not yet working; reboot required."
        ;;
    amd)
        log "Installing ROCm dependencies (AMD)..."
        apt-get install -y libnuma-dev || true
        # We rely on PyTorch's ROCm wheels at the install_comfyui step.
        warn "AMD: PyTorch ROCm wheels will be used. Full ROCm stack install is left to the admin."
        ;;
    intel)
        log "Intel GPU detected. ComfyUI will run with IPEX or CPU fallback."
        apt-get install -y intel-opencl-icd || true
        ;;
    cpu)
        warn "No discrete GPU detected. ComfyUI will run on CPU (very slow)."
        ;;
esac

ok "GPU detection finished: $VENDOR"
