#!/usr/bin/env bash
# ==========================================================
#  BashBard Installer (fixed)
#  AI Assistant for Shell Automation and Command Correction
#  Author: Khafagy | Co-Developer: Naggar
#  Maintainer of this fix: (installer rewrite)
#  License: Apache 2.0
# ==========================================================

# --- Re-exec with Bash if invoked by sh/dash/etc. ---
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

umask 022

REPO_URL="https://github.com/5afagy/BashBard.git"
TMP_DIR="$(mktemp -d -t bashbard-install-XXXXXX)"

# --- Colors ---
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[1;31m'
CYAN=$'\033[1;36m'
RESET=$'\033[0m'

# --- Helper functions ---
info()    { echo -e "${CYAN}➡${RESET} $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET} $*"; }
error()   { echo -e "${RED}❌${RESET} $*" >&2; exit 1; }
success() { echo -e "${GREEN}✅${RESET} $*"; }

cleanup() {
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}
trap cleanup EXIT

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
  3. Prompt for your Gemini API key (optional)
  4. Configure .env automatically
  5. Create the BashBard launcher (and a lowercase alias)
USAGE
}

MODE="${1:-user}"
case "$MODE" in
  user|system) ;;
  -h|--help|help) usage; exit 0 ;;
  *) warn "Unknown mode '$MODE' — defaulting to 'user'"; MODE="user" ;;
esac

# --- Pre-flight checks ---
command -v git >/dev/null 2>&1 || error "git not found. Please install git."
PY="${PYTHON:-python3}"
command -v "$PY" >/dev/null 2>&1 || error "Python 3 not found. Please install it first."
command -v "$PY" >/dev/null 2>&1 || error "pip not found for $PY. Try: $PY -m ensurepip --upgrade"

info "Using Python: $("$PY" -c 'import sys; print(sys.executable)')"
info "Pip version:  $("$PY" -m pip --version || echo 'unknown')"

# --- Clone repository ---
info "Downloading BashBard from GitHub..."
git clone --depth=1 "$REPO_URL" "$TMP_DIR" >/dev/null 2>&1 || error "Failed to clone repository."
SRC_DIR="$TMP_DIR"

# Allow either layout: repo root has package dir "BashBard"
[[ -d "$SRC_DIR/BashBard" ]] || error "Repository structure invalid (missing BashBard/ directory)."

# --- Install paths ---
if [[ "$MODE" == "system" ]]; then
  INSTALL_ROOT="/usr/local/share/bashbard"
  BIN_DIR="/usr/local/bin"
  SUDO="sudo"
  PIP_USER_FLAG=()   # system-wide install
else
  INSTALL_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/bashbard"
  BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
  SUDO=""
  PIP_USER_FLAG=(--user)
fi

BIN_PATH="$BIN_DIR/BashBard"
BIN_PATH_LOWER="$BIN_DIR/bashbard"

# --- Create install dirs and copy files ---
info "Installing BashBard package to: $INSTALL_ROOT"
$SUDO mkdir -p "$INSTALL_ROOT"
$SUDO rm -rf "$INSTALL_ROOT/BashBard"
$SUDO cp -a "$SRC_DIR/BashBard" "$INSTALL_ROOT/"

# --- Dependencies ---
REQ_FILE="$SRC_DIR/requirements.txt"
if [[ -f "$REQ_FILE" ]]; then
  info "Installing dependencies from requirements.txt..."
  set +e
  if [[ "$MODE" == "system" ]]; then
    $SUDO "$PY" -m pip install -r "$REQ_FILE" --no-warn-script-location
  else
    "$PY" -m pip install "${PIP_USER_FLAG[@]}" -r "$REQ_FILE" --no-warn-script-location
  fi
  DEP_STATUS=$?
  set -e
  if [[ $DEP_STATUS -ne 0 ]]; then
    warn "Some dependencies failed or had version conflicts; continuing..."
  fi
else
  warn "No requirements.txt found — skipping dependency install."
fi

# --- .env setup ---
ENV_PATH="$INSTALL_ROOT/.env"
info "Configuring BashBard environment..."

