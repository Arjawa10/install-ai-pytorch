#!/usr/bin/env bash
# =============================================================================
# setup.sh — Automated Ollama + Vision LLM + OpenClaw setup for VPS
# =============================================================================
# Usage:
#   bash setup.sh                          # Interactive setup
#   bash setup.sh --non-interactive        # Ollama only (no prompts)
#   bash setup.sh --with-openclaw          # Non-interactive full setup
#   bash setup.sh --help                   # Show usage information
# =============================================================================

set -euo pipefail

# ─── Colour helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'  # No Colour

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${NC}\n"; }

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}Usage:${NC} bash setup.sh [OPTIONS]

Automated setup script for Ollama + Vision LLM + OpenClaw AI
on a VPS with AMD GPU (ROCm) or NVIDIA GPU (CUDA).

${BOLD}Options:${NC}
  --help, -h          Show this help message and exit
  --non-interactive   Skip interactive prompts. Installs Ollama + default model only.
  --with-openclaw     Non-interactive full setup (Ollama + all models + OpenClaw).

${BOLD}Setup Modes (interactive):${NC}
  1) Ollama + Vision LLM only
  2) OpenClaw only (requires Ollama already running)
  3) Full setup (Ollama + OpenClaw + all models)

${BOLD}Models:${NC}
  - qwen2.5vl:72b     Default vision model for JupyterLab (~47 GB)
  - qwen3.5:122b      Primary model for chat, coding, agents (~81 GB)

${BOLD}What this script does:${NC}
  1.  Checks root/sudo access
  2.  Detects GPU type (AMD ROCm / NVIDIA CUDA)
  3.  Installs Ollama and configures systemd + iptables
  4.  Pulls selected AI models
  5.  Installs Python dependencies
  6.  (Optional) Installs Node.js + OpenClaw
  7.  (Optional) Configures OpenClaw to use local Ollama models
  8.  Runs verification tests

${BOLD}Requirements:${NC}
  - Ubuntu/Debian-based Linux
  - AMD GPU with ROCm installed, OR NVIDIA GPU with CUDA installed
  - Internet access (to download Ollama, models, and OpenClaw)

${BOLD}Examples:${NC}
  bash setup.sh
  bash setup.sh --non-interactive
  bash setup.sh --with-openclaw
  bash setup.sh --help
EOF
    exit 0
}

# ─── Argument parsing ─────────────────────────────────────────────────────────
NON_INTERACTIVE=false
WITH_OPENCLAW=false
for arg in "$@"; do
    case "${arg}" in
        --help|-h)            usage ;;
        --non-interactive)    NON_INTERACTIVE=true ;;
        --with-openclaw)      NON_INTERACTIVE=true; WITH_OPENCLAW=true ;;
        *)                    warn "Unknown argument: ${arg}" ;;
    esac
done

# ─── Setup mode selection ─────────────────────────────────────────────────────
# Modes: 1=Ollama only, 2=OpenClaw only, 3=Full (Ollama+OpenClaw)
SETUP_MODE=1
INSTALL_OLLAMA=true
INSTALL_OPENCLAW=false

if [[ "${WITH_OPENCLAW}" == "true" ]]; then
    SETUP_MODE=3
    INSTALL_OPENCLAW=true
elif [[ "${NON_INTERACTIVE}" == "false" ]]; then
    header "Setup Mode"
    echo -e "  ${BOLD}1)${NC} Ollama + Vision LLM only"
    echo -e "  ${BOLD}2)${NC} OpenClaw only (requires Ollama already running)"
    echo -e "  ${BOLD}3)${NC} Full setup (Ollama + OpenClaw + all models)"
    echo ""
    read -rp "$(echo -e "${YELLOW}[?]${NC} Enter choice [1/2/3] (default: 1): ")" SETUP_MODE
    SETUP_MODE="${SETUP_MODE:-1}"
fi

