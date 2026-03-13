# install-ai-pytorch

Automated VPS AI setup for **Ollama + Vision LLM + OpenClaw** on AMD GPU (ROCm) or NVIDIA GPU (CUDA).

---

## What this repo does

- Installs and configures [Ollama](https://ollama.com/) on a fresh VPS
- Configures Ollama to be accessible from Docker containers / JupyterLab
- Sets up firewall rules so Docker containers can reach Ollama
- Pulls AI models (vision + chat/coding/agent)
- Optionally installs [OpenClaw](https://openclaw.ai/) AI assistant with local Ollama integration
- Auto-generates gateway auth token and configures secure access
- Provides a Python script to bulk-export image metadata to CSV using a vision LLM
- Provides a connectivity test script useful from JupyterLab or Docker

---

## Models

| Model | Size | Purpose |
|---|---|---|
| `qwen2.5vl:72b` | ~47 GB | Vision processing (JupyterLab, metadata export) |
| `qwen3.5:122b` | ~81 GB | Chat, coding, automation, agents (OpenClaw) |

All models are **free and open-source**.

---

## Prerequisites

| Requirement | Details |
|---|---|
| OS | Ubuntu 20.04+ / Debian 11+ |
| GPU | AMD MI-series with ROCm **or** NVIDIA GPU with CUDA |
| RAM / VRAM | ≥ 48 GB VRAM for vision model, ≥ 128 GB for both models |
| Internet | Required to download Ollama, models, and OpenClaw |
| Python | Python 3.8+ with `pip` |

> **Tested on:** AMD MI300X (192 GB VRAM) with ROCm 7.0

---

## Quick Start

```bash
git clone https://github.com/Arjawa10/install-ai-pytorch.git
cd install-ai-pytorch
bash setup.sh
```

The script will prompt you to choose:

1. **Setup Mode** — Ollama only / OpenClaw only / Full setup
2. **Model Selection** — Vision model / Primary model / Both

### Non-interactive modes

```bash
# Ollama + default vision model only
bash setup.sh --non-interactive

# Full setup: Ollama + all models + OpenClaw
bash setup.sh --with-openclaw
```

---

## Setup Modes

### Mode 1: Ollama + Vision LLM

Installs Ollama, configures for Docker access, and pulls the selected model(s).

### Mode 2: OpenClaw Only

Installs OpenClaw and configures it to use an **already running** Ollama instance.

### Mode 3: Full Setup

Installs everything:
- Ollama + systemd service + iptables
- Both AI models (`qwen2.5vl:72b` + `qwen3.5:122b`)
- Node.js 22+
- OpenClaw with Ollama integration (auto-configured)
- Gateway auth token (auto-generated)
- Python dependencies

---

## Usage

### Metadata export script

```bash
# Basic usage
python3 vlm_metadata_export.py

# With CLI arguments
python3 vlm_metadata_export.py \
    --folder /path/to/images \
    --output results.csv \
    --model qwen2.5vl:72b \
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

### OpenClaw

#### Accessing the Dashboard (SSH Tunnel)

The OpenClaw Control UI requires a **secure context** (HTTPS or localhost). The easiest way to access it from your local machine is via SSH tunnel:

**Linux / macOS (OpenSSH):**
```bash
ssh -N -L 18789:127.0.0.1:18789 root@your-vps-ip
```

**Windows (PuTTY / plink):**
```powershell
plink -N -L 18789:127.0.0.1:18789 -i "C:\path\to\your-key.ppk" root@your-vps-ip
```

**Windows (OpenSSH — requires key conversion from .ppk to OpenSSH format):**
```powershell
ssh -N -L 18789:127.0.0.1:18789 -i "C:\path\to\your-key" root@your-vps-ip
```

Then open in your browser: **http://localhost:18789/**

> **Note:** If your VPS uses `.ppk` key format (PuTTY), use `plink` directly. If you want to use OpenSSH's `ssh`, convert the key first with PuTTYgen: **Conversions → Export OpenSSH key**.

#### Common OpenClaw Commands

```bash
# Check gateway status
openclaw gateway status

# Open dashboard
openclaw dashboard

# Start gateway manually
openclaw gateway --port 18789

# View gateway token
openclaw config get gateway.auth.token

# Health check
openclaw health

# Run diagnostics
openclaw doctor
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
| `MODEL_NAME` | `qwen2.5vl:72b` | Vision model to use |

All options can also be set via CLI flags — run `python3 vlm_metadata_export.py --help`.

### OpenClaw config

Located at `~/.openclaw/openclaw.json`. Auto-generated by setup script:

```json
{
  "models": {
    "providers": {
      "ollama": {
        "baseUrl": "http://localhost:11434",
        "apiKey": "ollama-local",
        "api": "ollama",
        "models": [
          { "id": "qwen3.5:122b", "name": "qwen3.5:122b" },
          { "id": "qwen2.5vl:72b", "name": "qwen2.5vl:72b" }
        ]
      }
    }
  },
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "controlUi": {
      "allowedOrigins": [
        "http://<your-server-ip>:18789",
        "https://<your-server-ip>:18789"
      ]
    },
    "auth": {
      "mode": "token",
      "token": "<auto-generated-token>"
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "ollama/qwen3.5:122b" },
      "memorySearch": { "enabled": false }
    }
  }
}
```

Key config options:

| Field | Value | Description |
|---|---|---|
| `gateway.bind` | `lan` | Binds to all LAN interfaces (0.0.0.0). Other modes: `loopback`, `tailnet`, `auto` |
| `gateway.auth.mode` | `token` | Token-based authentication |
| `gateway.auth.token` | *(auto-generated)* | 48-char hex token, use in dashboard to connect |
| `agents.defaults.model.primary` | `ollama/qwen3.5:122b` | Primary model for chat/coding |

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
ollama list                    # List downloaded models
ollama pull qwen2.5vl:72b     # Download vision model
ollama pull qwen3.5:122b      # Download primary model
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

### OpenClaw issues

#### "pairing required" error

This means the dashboard is trying to pair with the gateway. Approve it via CLI:
```bash
openclaw devices list              # List pending/paired devices
openclaw devices approve           # Approve pending request
```

#### "control ui requires device identity (use HTTPS or localhost)"

The Control UI requires a **secure context**. Access via SSH tunnel:
```bash
# Linux/macOS
ssh -N -L 18789:127.0.0.1:18789 root@your-vps-ip

# Windows (PuTTY)
plink -N -L 18789:127.0.0.1:18789 -i your-key.ppk root@your-vps-ip
```
Then open `http://localhost:18789/` in your browser.

#### Gateway not accessible from outside (connection refused)

1. Check gateway binding:
   ```bash
   ss -tlnp | grep 18789
   # Should show 0.0.0.0:18789, NOT 127.0.0.1:18789
   ```

2. If binding to loopback, check config:
   ```bash
   grep bind ~/.openclaw/openclaw.json
   # Should show "bind": "lan"
   ```

3. If config shows legacy `"0.0.0.0"`, run:
   ```bash
   openclaw doctor --fix
   ```

4. Open firewall port:
   ```bash
   sudo ufw allow 18789/tcp
   sudo iptables -I INPUT -p tcp --dport 18789 -j ACCEPT
   ```

#### Gateway config validation error

```bash
openclaw doctor --fix              # Auto-fix legacy config keys
openclaw config validate           # Validate config
cat ~/.openclaw/openclaw.json      # Check config manually
```

#### General OpenClaw commands

```bash
openclaw gateway status            # Check gateway
openclaw gateway --port 18789      # Start manually
openclaw config get gateway.auth.token   # View token
openclaw health                    # Gateway health check
openclaw doctor                    # Run diagnostics
```

---

## Repository Files

| File | Description |
|---|---|
| `setup.sh` | Automated setup script (Ollama + OpenClaw) |
| `vlm_metadata_export.py` | Bulk image metadata export to CSV |
| `test_connection.py` | Ollama connectivity test |
| `README.md` | This documentation |
| `.gitignore` | Ignores output CSVs, temp files, etc. |
