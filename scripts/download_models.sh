#!/usr/bin/env bash
# Download models, LoRAs, VAEs, and workflows from config files.
# Config format (one entry per line, #-comments ok):
#   <subdir>|<url>|<optional_filename>
# Example:
#   checkpoints|https://huggingface.co/.../sd_xl_base_1.0.safetensors|sd_xl_base_1.0.safetensors

set -euo pipefail

log()  { printf '\033[1;36m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR]\033[0m   %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }
skip() { printf '\033[1;34m[SKIP]\033[0m  %s\n' "$*"; }
dl()   { printf '\033[1;35m[DL]\033[0m    %s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMFYUI_ROOT="${COMFYUI_ROOT:-$HOME/ComfyUI}"
COMFYUI_USER="${COMFYUI_USER:-$USER}"
MODELS_DIR="$COMFYUI_ROOT/models"
WORKFLOWS_DIR="$COMFYUI_ROOT/user/default/workflows"

run_as_user() {
    if [[ $EUID -eq 0 ]]; then
        sudo -u "$COMFYUI_USER" -H bash -c "$*"
    else
        bash -c "$*"
    fi
}

download_one() {
    local subdir="$1" url="$2" fname="$3" base="$4"
    local target_dir="$base/$subdir"
    run_as_user "mkdir -p '$target_dir'"

    if [[ -z "$fname" ]]; then
        fname="$(basename "${url%%\?*}")"
    fi
    local out="$target_dir/$fname"

    if [[ -s "$out" ]]; then
        skip "$out (already exists)"
        return 0
    fi

    dl "$subdir/$fname  <=  $url"

    # Auth header for HuggingFace / Civitai if env var present
    local hdrs=()
    if [[ "$url" == *huggingface.co* && -n "${HF_TOKEN:-}" ]]; then
        hdrs=(--header="Authorization: Bearer $HF_TOKEN")
    fi
    if [[ "$url" == *civitai.com* && -n "${CIVITAI_TOKEN:-}" ]]; then
        url="${url}${url/*\?*/&}token=$CIVITAI_TOKEN"
    fi

    if command -v aria2c >/dev/null 2>&1; then
        run_as_user "aria2c -x 8 -s 8 -c --dir='$target_dir' --out='$fname' '${hdrs[*]:-}' '$url'" || {
            warn "aria2c failed, falling back to wget"
            run_as_user "wget -c -O '$out.part' ${hdrs[*]:-} '$url' && mv '$out.part' '$out'"
        }
    else
        run_as_user "wget -c -O '$out.part' ${hdrs[*]:-} '$url' && mv '$out.part' '$out'"
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
process_config "$SCRIPT_DIR/config/models.txt"    "$MODELS_DIR"
process_config "$SCRIPT_DIR/config/loras.txt"     "$MODELS_DIR"

log "Downloading workflows into: $WORKFLOWS_DIR"
process_config "$SCRIPT_DIR/config/workflows.txt" "$WORKFLOWS_DIR"

ok "Model / workflow download finished."