case "${SETUP_MODE}" in
    1)  INSTALL_OLLAMA=true;  INSTALL_OPENCLAW=false ;;
    2)  INSTALL_OLLAMA=false; INSTALL_OPENCLAW=true ;;
    3)  INSTALL_OLLAMA=true;  INSTALL_OPENCLAW=true ;;
    *)  warn "Invalid choice '${SETUP_MODE}', defaulting to mode 1"
        SETUP_MODE=1; INSTALL_OLLAMA=true; INSTALL_OPENCLAW=false ;;
esac

info "Setup mode: ${SETUP_MODE} (Ollama=${INSTALL_OLLAMA}, OpenClaw=${INSTALL_OPENCLAW})"

# ─── Model selection ──────────────────────────────────────────────────────────
VISION_MODEL="qwen2.5vl:72b"
PRIMARY_MODEL="qwen3.5:122b"
INSTALL_VISION=true
INSTALL_PRIMARY=false

if [[ "${INSTALL_OLLAMA}" == "true" ]]; then
    if [[ "${WITH_OPENCLAW}" == "true" ]]; then
        # Non-interactive full mode: install both
        INSTALL_VISION=true
        INSTALL_PRIMARY=true
    elif [[ "${NON_INTERACTIVE}" == "true" ]]; then
        # Non-interactive Ollama-only: just vision model
        INSTALL_VISION=true
        INSTALL_PRIMARY=false
    else
        header "Model Selection"
        echo -e "  ${BOLD}1)${NC} ${VISION_MODEL} only (~47 GB) — vision / JupyterLab"
        echo -e "  ${BOLD}2)${NC} ${PRIMARY_MODEL} only (~81 GB) — chat, coding, agent, vision"
        echo -e "  ${BOLD}3)${NC} Both models (~128 GB) — recommended for full AI stack"
        echo ""
        read -rp "$(echo -e "${YELLOW}[?]${NC} Enter choice [1/2/3] (default: 1): ")" MODEL_CHOICE
        MODEL_CHOICE="${MODEL_CHOICE:-1}"
        case "${MODEL_CHOICE}" in
            1)  INSTALL_VISION=true;  INSTALL_PRIMARY=false ;;
            2)  INSTALL_VISION=false; INSTALL_PRIMARY=true ;;
            3)  INSTALL_VISION=true;  INSTALL_PRIMARY=true ;;
            *)  warn "Invalid choice, defaulting to vision model only"
                INSTALL_VISION=true; INSTALL_PRIMARY=false ;;
        esac
    fi

    # If mode 3 (full), default to installing primary model for OpenClaw
    if [[ "${SETUP_MODE}" == "3" && "${INSTALL_PRIMARY}" == "false" ]]; then
        INSTALL_PRIMARY=true
        info "Full setup mode — enabling ${PRIMARY_MODEL} for OpenClaw"
    fi
fi

# ─── Root / sudo check ────────────────────────────────────────────────────────
header "Checking privileges"
if [[ $EUID -eq 0 ]]; then
    SUDO=""
    success "Running as root"
else
    if command -v sudo &>/dev/null; then
        SUDO="sudo"
        success "sudo available — will use sudo for privileged commands"
    else
        error "This script must be run as root or with sudo available."
        exit 1
    fi
fi

# ─── GPU detection ────────────────────────────────────────────────────────────
header "Detecting GPU"
GPU_TYPE="unknown"

if command -v rocminfo &>/dev/null || ls /opt/rocm &>/dev/null 2>&1; then
    GPU_TYPE="amd"
    ROCM_VERSION=$(cat /opt/rocm/.info/version 2>/dev/null \
        || rocminfo 2>/dev/null | grep -oP 'ROCm \K[\d.]+' | head -1 \
        || echo "unknown")
    success "AMD GPU detected — ROCm version: ${ROCM_VERSION}"
elif command -v nvidia-smi &>/dev/null; then
    GPU_TYPE="nvidia"
    CUDA_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo "unknown")
    success "NVIDIA GPU detected — driver: ${CUDA_VERSION}"
