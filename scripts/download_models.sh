#!/usr/bin/env bash
# Download models, LoRAs, VAEs, and workflows from config files.
# Runs as the current (non-root) user.
#
# Config format (one entry per line, #-comments ok):
#   <subdir>|<url>|<optional_filename>

set -euo pipefail

log()  { printf '\033[1;36m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR]\033[0m   %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }
skip() { printf '\033[1;34m[SKIP]\033[0m  %s\n' "$*"; }
dl()   { printf '\033[1;35m[DL]\033[0m    %s\n' "$*"; }

if [[ $EUID -eq 0 ]]; then
    err "This step must NOT run as root."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMFYUI_ROOT="${COMFYUI_ROOT:-$HOME/ComfyUI}"
MODELS_DIR="$COMFYUI_ROOT/models"
WORKFLOWS_DIR="$COMFYUI_ROOT/user/default/workflows"

download_one() {
    local subdir="$1" url="$2" fname="$3" base="$4"
    local target_dir="$base/$subdir"
    mkdir -p "$target_dir"

    if [[ -z "$fname" ]]; then
        fname="$(basename "${url%%\?*}")"
    fi
    local out="$target_dir/$fname"

    if [[ -s "$out" ]]; then
        skip "$subdir/$fname (already exists)"
        return 0
    fi

    dl "$subdir/$fname  <=  $url"

    # CivitAI: append token as query param
    if [[ "$url" == *civitai.com* && -n "${CIVITAI_TOKEN:-}" ]]; then
        if [[ "$url" == *\?* ]]; then
            url="${url}&token=${CIVITAI_TOKEN}"
        else
            url="${url}?token=${CIVITAI_TOKEN}"
        fi
    fi

    # Build auth header for HuggingFace
    local -a auth=()
    if [[ "$url" == *huggingface.co* && -n "${HF_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer ${HF_TOKEN}")
    fi

    if command -v curl >/dev/null 2>&1; then
        curl -L --fail --progress-bar "${auth[@]}" -o "${out}.part" "$url" \
            && mv "${out}.part" "$out"
    elif command -v wget >/dev/null 2>&1; then
        local wget_hdr=""
        [[ ${#auth[@]} -gt 0 ]] && wget_hdr="${auth[1]}"
        wget -q --show-progress -c \
            ${wget_hdr:+--header="$wget_hdr"} \
            -O "${out}.part" "$url" \
            && mv "${out}.part" "$out"
    else
        err "Neither curl nor wget found. Install one and retry."
        exit 1
    fi
}

process_config() {
    local cfg="$1" base="$2"
    [[ -f "$cfg" ]] || { warn "Missing config: $cfg"; return 0; }
    log "Processing $cfg -> $base"

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="$(echo "$line" | xargs || true)"
        [[ -z "$line" ]] && continue

        IFS='|' read -r subdir url fname <<< "$line"
        subdir="$(echo "${subdir:-}" | xargs)"
        url="$(echo "${url:-}" | xargs)"
        fname="$(echo "${fname:-}" | xargs)"

        if [[ -z "$subdir" || -z "$url" ]]; then
            warn "Malformed line: $line"
            continue
        fi
        download_one "$subdir" "$url" "$fname" "$base"
    done < "$cfg"
}

log "Downloading models into: $MODELS_DIR"
process_config "$SCRIPT_DIR/config/models.txt" "$MODELS_DIR"
process_config "$SCRIPT_DIR/config/loras.txt"  "$MODELS_DIR"

log "Downloading workflows into: $WORKFLOWS_DIR"
process_config "$SCRIPT_DIR/config/workflows.txt" "$WORKFLOWS_DIR"

ok "Model / workflow download finished."
