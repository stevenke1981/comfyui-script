#!/usr/bin/env bash
# Generate an image via ComfyUI using FLUX.1-schnell GGUF (Q8_0).
# Uses UnetLoaderGGUF node — better prompt adherence than safetensors at 8 steps.
#
# Usage: gen-photo-flux-gguf.sh [OPTIONS] ["prompt text"]
#
# Options:
#   -f FILE         Read prompt from file (lines starting with # are ignored)
#   -w WIDTH        Image width  (default: 896)
#   -h HEIGHT       Image height (default: 1152)
#   -s STEPS        Sampling steps (default: 8)
#   -g GUIDANCE     Guidance scale (default: 3.5)
#   -S SEED         Random seed; -1 = random (default: -1)
#   -o OUTPUT_DIR   Directory to save the image (default: ~/Pictures/comfyui)
#   -H HOST         ComfyUI host (default: 127.0.0.1:8188)
#   --open          Open the image after saving (uses xdg-open)
#
# Prompt files live in config/prompts/*.txt
# Lines starting with # are treated as comments and ignored.
#
# Examples:
#   gen-photo-flux-gguf.sh -f config/prompts/taiwan_beauty.txt
#   gen-photo-flux-gguf.sh -f config/prompts/taiwan_beauty.txt -S 42 --open
#   gen-photo-flux-gguf.sh -s 12 "portrait of a Taipei street vendor"

set -euo pipefail

# ── defaults ──────────────────────────────────────────────────────────────────
HOST="127.0.0.1:8188"
WIDTH=896
HEIGHT=1152
STEPS=8
GUIDANCE=3.5
SEED=-1
OUTPUT_DIR="$HOME/Pictures/comfyui"
AUTO_OPEN=false
PROMPT_FILE=""

GGUF_MODEL="flux1-schnell-Q8_0.gguf"
CLIP1="t5xxl_fp8_e4m3fn.safetensors"
CLIP2="clip_l.safetensors"
VAE="flux_ae.safetensors"

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
  [[ ! -f "$PROMPT_FILE" ]] && { echo "Error: prompt file not found: $PROMPT_FILE" >&2; exit 1; }
  PROMPT=$(grep -v '^\s*#' "$PROMPT_FILE" | grep -v '^\s*$' | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')
elif [[ $# -gt 0 ]]; then
  PROMPT="$*"
else
  echo "Error: provide a prompt via -f FILE or as a positional argument." >&2
  usage
fi

[[ -z "$PROMPT" ]] && { echo "Error: prompt is empty." >&2; exit 1; }

# ── resolve seed ──────────────────────────────────────────────────────────────
[[ "$SEED" == "-1" ]] && SEED=$(( RANDOM * RANDOM ))

# ── check ComfyUI is up ───────────────────────────────────────────────────────
if ! curl -sf "http://$HOST/system_stats" > /dev/null; then
  echo "Error: ComfyUI is not reachable at http://$HOST" >&2
  exit 1
fi

# ── check UnetLoaderGGUF node is available ────────────────────────────────────
if ! curl -sf "http://$HOST/object_info/UnetLoaderGGUF" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if 'UnetLoaderGGUF' in d else 1)" 2>/dev/null; then
  echo "Error: UnetLoaderGGUF node not found." >&2
  echo "Install ComfyUI-GGUF and restart ComfyUI:" >&2
  echo "  cd ~/ComfyUI/custom_nodes && git clone https://github.com/city96/ComfyUI-GGUF.git" >&2
  echo "  pip install -r ComfyUI-GGUF/requirements.txt" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

if [[ -n "$PROMPT_FILE" ]]; then
  echo "Prompt : [${PROMPT_FILE}]"
else
  echo "Prompt : $PROMPT"
fi
echo "Model  : $GGUF_MODEL"
echo "Size   : ${WIDTH}x${HEIGHT}  Steps: $STEPS  Guidance: $GUIDANCE  Seed: $SEED"
echo "Host   : http://$HOST"

# ── build workflow JSON ───────────────────────────────────────────────────────
WORKFLOW=$(FLUX_PROMPT="$PROMPT" FLUX_WIDTH="$WIDTH" FLUX_HEIGHT="$HEIGHT" \
           FLUX_STEPS="$STEPS" FLUX_GUIDANCE="$GUIDANCE" FLUX_SEED="$SEED" \
           FLUX_MODEL="$GGUF_MODEL" FLUX_CLIP1="$CLIP1" FLUX_CLIP2="$CLIP2" FLUX_VAE="$VAE" \
           python3 - <<'PYEOF'
import json, os

prompt     = os.environ['FLUX_PROMPT']
width      = int(os.environ['FLUX_WIDTH'])
height     = int(os.environ['FLUX_HEIGHT'])
steps      = int(os.environ['FLUX_STEPS'])
guidance   = float(os.environ['FLUX_GUIDANCE'])
seed       = int(os.environ['FLUX_SEED'])
gguf_model = os.environ['FLUX_MODEL']
clip1      = os.environ['FLUX_CLIP1']
clip2      = os.environ['FLUX_CLIP2']
vae        = os.environ['FLUX_VAE']

workflow = {
  "1": {
    "class_type": "UnetLoaderGGUF",
    "inputs": {"unet_name": gguf_model}
  },
  "2": {
    "class_type": "DualCLIPLoader",
    "inputs": {
      "clip_name1": clip1,
      "clip_name2": clip2,
      "type": "flux",
      "device": "default"
    }
  },
  "3": {
    "class_type": "VAELoader",
    "inputs": {"vae_name": vae}
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
    "inputs": {"images": ["8", 0], "filename_prefix": "flux_gguf"}
  }
}
print(json.dumps({"prompt": workflow}))
PYEOF
)

# ── submit ────────────────────────────────────────────────────────────────────
RESPONSE=$(curl -sf -X POST "http://$HOST/prompt" \
  -H "Content-Type: application/json" \
  -d "$WORKFLOW")

PROMPT_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['prompt_id'])")
echo "Submitted: $PROMPT_ID"

# ── poll for completion ───────────────────────────────────────────────────────
echo -n "Generating"
for i in $(seq 1 180); do
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
  if [[ $i -eq 180 ]]; then
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
DEST="$OUTPUT_DIR/flux_gguf_${TIMESTAMP}_seed${SEED}.png"

curl -sf "http://$HOST/view?filename=${FILENAME}&type=output" -o "$DEST"
echo "Saved  : $DEST"

$AUTO_OPEN && xdg-open "$DEST" &