else
    warn "No GPU detected (ROCm or NVIDIA). Ollama will run in CPU mode."
    GPU_TYPE="cpu"
fi

# ==============================================================================
# OLLAMA SETUP (modes 1 and 3)
# ==============================================================================
if [[ "${INSTALL_OLLAMA}" == "true" ]]; then

# ─── Install Ollama ───────────────────────────────────────────────────────────
header "Installing Ollama"
if command -v ollama &>/dev/null; then
    OLLAMA_VER=$(ollama --version 2>/dev/null || echo "unknown")
    success "Ollama already installed: ${OLLAMA_VER}"
else
    info "Downloading and installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
    success "Ollama installed successfully"
fi

# ─── Configure systemd service ────────────────────────────────────────────────
header "Configuring Ollama systemd service"

OLLAMA_SERVICE="/etc/systemd/system/ollama.service"

configure_systemd() {
    if [[ ! -f "${OLLAMA_SERVICE}" ]]; then
        warn "Ollama systemd service file not found at ${OLLAMA_SERVICE}"
        warn "Skipping systemd configuration."
        return 0
    fi

    if grep -q 'OLLAMA_HOST=0.0.0.0:11434' "${OLLAMA_SERVICE}" 2>/dev/null; then
        success "OLLAMA_HOST already configured in systemd service"
        return 0
    fi

    info "Setting OLLAMA_HOST=0.0.0.0:11434 in systemd service..."
    OVERRIDE_DIR="/etc/systemd/system/ollama.service.d"
    $SUDO mkdir -p "${OVERRIDE_DIR}"
    $SUDO tee "${OVERRIDE_DIR}/ollama-host.conf" > /dev/null <<'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF
    success "Systemd override created at ${OVERRIDE_DIR}/ollama-host.conf"
    $SUDO systemctl daemon-reload
    success "systemd daemon reloaded"
}

configure_systemd

# ─── Restart / start Ollama service ──────────────────────────────────────────
header "Starting Ollama service"

if systemctl is-active --quiet ollama 2>/dev/null; then
    info "Ollama service is running — restarting to apply configuration..."
    $SUDO systemctl restart ollama
    success "Ollama service restarted"
elif systemctl is-enabled --quiet ollama 2>/dev/null; then
    info "Starting Ollama systemd service..."
    $SUDO systemctl start ollama
    success "Ollama service started"
else
    warn "Ollama systemd service is not enabled."
    info "Attempting to enable and start the Ollama service..."
    $SUDO systemctl enable ollama 2>/dev/null || true
    $SUDO systemctl start ollama 2>/dev/null || true

    if ! systemctl is-active --quiet ollama 2>/dev/null; then
        warn "Systemd service could not be started. Starting Ollama manually..."
        OLLAMA_HOST=0.0.0.0:11434 nohup ollama serve &>/var/log/ollama.log &
        success "Ollama started manually (PID: $!, logs: /var/log/ollama.log)"
    fi
fi

# Wait for Ollama to be ready
info "Waiting for Ollama to be ready..."
for i in {1..15}; do
    if curl -sf http://localhost:11434/api/tags &>/dev/null; then
        success "Ollama is responding on port 11434"
        break
    fi
    if [[ $i -eq 15 ]]; then
        error "Ollama did not become ready in time. Check: journalctl -u ollama"
        exit 1
    fi
    sleep 2
done

# ─── iptables — allow Docker network access ────────────────────────────────────
header "Configuring iptables for Docker access"

DOCKER_NET="172.17.0.0/16"
OLLAMA_PORT=11434

if $SUDO iptables -C INPUT -p tcp --dport "${OLLAMA_PORT}" -s "${DOCKER_NET}" -j ACCEPT &>/dev/null 2>&1; then
    success "iptables rule for Docker → Ollama already exists"
