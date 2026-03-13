# install-ai-pytorch

Automated VPS AI setup for **Ollama + Vision LLM** (`llama3.2-vision`) on AMD GPU (ROCm) or NVIDIA GPU (CUDA).

---

## What this repo does

- Installs and configures [Ollama](https://ollama.com/) on a fresh VPS
- Configures Ollama to be accessible from Docker containers / JupyterLab
- Sets up firewall rules so Docker containers can reach Ollama
- Pulls the default vision model (`llama3.2-vision:11b`)
- Provides a Python script to bulk-export image metadata to CSV using a vision LLM
- Provides a connectivity test script useful from JupyterLab or Docker

---

## Prerequisites

| Requirement | Details |
|---|---|
| OS | Ubuntu 20.04+ / Debian 11+ |
| GPU | AMD MI-series with ROCm **or** NVIDIA GPU with CUDA |
| RAM / VRAM | ≥ 16 GB VRAM for 11B model, ≥ 144 GB for 72B model |
| Internet | Required to download Ollama and model weights |
| Python | Python 3.8+ with `pip` |

> **Tested on:** AMD MI300X (192 GB VRAM) with ROCm 7.0

---

## Quick Start

```bash
git clone https://github.com/georgepre13/install-ai-pytorch.git
cd install-ai-pytorch
bash setup.sh
```

That's it. The script is **idempotent** — safe to run multiple times.

For automated/CI environments (no interactive prompts):

```bash
bash setup.sh --non-interactive
```

---

## Manual Step-by-Step

If you prefer to run steps manually:

### 1. Install Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

### 2. Configure Ollama to listen on all interfaces

By default Ollama binds to `127.0.0.1:11434`, which is not reachable from Docker containers.

```bash
# Create a systemd drop-in override
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/ollama-host.conf <<'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF

sudo systemctl daemon-reload
sudo systemctl restart ollama

# Verify — should show *:11434 or 0.0.0.0:11434
ss -tlnp | grep 11434
```

### 3. Allow Docker network access via iptables

```bash
sudo iptables -I INPUT -p tcp --dport 11434 -s 172.17.0.0/16 -j ACCEPT
```

### 4. Pull the vision model

```bash
ollama pull llama3.2-vision:11b
```

### 5. Install Python dependencies

```bash
pip install Pillow requests pandas
```

---

## Usage

### Metadata export script

```bash
# Basic usage (edit defaults at top of script)
python3 vlm_metadata_export.py

# With CLI arguments
python3 vlm_metadata_export.py \
    --folder /path/to/images \
    --output results.csv \
    --model llama3.2-vision:11b \
    --ollama-url http://localhost:11434
```

#### From inside JupyterLab / Docker

```bash
python3 vlm_metadata_export.py \
    --folder /shared-docker/gambar \
    --output /shared-docker/metadata.csv \
    --ollama-url http://172.17.0.1:11434
```

### Connectivity test

```bash
# From VPS host
python3 test_connection.py

# From inside Docker / JupyterLab
python3 test_connection.py --ollama-url http://172.17.0.1:11434
```

### Quick API test (curl)

```bash
# From host
curl http://localhost:11434/api/tags

# From Docker container
curl http://172.17.0.1:11434/api/tags
```

---

## Example CSV Output

| Filename | Title | Description | Keywords | Category | Mood | Colors |
|---|---|---|---|---|---|---|
| solar.jpg | Solar Panel on Rooftop with Green Plants | A rooftop solar installation surrounded by potted plants, illustrating sustainable energy in an urban setting. | solar panel, renewable energy, green, rooftop, … | technology | calm, optimistic | dark blue, silver, green |

---

## Configuration Options

### `vlm_metadata_export.py` defaults

| Variable | Default | Description |
|---|---|---|
| `FOLDER_PATH` | `./images` | Folder containing images |
| `OUTPUT_CSV` | `metadata_vlm.csv` | Output CSV file |
| `OLLAMA_URL` | *(auto-detect)* | Ollama base URL |
| `MODEL_NAME` | `llama3.2-vision:11b` | Vision model to use |

All options can also be set via CLI flags — run `python3 vlm_metadata_export.py --help`.

---

## Troubleshooting

### "address already in use" when running `ollama serve`

Ollama is already running as a systemd service. Don't start it manually — use:

```bash
sudo systemctl status ollama   # Check status
sudo systemctl restart ollama  # Restart
```

### Connection refused from JupyterLab / Docker

1. Check Ollama is listening on all interfaces (not just 127.0.0.1):
   ```bash
   ss -tlnp | grep 11434
   # Should show *:11434 or 0.0.0.0:11434, NOT 127.0.0.1:11434
   ```

2. If it shows `127.0.0.1:11434`, run the systemd override step in the manual section above.

3. Check the iptables rule is in place:
   ```bash
   sudo iptables -L INPUT -n | grep 11434
   ```

4. From inside the container, find the correct gateway IP:
   ```bash
   ip route | grep default
   # Use the gateway IP shown, e.g. 172.17.0.1
   ```

5. Run the connectivity test:
   ```bash
   python3 test_connection.py
   ```

### Model not found

```bash
ollama list                        # List downloaded models
ollama pull llama3.2-vision:11b    # Download the model
```

### GPU not detected

**AMD:**
```bash
rocminfo | grep -i gpu             # Should list AMD GPU
ls /opt/rocm                       # ROCm installation directory
```

**NVIDIA:**
```bash
nvidia-smi                         # Should show GPU info
```

If no GPU is detected, Ollama will run in CPU mode (slower but functional).

### Ollama service won't start

```bash
journalctl -u ollama -n 50 --no-pager    # View recent logs
sudo systemctl status ollama              # Check service status
```

---

## Upgrading to a Larger Model

The AMD MI300X with 192 GB VRAM can handle 72B parameter models:

```bash
ollama pull qwen2.5vl:72b

# Then use it in the export script:
python3 vlm_metadata_export.py --model qwen2.5vl:72b
```

---

## Repository Files

| File | Description |
|---|---|
| `setup.sh` | Automated setup script |
| `vlm_metadata_export.py` | Bulk image metadata export to CSV |
| `test_connection.py` | Ollama connectivity test |
| `README.md` | This documentation |
| `.gitignore` | Ignores output CSVs, temp files, etc. |
