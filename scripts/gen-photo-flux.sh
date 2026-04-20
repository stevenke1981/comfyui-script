#!/usr/bin/env bash
# Generate an image via ComfyUI FLUX.1-schnell API.
# Usage: gen-photo-flux.sh [OPTIONS] ["prompt text"]
#
# Options:
#   -f FILE         Read prompt from file (lines starting with # are ignored)
#   -w WIDTH        Image width  (default: 896)
#   -h HEIGHT       Image height (default: 1152)
#   -s STEPS        Sampling steps (default: 4)
#   -g GUIDANCE     Guidance scale (default: 3.5)
#   -S SEED         Random seed; -1 = random (default: -1)
#   -o OUTPUT_DIR   Directory to save the image (default: ~/Pictures/comfyui)
#   -H HOST         ComfyUI host (default: 127.0.0.1:8188)
#   --open          Open the image after saving (uses xdg-open)
#
# Prompt files live in config/prompts/*.txt (one prompt per file).
# Lines starting with # are treated as comments and ignored.
# Newlines within the file are collapsed into a single prompt string.
#
# Examples:
#   gen-photo-flux.sh -f config/prompts/taiwan_beauty.txt
#   gen-photo-flux.sh -f config/prompts/taiwan_beauty.txt -S 42 --open
#   gen-photo-flux.sh "a cat sitting on a roof in Tainan"

set -euo pipefail

# ── defaults ──────────────────────────────────────────────────────────────────
HOST="127.0.0.1:8188"
WIDTH=896
HEIGHT=1152
STEPS=4
GUIDANCE=3.5
SEED=-1
OUTPUT_DIR="$HOME/Pictures/comfyui"
AUTO_OPEN=false
PROMPT_FILE=""

# ── arg parsing ───────────────────────────────────────────────────────────────
usage() {
  awk '/^[^#]/{exit} NR>1{sub(/^# ?/,""); print}' "$0"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f) PROMPT_FILE="$2"; shift 2 ;;
    -w) WIDTH="$2";       shift 2 ;;
    -h) HEIGHT="$2";      shift 2 ;;
    -s) STEPS="$2";       shift 2 ;;
    -g) GUIDANCE="$2";    shift 2 ;;
    -S) SEED="$2";        shift 2 ;;
    -o) OUTPUT_DIR="$2";  shift 2 ;;
    -H) HOST="$2";        shift 2 ;;
    --open) AUTO_OPEN=true; shift ;;
    --help) usage ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1"; usage ;;
    *) break ;;
  esac
done