else
    info "Adding iptables rule: Docker network (${DOCKER_NET}) → port ${OLLAMA_PORT}..."
    $SUDO iptables -I INPUT -p tcp --dport "${OLLAMA_PORT}" -s "${DOCKER_NET}" -j ACCEPT
    success "iptables rule added"

    if command -v netfilter-persistent &>/dev/null; then
        $SUDO netfilter-persistent save
        success "iptables rules persisted via netfilter-persistent"
    elif command -v iptables-save &>/dev/null; then
        IPTABLES_RULES_FILE="/etc/iptables/rules.v4"
        if [[ -f "${IPTABLES_RULES_FILE}" ]]; then
            $SUDO iptables-save | $SUDO tee "${IPTABLES_RULES_FILE}" > /dev/null
            success "iptables rules saved to ${IPTABLES_RULES_FILE}"
        else
            warn "iptables-persistent not installed — rules will be lost on reboot."
            warn "Install with: sudo apt-get install iptables-persistent"
        fi
    fi
fi

# ─── Pull AI models ──────────────────────────────────────────────────────────
header "Pulling AI models"

pull_model() {
    local model="$1"
    local label="$2"
    if ollama list 2>/dev/null | grep -q "${model%:*}"; then
        success "Model ${model} already available (${label})"
    else
        info "Pulling ${model} — ${label} (this may take a while)..."
        ollama pull "${model}"
        success "Model ${model} downloaded"
    fi
}

if [[ "${INSTALL_VISION}" == "true" ]]; then
    pull_model "${VISION_MODEL}" "vision / JupyterLab"
fi

if [[ "${INSTALL_PRIMARY}" == "true" ]]; then
    pull_model "${PRIMARY_MODEL}" "chat, coding, agent"
fi

# ─── Python dependencies ──────────────────────────────────────────────────────
header "Installing Python dependencies"

PIP_CMD=""
if command -v pip3 &>/dev/null; then
    PIP_CMD="pip3"
elif command -v pip &>/dev/null; then
    PIP_CMD="pip"
else
    warn "pip not found — skipping Python dependency installation."
    warn "Install manually: pip install Pillow requests pandas"
fi

if [[ -n "${PIP_CMD}" ]]; then
    info "Installing Pillow, requests, pandas..."

    if ${PIP_CMD} install --quiet --upgrade Pillow requests pandas 2>/dev/null; then
        success "Python dependencies installed (system pip)"
    else
        warn "System pip blocked (externally-managed-environment). Using virtual environment..."

        # Auto-install python3-venv if not available
        if ! python3 -c "import venv" &>/dev/null; then
            PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "3")
            info "python3-venv not found. Installing python${PY_VER}-venv..."
            if command -v apt-get &>/dev/null; then
                $SUDO apt-get update -qq
                $SUDO apt-get install -y -qq "python${PY_VER}-venv" || $SUDO apt-get install -y -qq python3-venv
                success "python3-venv installed"
            else
                warn "Cannot auto-install python3-venv (apt-get not found)."
                warn "Install manually: sudo apt install python3-venv"
            fi
        fi

        if python3 -c "import venv" &>/dev/null; then
            VENV_DIR="${HOME}/ollama-venv"
            python3 -m venv "${VENV_DIR}"
            "${VENV_DIR}/bin/pip" install --quiet --upgrade Pillow requests pandas
            success "Python dependencies installed in venv: ${VENV_DIR}"

            SCRIPT_DIR="$(dirname "$(realpath "$0")")"
            for script in vlm_metadata_export.py test_connection.py; do
                if [[ -f "${SCRIPT_DIR}/${script}" ]]; then
                    sed -i "1s|.*|#!${VENV_DIR}/bin/python3|" "${SCRIPT_DIR}/${script}"
                    chmod +x "${SCRIPT_DIR}/${script}"
                    info "Patched shebang → ${script}"
                fi
            done
            info "Run scripts with: ${VENV_DIR}/bin/python3 vlm_metadata_export.py ..."
            info "Or activate venv: source ${VENV_DIR}/bin/activate"
        else
            warn "venv still unavailable after install attempt. Trying --break-system-packages..."
            if ${PIP_CMD} install --quiet --upgrade --break-system-packages Pillow requests pandas; then
                success "Python dependencies installed (--break-system-packages)"
            else
                warn "Automatic installation failed. Install manually:"
                warn "  (venv)  sudo apt install python3-venv && python3 -m venv ~/ollama-venv && ~/ollama-venv/bin/pip install Pillow requests pandas"
                warn "  (apt)   apt install python3-pillow python3-requests python3-pandas"
                warn "  (force) pip install --break-system-packages Pillow requests pandas"
            fi
        fi
    fi
