# ComfyUI Auto-Installer for Ubuntu Server

One-shot installer for [ComfyUI](https://github.com/comfyanonymous/ComfyUI) on a
headless Ubuntu server (no desktop). It detects your GPU, installs every
dependency, clones ComfyUI, pulls popular custom nodes, optionally downloads
models / LoRAs / workflows, runs ComfyUI as a `systemd` service, and opens the
port to your local network only.

Designed for the common home-lab setup: one Ubuntu box with a GPU in the
closet, several workstations on the LAN that want to hit it.

---

## Features

- Detects NVIDIA / AMD / Intel / CPU-only and installs the right stack
- Installs CUDA / ROCm / CPU PyTorch wheels automatically
- Clones ComfyUI and a set of popular custom nodes (`ComfyUI-Manager`,
  `Impact-Pack`, `rgthree`, `controlnet_aux`, `VideoHelperSuite`, …)
- Plain-text config files for models, LoRAs, and workflows
- Systemd service with restart-on-failure and basic hardening
- UFW rule limits access to your LAN subnet only
- `manage.sh` helper for remote management over SSH

---

## Requirements

- Ubuntu 22.04 / 24.04 server
- `sudo` user with internet access
- (Optional) NVIDIA GPU with driver-compatible hardware
- Disk space for models — SDXL alone needs ~15 GB

---

## Quick start

```bash
git clone https://github.com/stevenke1981/comfyui-script.git
cd comfyui-script

# Review what will be downloaded:
$EDITOR config/models.txt config/loras.txt config/workflows.txt config/custom_nodes.txt

# Full install:
sudo COMFYUI_ROOT="$HOME/ComfyUI" COMFYUI_USER="$USER" bash install.sh --all
```

When it finishes, visit `http://<server-ip>:8188` from any LAN machine.

### Run one step at a time

```bash
sudo bash install.sh --step install_deps
sudo bash install.sh --step detect_gpu
sudo bash install.sh --step install_comfyui
sudo bash install.sh --step install_custom_nodes
sudo bash install.sh --step download_models
sudo bash install.sh --step setup_service
sudo bash install.sh --step setup_firewall
sudo bash install.sh --step start_comfyui
```

### Environment overrides

| Variable            | Default                | Purpose                                     |
| ------------------- | ---------------------- | ------------------------------------------- |
| `COMFYUI_ROOT`      | `$HOME/ComfyUI`        | Install directory                           |
| `COMFYUI_USER`      | `$USER`                | User that owns and runs ComfyUI             |
| `COMFYUI_PORT`      | `8188`                 | Listen port                                 |
| `COMFYUI_BIND`      | `0.0.0.0`              | Bind address (use `127.0.0.1` for SSH only) |
| `COMFYUI_EXTRA_ARGS`| empty                  | Extra flags for `main.py`                   |
| `LAN_CIDR`          | auto-detected          | Subnet allowed through UFW                  |
| `HF_TOKEN`          | –                      | HuggingFace token for gated repos           |
| `CIVITAI_TOKEN`     | –                      | Civitai token for gated LoRAs               |

---

## Configuring downloads

Edit the three config files and uncomment or add lines.

### `config/models.txt` and `config/loras.txt`

```text
# <subdir>|<url>|<optional filename>
checkpoints|https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors|sd_xl_base_1.0.safetensors
loras|https://huggingface.co/latent-consistency/lcm-lora-sdxl/resolve/main/pytorch_lora_weights.safetensors|lcm-lora-sdxl.safetensors
```

`<subdir>` is any folder under `ComfyUI/models/`: `checkpoints`, `vae`, `clip`,
`clip_vision`, `controlnet`, `upscale_models`, `embeddings`, `unet`, `loras`, …

### `config/workflows.txt`

Same format; files land in `ComfyUI/user/default/workflows/`.

### `config/custom_nodes.txt`

One git URL per line. `requirements.txt` inside each node is installed
automatically.

---

## LAN management with `manage.sh`

Run these on the server (or over SSH) once the install has finished:

```bash
./manage.sh status             # show systemd status
./manage.sh start|stop|restart
./manage.sh logs               # tail journalctl
./manage.sh update             # git pull ComfyUI + reinstall deps
./manage.sh update-nodes       # git pull all custom nodes
./manage.sh download           # re-run model/LoRA/workflow downloads
./manage.sh add-model checkpoints <url> [filename]
./manage.sh add-lora   <url> [filename]
./manage.sh add-node   <git-url>
./manage.sh list-models
./manage.sh gpu                # nvidia-smi / rocm-smi
```

You can call it remotely without cloning the repo on the client:

```bash
ssh user@server 'cd ~/comfyui-script && ./manage.sh status'
```

---

## Security notes

- The UFW rule only allows the detected LAN subnet. Override with
  `LAN_CIDR=192.168.1.0/24` if auto-detection is wrong.
- ComfyUI has **no built-in authentication**. If you need auth from outside the
  LAN, front it with Tailscale, WireGuard, or an nginx reverse proxy with basic
  auth or OAuth.
- Do not expose port 8188 directly to the public internet.

---

## Troubleshooting

| Symptom                               | Fix                                                                 |
| ------------------------------------- | ------------------------------------------------------------------- |
| `torch.cuda.is_available() == False`  | Reboot after NVIDIA driver install, then `manage.sh restart`        |
| Service fails on start                | `manage.sh logs`                                                    |
| Port unreachable from LAN             | `sudo ufw status` and confirm `LAN_CIDR`                            |
| Gated HF model 401                    | `export HF_TOKEN=hf_...` before running `download_models`           |
| Node import errors                    | Open ComfyUI-Manager → "Try fix" on the failing node                |

---

## Uninstall

```bash
sudo systemctl disable --now comfyui.service
sudo rm /etc/systemd/system/comfyui.service
sudo ufw delete allow from <lan> to any port 8188 proto tcp
rm -rf "$COMFYUI_ROOT"
```

---

## License

MIT — see [LICENSE](LICENSE).