if [[ ! -f "$ENV_PATH" ]]; then
  $SUDO bash -c "cat > '$ENV_PATH' <<'EOF'
# Agentic BashBard environment configuration
# Automatically generated during installation

# LLM provider: \"openai\" or \"google\"
LLM_PROVIDER=google

# Google Generative AI settings (used when LLM_PROVIDER=google)
GOOGLE_API_KEY=
GOOGLE_MODEL=gemini-2.5-flash-lite

# If set to 1, commands are not executed (dry-run)
DRY_RUN=0
EOF"
  success "Created .env at $ENV_PATH"
else
  warn ".env already exists — keeping existing values."
fi

# --- Request Gemini API key (only if interactive) ---
if [[ -t 0 && -t 1 ]]; then
  echo ""
  read -rp "🔑 Enter your Google Gemini API key (or press Enter to skip): " GEMINI_KEY || true
  if [[ -n "${GEMINI_KEY:-}" ]]; then
    # Use env-safe edit
    $SUDO awk -v key="$GEMINI_KEY" '
      BEGIN {done=0}
      /^GOOGLE_API_KEY=/ {print "GOOGLE_API_KEY=" key; done=1; next}
      {print}
      END {if (!done) print "GOOGLE_API_KEY=" key}
    ' "$ENV_PATH" | $SUDO tee "$ENV_PATH.tmp" >/dev/null
    $SUDO mv "$ENV_PATH.tmp" "$ENV_PATH"
    success "Gemini API key saved to $ENV_PATH"
  else
    warn "No API key entered. You can edit $ENV_PATH later."
  fi
else
  warn "Non-interactive shell detected, skipping API key prompt. Edit $ENV_PATH later."
fi

# --- Launcher creation ---
LAUNCHER='#!/usr/bin/env bash
set -euo pipefail
PKG_PARENT="__PKG_PARENT__"
# Ensure the package directory is importable
if [[ -n "${PYTHONPATH:-}" ]]; then
  export PYTHONPATH="$PKG_PARENT:$PYTHONPATH"
else
  export PYTHONPATH="$PKG_PARENT"
fi
exec /usr/bin/env python3 -m BashBard "$@"'

info "Creating launcher(s) in: $BIN_DIR"
$SUDO mkdir -p "$BIN_DIR"

# Main launcher (Capitalized)
printf '%s\n' "${LAUNCHER/__PKG_PARENT__/$INSTALL_ROOT}" | $SUDO tee "$BIN_PATH" >/dev/null
$SUDO chmod 0755 "$BIN_PATH"

# Convenience lowercase symlink (or wrapper if symlinks not allowed)
if $SUDO ln -sf "BashBard" "$BIN_PATH_LOWER" 2>/dev/null; then
  :
else
  # Fallback wrapper
  $SUDO bash -c "cat > '$BIN_PATH_LOWER' <<'EOW'
#!/usr/bin/env bash
exec BashBard \"\$@\"
EOW"
  $SUDO chmod 0755 "$BIN_PATH_LOWER"
fi

# --- PATH check (user mode only) ---
if [[ "$MODE" != "system" ]]; then
  # Update PATH for current session
  case ":$PATH:" in
    *":$BIN_DIR:"*) : ;;
    *) export PATH="$BIN_DIR:$PATH"; success "Added $BIN_DIR to PATH for this session." ;;
  esac

  # Persist in common shells
  persist_line='export PATH="$HOME/.local/bin:$PATH"'
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$rc" ]]; then
      if ! grep -qs 'export PATH="$HOME/.local/bin:$PATH"' "$rc"; then
        echo "$persist_line" >> "$rc"
        success "Added ~/.local/bin to PATH in $rc"
      fi
    else
      # create minimal rc if none exists
      echo "$persist_line" >> "$rc" 2>/dev/null || true
    fi
  done
fi

# --- Verification hints ---
echo ""
success "BashBard installed successfully!"
echo -e "${CYAN}💡 Try running:${RESET}  BashBard --help"
echo -e "${CYAN}💡 Or lowercase:${RESET}  bashbard --help"
echo ""
success "Installation complete."