fi

# ─── Verification test ────────────────────────────────────────────────────────
header "Running Ollama verification test"

# Pick the first available model for testing
VERIFY_MODEL=""
if [[ "${INSTALL_VISION}" == "true" ]]; then
    VERIFY_MODEL="${VISION_MODEL}"
elif [[ "${INSTALL_PRIMARY}" == "true" ]]; then
    VERIFY_MODEL="${PRIMARY_MODEL}"
fi

TEST_RESULT=0

if [[ -n "${VERIFY_MODEL}" ]]; then
    info "Creating a test image and querying Ollama with ${VERIFY_MODEL}..."
    TMPDIR_TEST=$(mktemp -d)
    TEST_IMAGE="${TMPDIR_TEST}/test.png"

    python3 - <<PYEOF
try:
    from PIL import Image
    img = Image.new("RGB", (64, 64), color=(128, 180, 220))
    img.save("${TEST_IMAGE}")
    print("Test image created (PIL)")
except ImportError:
    import struct, zlib
    def make_png():
        sig = b'\x89PNG\r\n\x1a\n'
        def chunk(t, d):
            c = struct.pack('>I', len(d)) + t + d
            return c + struct.pack('>I', zlib.crc32(c[4:]) & 0xffffffff)
        ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
        row  = b'\x00\xff\xff\xff'
        idat = chunk(b'IDAT', zlib.compress(row))
        iend = chunk(b'IEND', b'')
        return sig + ihdr + idat + iend
    open("${TEST_IMAGE}", "wb").write(make_png())
    print("Test image created (fallback PNG)")
PYEOF

    if python3 - <<PYEOF 2>/dev/null; then
import base64, json, requests, sys

with open("${TEST_IMAGE}", "rb") as f:
    img_b64 = base64.b64encode(f.read()).decode()

try:
    r = requests.post(
        "http://localhost:11434/api/generate",
        json={
            "model": "${VERIFY_MODEL}",
            "prompt": "Describe this image in one sentence.",
            "images": [img_b64],
            "stream": False,
            "options": {"temperature": 0.1, "num_predict": 50},
        },
        timeout=120,
    )
    r.raise_for_status()
    response = r.json().get("response", "").strip()
    if response:
        print(f"Model response: {response[:200]}")
        sys.exit(0)
    else:
        sys.exit(1)