# ── resolve prompt ─────────────────────────────────────────────────────────────
if [[ -n "$PROMPT_FILE" ]]; then
  if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "Error: prompt file not found: $PROMPT_FILE" >&2
    exit 1
  fi
  # strip comment lines, collapse newlines into comma-separated string
  PROMPT=$(grep -v '^\s*#' "$PROMPT_FILE" | grep -v '^\s*$' | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')
elif [[ $# -gt 0 ]]; then
  PROMPT="$*"
else
  echo "Error: provide a prompt via -f FILE or as a positional argument." >&2
  usage
fi

if [[ -z "$PROMPT" ]]; then
  echo "Error: prompt is empty." >&2
  exit 1
fi

# ── resolve seed ──────────────────────────────────────────────────────────────
if [[ "$SEED" == "-1" ]]; then
  SEED=$(( RANDOM * RANDOM ))
fi

# ── check ComfyUI is up ───────────────────────────────────────────────────────
if ! curl -sf "http://$HOST/system_stats" > /dev/null; then
  echo "Error: ComfyUI is not reachable at http://$HOST" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# show which source the prompt came from
if [[ -n "$PROMPT_FILE" ]]; then
  echo "Prompt : [${PROMPT_FILE}]"
else
  echo "Prompt : $PROMPT"
fi
echo "Size   : ${WIDTH}x${HEIGHT}  Steps: $STEPS  Guidance: $GUIDANCE  Seed: $SEED"
echo "Host   : http://$HOST"

# ── build workflow JSON ───────────────────────────────────────────────────────
WORKFLOW=$(python3 - <<PYEOF
import json, sys

prompt   = sys.argv[1]
width    = int(sys.argv[2])
height   = int(sys.argv[3])
steps    = int(sys.argv[4])
guidance = float(sys.argv[5])
seed     = int(sys.argv[6])

workflow = {
  "1": {
    "class_type": "UNETLoader",
    "inputs": {"unet_name": "flux1-schnell.safetensors", "weight_dtype": "fp8_e4m3fn"}
  },
  "2": {
    "class_type": "DualCLIPLoader",
    "inputs": {
      "clip_name1": "t5xxl_fp8_e4m3fn.safetensors",
      "clip_name2": "clip_l.safetensors",
      "type": "flux",
      "device": "default"
    }
  },
  "3": {
    "class_type": "VAELoader",
    "inputs": {"vae_name": "flux_ae.safetensors"}
  },
  "4": {
    "class_type": "CLIPTextEncode",
    "inputs": {"clip": ["2", 0], "text": prompt}
  },
  "5": {
    "class_type": "EmptySD3LatentImage",
    "inputs": {"width": width, "height": height, "batch_size": 1}
  },
  "6": {
    "class_type": "FluxGuidance",
    "inputs": {"conditioning": ["4", 0], "guidance": guidance}
  },
  "7": {
    "class_type": "KSampler",
    "inputs": {
      "model": ["1", 0],
      "positive": ["6", 0],
      "negative": ["4", 0],
      "latent_image": ["5", 0],
      "sampler_name": "euler",
      "scheduler": "simple",
      "steps": steps,
      "cfg": 1.0,
      "denoise": 1.0,
      "seed": seed
    }
  },
  "8": {
    "class_type": "VAEDecode",
    "inputs": {"samples": ["7", 0], "vae": ["3", 0]}
  },
  "9": {
    "class_type": "SaveImage",
    "inputs": {"images": ["8", 0], "filename_prefix": "flux_gen"}
  }
}
print(json.dumps({"prompt": workflow}))
PYEOF
"$PROMPT" "$WIDTH" "$HEIGHT" "$STEPS" "$GUIDANCE" "$SEED")

# ── submit ────────────────────────────────────────────────────────────────────
RESPONSE=$(curl -sf -X POST "http://$HOST/prompt" \
  -H "Content-Type: application/json" \
  -d "$WORKFLOW")

PROMPT_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['prompt_id'])")
echo "Submitted: $PROMPT_ID"

# ── poll for completion ───────────────────────────────────────────────────────
echo -n "Generating"
for i in $(seq 1 120); do
  sleep 2
  HISTORY=$(curl -sf "http://$HOST/history/$PROMPT_ID")
  if [[ -n "$HISTORY" ]] && echo "$HISTORY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
pid = list(d.keys())[0] if d else ''
exit(0 if pid and d[pid].get('outputs') else 1)
" 2>/dev/null; then
    echo " done."
    break
  fi
  echo -n "."
  if [[ $i -eq 120 ]]; then
    echo ""
    echo "Error: timed out waiting for generation." >&2
    exit 1
  fi
done

# ── download result ───────────────────────────────────────────────────────────
FILENAME=$(echo "$HISTORY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
pid = list(d.keys())[0]
for node in d[pid]['outputs'].values():
    if 'images' in node:
        print(node['images'][0]['filename'])
        break
")

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="$OUTPUT_DIR/flux_${TIMESTAMP}_seed${SEED}.png"

curl -sf "http://$HOST/view?filename=${FILENAME}&type=output" -o "$DEST"
echo "Saved  : $DEST"

if $AUTO_OPEN; then
  xdg-open "$DEST" &
fi
