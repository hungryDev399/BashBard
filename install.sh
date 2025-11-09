#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
#  BashBard Installer
#  AI Assistant for Shell Automation and Command Correction
#  Author: Khafagy | Co-Developer: Naggar
#  License: Apache 2.0
# ==========================================================

REPO_URL="https://github.com/5afagy/BashBard.git"
TMP_DIR="/tmp/bashbard-install-$$"

# --- Colors ---
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[1;36m'
RESET='\033[0m'

# --- Helpers ---
info()    { echo -e "${CYAN}➡${RESET} $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET} $*"; }
error()   { echo -e "${RED}❌${RESET} $*" >&2; exit 1; }
success() { echo -e "${GREEN}✅${RESET} $*"; }

usage() {
  cat <<'USAGE'
Usage:
  ./install.sh [user|system]

Modes:
  user   → installs to ~/.local (default)
  system → installs to /usr/local (requires sudo)

This script will:
  1. Download BashBard from GitHub
  2. Install dependencies
  3. Ask for your Gemini API key
  4. Configure your .env
  5. Create the BashBard launcher on PATH
USAGE
}

MODE="${1:-user}"

# --- Clone Repository ---
info "Downloading BashBard from GitHub..."
rm -rf "$TMP_DIR"
git clone --depth=1 "$REPO_URL" "$TMP_DIR" >/dev/null 2>&1 || error "Failed to clone repository."

SRC_DIR="$TMP_DIR"

if [[ ! -d "$SRC_DIR/BashBard" ]]; then
  error "Repository structure invalid — missing BashBard/ directory."
fi

# --- Installation Paths ---
if [[ "$MODE" == "system" ]]; then
  INSTALL_ROOT="/usr/local/share/bashbard"
  BIN_PATH="/usr/local/bin/BashBard"
  SUDO="sudo"
  PIP_PREFIX=()
else
  INSTALL_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/bashbard"
  BIN_PATH="$HOME/.local/bin/BashBard"
  SUDO=""
  PIP_PREFIX=(--user)
fi

# --- Python & Pip ---
PY="${PYTHON:-python3}"
command -v "$PY" >/dev/null 2>&1 || error "Python 3 not found. Install it first."

info "Using Python: $("$PY" -c 'import sys; print(sys.executable)')"
info "Pip version:  $("${PY}" -m pip --version)"

# --- Copy Files ---
info "Installing BashBard package to: $INSTALL_ROOT"
$SUDO mkdir -p "$INSTALL_ROOT"
$SUDO rm -rf "$INSTALL_ROOT/BashBard"
$SUDO cp -a "$SRC_DIR/BashBard" "$INSTALL_ROOT/"

# --- Install Dependencies ---
REQ_FILE="$SRC_DIR/requirements.txt"
if [[ -f "$REQ_FILE" ]]; then
  info "Installing Python dependencies..."
  if [[ "$MODE" == "system" ]]; then
    $SUDO "$PY" -m pip install -r "$REQ_FILE"
  else
    "$PY" -m pip install "${PIP_PREFIX[@]}" -r "$REQ_FILE"
  fi
else
  warn "No requirements.txt found (skipping dependency install)."
fi

# --- .env Setup ---
ENV_PATH="$INSTALL_ROOT/.env"

info "Configuring BashBard environment..."
if [[ -f "$ENV_PATH" ]]; then
  warn ".env already exists — updating API key if needed."
else
  info "Creating new .env file..."
  cat > "$ENV_PATH" <<'EOF'
# Agentic BashBard environment configuration
# Automatically generated during installation

# LLM provider: "openai" (default) or "google"
LLM_PROVIDER=google

# Google Generative AI settings (used when LLM_PROVIDER=google)
GOOGLE_API_KEY=
GOOGLE_MODEL=gemini-2.5-flash-lite

# If set to 1, commands are not executed (dry-run)
DRY_RUN=0
EOF
  success "Created .env at $ENV_PATH"
fi

# --- Request Gemini API Key ---
echo ""
read -rp "🔑 Enter your Google Gemini API key: " GEMINI_KEY
if [[ -z "$GEMINI_KEY" ]]; then
  warn "No API key entered. You can add it later in $ENV_PATH"
else
  sed -i "s|^GOOGLE_API_KEY=.*|GOOGLE_API_KEY=${GEMINI_KEY}|" "$ENV_PATH"
  success "Gemini API key added to $ENV_PATH"
fi

# --- Create Launcher ---
LAUNCHER='#!/usr/bin/env bash
set -euo pipefail
PKG_PARENT="__PKG_PARENT__"
if [[ -n "${PYTHONPATH:-}" ]]; then
  export PYTHONPATH="$PKG_PARENT:$PYTHONPATH"
else
  export PYTHONPATH="$PKG_PARENT"
fi
exec /usr/bin/env python3 -m BashBard "$@"'

info "Creating launcher: $BIN_PATH"
if [[ "$MODE" == "system" ]]; then
  echo "${LAUNCHER/__PKG_PARENT__/$INSTALL_ROOT}" | sudo tee "$BIN_PATH" >/dev/null
  sudo chmod 0755 "$BIN_PATH"
else
  mkdir -p "$(dirname "$BIN_PATH")"
  printf '%s\n' "${LAUNCHER/__PKG_PARENT__/$INSTALL_ROOT}" > "$BIN_PATH"
  chmod 0755 "$BIN_PATH"
fi

# --- Add PATH (for user installs) ---
if [[ "$MODE" != "system" ]]; then
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc" 2>/dev/null || true
    success "Added ~/.local/bin to your PATH (reload your terminal to apply)"
  fi
fi

# --- Cleanup ---
rm -rf "$TMP_DIR"

# --- Done ---
echo ""
success "BashBard installed successfully!"
echo ""
echo -e "${CYAN}💡 To start BashBard, run:${RESET}  BashBard"
echo ""
success "Installation complete."