except Exception as e:
    print(f"Test failed: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
        success "Verification test passed — Ollama vision model is working!"
    else
        warn "Verification test failed. Ollama may still be warming up."
        warn "Try running: python3 test_connection.py"
        TEST_RESULT=1
    fi

    rm -rf "${TMPDIR_TEST}"
else
    info "No vision model installed — skipping image verification test."
fi

fi  # end INSTALL_OLLAMA

# ==============================================================================
# OPENCLAW SETUP (modes 2 and 3)
# ==============================================================================
OPENCLAW_INSTALLED=false

if [[ "${INSTALL_OPENCLAW}" == "true" ]]; then

# ─── Check Ollama is running (required for OpenClaw) ──────────────────────────
header "Checking Ollama for OpenClaw"

if ! curl -sf http://localhost:11434/api/tags &>/dev/null; then
    if [[ "${SETUP_MODE}" == "2" ]]; then
        error "Ollama is not running on localhost:11434."
        error "OpenClaw requires Ollama. Please run this script with mode 3 (full setup)"
        error "or start Ollama manually first."
        exit 1
    fi
else
    success "Ollama is running on localhost:11434"
fi

# ─── Install Node.js ──────────────────────────────────────────────────────────
header "Installing Node.js (required for OpenClaw)"

NODE_MIN_VERSION=22

check_node_version() {
    if command -v node &>/dev/null; then
        NODE_VER=$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)
        if [[ "${NODE_VER}" -ge "${NODE_MIN_VERSION}" ]] 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

if check_node_version; then
    success "Node.js $(node --version) already installed (>= ${NODE_MIN_VERSION} required)"
else
    info "Installing Node.js ${NODE_MIN_VERSION} via NodeSource..."

    # Install via NodeSource repository
    if command -v apt-get &>/dev/null; then
        $SUDO apt-get update -qq
        $SUDO apt-get install -y -qq ca-certificates curl gnupg
        $SUDO mkdir -p /etc/apt/keyrings
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | $SUDO gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true
        echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MIN_VERSION}.x nodistro main" | $SUDO tee /etc/apt/sources.list.d/nodesource.list > /dev/null
        $SUDO apt-get update -qq
        $SUDO apt-get install -y -qq nodejs
        success "Node.js installed via NodeSource"
    else
        # Fallback: install local Node.js binary
        info "apt-get not available. Installing Node.js locally..."
        NODE_INSTALL_VER="22.22.0"
        NODE_DIR="${HOME}/.openclaw/tools/node-v${NODE_INSTALL_VER}"
        NODE_TARBALL="node-v${NODE_INSTALL_VER}-linux-x64.tar.gz"
        NODE_URL="https://nodejs.org/dist/v${NODE_INSTALL_VER}/${NODE_TARBALL}"

        if [[ ! -d "${NODE_DIR}" ]]; then
            mkdir -p "${HOME}/.openclaw/tools"
            curl -fsSL "${NODE_URL}" -o "/tmp/${NODE_TARBALL}"
            tar -xzf "/tmp/${NODE_TARBALL}" -C "${HOME}/.openclaw/tools"
            mv "${HOME}/.openclaw/tools/node-v${NODE_INSTALL_VER}-linux-x64" "${NODE_DIR}"
            rm -f "/tmp/${NODE_TARBALL}"
        fi
        export PATH="${NODE_DIR}/bin:${PATH}"
        success "Node.js installed locally at ${NODE_DIR}"
    fi

    if check_node_version; then
        success "Node.js $(node --version) is ready"
    else
        error "Failed to install Node.js >= ${NODE_MIN_VERSION}. Cannot install OpenClaw."
        error "Install manually: https://nodejs.org/en/download/"
        INSTALL_OPENCLAW=false
    fi
fi

# ─── Install OpenClaw ─────────────────────────────────────────────────────────
if [[ "${INSTALL_OPENCLAW}" == "true" ]]; then

header "Installing OpenClaw"

if command -v openclaw &>/dev/null; then
    OPENCLAW_VER=$(openclaw --version 2>/dev/null || echo "installed")
    success "OpenClaw already installed: ${OPENCLAW_VER}"
    OPENCLAW_INSTALLED=true
else
    info "Installing OpenClaw via official installer..."
    if curl -fsSL https://openclaw.ai/install.sh | bash; then
        success "OpenClaw installed successfully"
        OPENCLAW_INSTALLED=true
    else
        warn "Official installer failed. Trying npm install..."
        if command -v npm &>/dev/null; then
            SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest
            success "OpenClaw installed via npm"
            OPENCLAW_INSTALLED=true
        else
            error "Failed to install OpenClaw. Install manually: npm install -g openclaw@latest"
        fi
    fi
fi

# ─── Configure OpenClaw → Ollama ──────────────────────────────────────────────
if [[ "${OPENCLAW_INSTALLED}" == "true" ]]; then

