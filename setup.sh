#!/usr/bin/env bash
# =============================================================================
# setup.sh — Automated Ollama + Vision LLM setup for VPS (AMD ROCm / NVIDIA)
# =============================================================================
# Usage:
#   bash setup.sh           # Interactive setup
#   bash setup.sh --help    # Show usage information
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

Automated setup script for Ollama + Vision LLM (llama3.2-vision)
on a VPS with AMD GPU (ROCm) or NVIDIA GPU (CUDA).

${BOLD}Options:${NC}
  --help, -h          Show this help message and exit
  --non-interactive   Skip interactive prompts (e.g. large model download).
                      Suitable for CI/CD pipelines and automated deployments.

${BOLD}What this script does:${NC}
  1.  Checks root/sudo access
  2.  Detects GPU type (AMD ROCm / NVIDIA CUDA)
  3.  Installs Ollama if not already installed
  4.  Configures Ollama to listen on 0.0.0.0:11434 (Docker-accessible)
  5.  Sets up systemd service with correct environment variables
  6.  Configures iptables to allow Docker network (172.17.0.0/16) access
  7.  Pulls the default vision model (llama3.2-vision:11b)
  8.  Optionally pulls larger models (qwen2.5vl:72b)
  9.  Installs Python dependencies (Pillow, requests, pandas)
  10. Runs a connectivity verification test
  11. Prints a usage summary

${BOLD}Requirements:${NC}
  - Ubuntu/Debian-based Linux
  - AMD GPU with ROCm installed, OR NVIDIA GPU with CUDA installed
  - Internet access (to download Ollama and models)

${BOLD}Examples:${NC}
  bash setup.sh
  bash setup.sh --non-interactive
  bash setup.sh --help
EOF
    exit 0
}

NON_INTERACTIVE=false
for arg in "$@"; do
    case "${arg}" in
        --help|-h)            usage ;;
        --non-interactive)    NON_INTERACTIVE=true ;;
        *)                    warn "Unknown argument: ${arg}" ;;
    esac
done

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
    # Check if the service file exists (created by Ollama installer)
    if [[ ! -f "${OLLAMA_SERVICE}" ]]; then
        warn "Ollama systemd service file not found at ${OLLAMA_SERVICE}"
        warn "Ollama may not have been installed with the official installer."
        warn "Skipping systemd configuration."
        return 0
    fi

    # Check if OLLAMA_HOST is already set correctly
    if grep -q 'OLLAMA_HOST=0.0.0.0:11434' "${OLLAMA_SERVICE}" 2>/dev/null; then
        success "OLLAMA_HOST already configured in systemd service"
        return 0
    fi

    info "Setting OLLAMA_HOST=0.0.0.0:11434 in systemd service..."

    # Use a drop-in override to avoid modifying the installer-managed service file
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

    # Fallback: start manually if systemd not available / not working
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

# Check if the rule already exists
if $SUDO iptables -C INPUT -p tcp --dport "${OLLAMA_PORT}" -s "${DOCKER_NET}" -j ACCEPT &>/dev/null 2>&1; then
    success "iptables rule for Docker → Ollama already exists"
else
    info "Adding iptables rule: Docker network (${DOCKER_NET}) → port ${OLLAMA_PORT}..."
    $SUDO iptables -I INPUT -p tcp --dport "${OLLAMA_PORT}" -s "${DOCKER_NET}" -j ACCEPT
    success "iptables rule added"

    # Persist iptables rules if iptables-persistent is available
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

# ─── Pull vision model ────────────────────────────────────────────────────────
header "Pulling Vision LLM model"

DEFAULT_MODEL="llama3.2-vision:11b"

# Check if default model already exists
if ollama list 2>/dev/null | grep -q "${DEFAULT_MODEL%:*}"; then
    success "Model ${DEFAULT_MODEL} already available"
else
    info "Pulling ${DEFAULT_MODEL} (this may take several minutes)..."
    ollama pull "${DEFAULT_MODEL}"
    success "Model ${DEFAULT_MODEL} downloaded"
fi

# ─── Optional: larger model ───────────────────────────────────────────────────
LARGE_MODEL="qwen2.5vl:72b"
PULL_LARGE="n"
if [[ "${NON_INTERACTIVE}" == "false" ]]; then
    echo ""
    read -rp "$(echo -e "${YELLOW}[?]${NC} Pull larger model ${LARGE_MODEL} (requires ~144GB VRAM)? [y/N]: ")" PULL_LARGE
fi

if [[ "${PULL_LARGE,,}" == "y" || "${PULL_LARGE,,}" == "yes" ]]; then
    info "Pulling ${LARGE_MODEL} (this will take a long time)..."
    ollama pull "${LARGE_MODEL}"
    success "Model ${LARGE_MODEL} downloaded"
else
    info "Skipping ${LARGE_MODEL}"
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
    $PIP_CMD install --quiet --upgrade Pillow requests pandas
    success "Python dependencies installed"
fi

# ─── Verification test ────────────────────────────────────────────────────────
header "Running verification test"

info "Creating a test image and querying Ollama..."

TMPDIR_TEST=$(mktemp -d)
TEST_IMAGE="${TMPDIR_TEST}/test.png"
TEST_RESULT=0

# Create a small dummy PNG image (1x1 pixel, grey) using Python
python3 - <<PYEOF
try:
    from PIL import Image
    img = Image.new("RGB", (64, 64), color=(128, 180, 220))
    img.save("${TEST_IMAGE}")
    print("Test image created (PIL)")
except ImportError:
    # Fallback: write a minimal valid PNG (1x1 white pixel)
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

# Send test image to Ollama
if python3 - <<PYEOF 2>/dev/null; then
import base64, json, requests, sys

with open("${TEST_IMAGE}", "rb") as f:
    img_b64 = base64.b64encode(f.read()).decode()

try:
    r = requests.post(
        "http://localhost:11434/api/generate",
        json={
            "model": "${DEFAULT_MODEL}",
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

# ─── Summary ──────────────────────────────────────────────────────────────────
header "Setup Complete — Summary"

cat <<EOF
${GREEN}${BOLD}Installation Summary${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  GPU type        : ${GPU_TYPE}
  Ollama          : $(ollama --version 2>/dev/null || echo "installed")
  Model           : ${DEFAULT_MODEL}
  Ollama binding  : 0.0.0.0:11434 (accessible from Docker)
  iptables rule   : Docker (172.17.0.0/16) → port 11434 ✅

${BOLD}From the VPS host:${NC}
  curl http://localhost:11434/api/tags

${BOLD}From inside a Docker container / JupyterLab:${NC}
  curl http://172.17.0.1:11434/api/tags

${BOLD}Run metadata export:${NC}
  python3 vlm_metadata_export.py --folder /path/to/images --output metadata.csv

${BOLD}Test connectivity:${NC}
  python3 test_connection.py
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

if [[ ${TEST_RESULT} -ne 0 ]]; then
    echo -e "${YELLOW}⚠ The verification test did not pass. See test_connection.py for debugging.${NC}"
fi

echo ""
success "Setup complete! 🚀"