header "Configuring OpenClaw → Ollama"

OPENCLAW_CONFIG_DIR="${HOME}/.openclaw"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG_DIR}/openclaw.json"

# Determine which model OpenClaw should use
OPENCLAW_MODEL="${PRIMARY_MODEL}"
if [[ "${INSTALL_PRIMARY}" != "true" ]]; then
    OPENCLAW_MODEL="${VISION_MODEL}"
    warn "Primary model (${PRIMARY_MODEL}) not installed. Using ${VISION_MODEL} for OpenClaw."
fi

if [[ -f "${OPENCLAW_CONFIG}" ]]; then
    warn "OpenClaw config already exists at ${OPENCLAW_CONFIG}"
    info "Backing up existing config..."
    cp "${OPENCLAW_CONFIG}" "${OPENCLAW_CONFIG}.bak.$(date +%s)"
fi

# Build models array based on what was installed
MODELS_ARRAY="{\"id\": \"${OPENCLAW_MODEL}\", \"name\": \"${OPENCLAW_MODEL}\"}"
if [[ "${INSTALL_VISION}" == "true" && "${INSTALL_PRIMARY}" == "true" ]]; then
    MODELS_ARRAY="{\"id\": \"${PRIMARY_MODEL}\", \"name\": \"${PRIMARY_MODEL}\"}, {\"id\": \"${VISION_MODEL}\", \"name\": \"${VISION_MODEL}\"}"
fi

# Generate a random auth token for the gateway
OPENCLAW_TOKEN=$(openssl rand -hex 24 2>/dev/null || head -c 48 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 48)
info "Generated gateway auth token: ${OPENCLAW_TOKEN}"

# Detect server IP for allowedOrigins
SERVER_IP=$(curl -sf https://ifconfig.me 2>/dev/null || curl -sf https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}' || echo "0.0.0.0")

cat > "${OPENCLAW_CONFIG}" <<OCEOF
{
  "models": {
    "providers": {
      "ollama": {
        "baseUrl": "http://localhost:11434",
        "apiKey": "ollama-local",
        "api": "ollama",
        "models": [${MODELS_ARRAY}]
      }
    }
  },
  "gateway": {
    "mode": "local",
    "bind": "0.0.0.0",
    "controlUi": {
      "allowedOrigins": [
        "http://${SERVER_IP}:18789",
        "https://${SERVER_IP}:18789",
        "http://${SERVER_IP}"
      ]
    },
    "auth": {
      "mode": "token",
      "token": "${OPENCLAW_TOKEN}"
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "ollama/${OPENCLAW_MODEL}" },
      "memorySearch": { "enabled": false }
    }
  }
}
OCEOF

success "OpenClaw config created at ${OPENCLAW_CONFIG}"
info "Primary model for OpenClaw: ollama/${OPENCLAW_MODEL}"
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║  OpenClaw Gateway Token (SAVE THIS!)                     ║${NC}"
echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${CYAN}║${NC}  ${YELLOW}${OPENCLAW_TOKEN}${NC}  ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ─── Onboard & start OpenClaw Gateway ─────────────────────────────────────────
header "Starting OpenClaw Gateway"

info "Running OpenClaw onboard with daemon install..."
if openclaw onboard --install-daemon 2>/dev/null; then
    success "OpenClaw daemon installed and onboarded"
else
    warn "Onboard command had issues. Trying to start gateway manually..."
fi

# Start gateway with proper binding
info "Starting gateway with bind 0.0.0.0..."
if pgrep -f "openclaw-gateway" > /dev/null 2>&1; then
    info "Stopping existing gateway process..."
    pkill -f "openclaw-gateway" 2>/dev/null || true
    sleep 2
fi

nohup openclaw gateway --port 18789 > /var/log/openclaw-gateway.log 2>&1 &
GATEWAY_PID=$!
info "Gateway started (PID: ${GATEWAY_PID}, logs: /var/log/openclaw-gateway.log)"

# Wait and verify gateway is running
sleep 5
if pgrep -f "openclaw-gateway" > /dev/null 2>&1; then
    # Check if gateway is binding correctly
    GATEWAY_BIND=$(ss -tlnp | grep -E "18789|openclaw" | head -1 || echo "unknown")
    success "OpenClaw Gateway is running"
    info "Gateway binding: ${GATEWAY_BIND}"
else
    warn "OpenClaw Gateway may not be running. Start manually with:"
    warn "  openclaw gateway --port 18789"
    warn "Check logs: cat /var/log/openclaw-gateway.log"
fi

fi  # end OPENCLAW_INSTALLED
fi  # end INSTALL_OPENCLAW check
fi  # end INSTALL_OPENCLAW

# ==============================================================================
# SUMMARY
# ==============================================================================
header "Setup Complete — Summary"

# Build models list string
MODELS_INSTALLED=""
if [[ "${INSTALL_OLLAMA}" == "true" ]]; then
    if [[ "${INSTALL_VISION}" == "true" ]]; then
        MODELS_INSTALLED="${VISION_MODEL} (vision)"
    fi
    if [[ "${INSTALL_PRIMARY}" == "true" ]]; then
        if [[ -n "${MODELS_INSTALLED}" ]]; then
            MODELS_INSTALLED="${MODELS_INSTALLED}, ${PRIMARY_MODEL} (primary)"
        else
            MODELS_INSTALLED="${PRIMARY_MODEL} (primary)"
        fi
    fi
fi

cat <<EOF
${GREEN}${BOLD}Installation Summary${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  GPU type        : ${GPU_TYPE}
  Setup mode      : ${SETUP_MODE}
EOF

if [[ "${INSTALL_OLLAMA}" == "true" ]]; then
cat <<EOF
  Ollama          : $(ollama --version 2>/dev/null || echo "installed")
  Models          : ${MODELS_INSTALLED:-none}
  Ollama binding  : 0.0.0.0:11434 (accessible from Docker)
  iptables rule   : Docker (172.17.0.0/16) → port 11434 ✅
EOF
fi

if [[ "${OPENCLAW_INSTALLED}" == "true" ]]; then
cat <<EOF
  OpenClaw        : $(openclaw --version 2>/dev/null || echo "installed")
  OpenClaw config : ~/.openclaw/openclaw.json
  OpenClaw model  : ollama/${OPENCLAW_MODEL:-${PRIMARY_MODEL}}
  Gateway bind    : 0.0.0.0:18789 (accessible from outside)
  Gateway token   : ${OPENCLAW_TOKEN:-<check ~/.openclaw/openclaw.json>}
  Dashboard       : http://${SERVER_IP:-<your-server-ip>}:18789/
EOF
fi

echo ""

if [[ "${INSTALL_OLLAMA}" == "true" ]]; then
cat <<EOF
${BOLD}Ollama Commands:${NC}
  From VPS host:        curl http://localhost:11434/api/tags
  From Docker/Jupyter:  curl http://172.17.0.1:11434/api/tags
  Test connectivity:    python3 test_connection.py
  Metadata export:      python3 vlm_metadata_export.py --folder /path/to/images --output metadata.csv
EOF
fi

if [[ "${OPENCLAW_INSTALLED}" == "true" ]]; then
cat <<EOF

${BOLD}OpenClaw Commands:${NC}
  Gateway status:       openclaw gateway status
  Open dashboard:       openclaw dashboard
  Start gateway:        openclaw gateway --port 18789
  SSH tunnel (remote):  ssh -N -L 18789:127.0.0.1:18789 user@your-vps-ip
EOF
fi

echo ""
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "${INSTALL_OLLAMA}" == "true" && ${TEST_RESULT:-0} -ne 0 ]]; then
    echo -e "${YELLOW}⚠ The Ollama verification test did not pass. See test_connection.py for debugging.${NC}"
fi

echo ""
success "Setup complete! 🚀"
