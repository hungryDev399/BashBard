#!/usr/bin/env bash
# ==========================================================
#  BashBard Installer (first-run API prompt built into launcher)
#  - Reexecs with bash (no sh/dash syntax errors)
#  - Creates BashBard + bashbard
#  - Works immediately by placing shims in a PATH dir when possible
#  - If installer is non-interactive, launcher will prompt for API on first run
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

# --- Helpers ---
info()    { echo -e "${CYAN}➡${RESET} $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET} $*"; }
error()   { echo -e "${RED}❌${RESET} $*" >&2; exit 1; }
success() { echo -e "${GREEN}✅${RESET} $*"; }

cleanup() { [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

usage() {
  cat <<'USAGE'
Usage:
  ./install.sh [user|system]

Modes:
  user   → installs to ~/.local (default)
  system → installs to /usr/local (requires sudo)

What this does:
  1) Download BashBard
  2) Install dependencies
  3) Configure .env (prompts here if interactive)
  4) Create launchers (BashBard + bashbard)
  5) Ensure you can run it immediately (shim in PATH if possible)
  6) If API key not set at install time, the launcher will prompt the first time you run it
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
# ensure pip exists for this Python
"$PY" -m pip --version >/dev/null 2>&1 || "$PY" -m ensurepip --upgrade >/dev/null 2>&1 || true

info "Using Python: $("$PY" -c 'import sys; print(sys.executable)')"
info "Pip version:  $("$PY" -m pip --version || echo 'unknown')"

# --- Clone repository ---
info "Downloading BashBard from GitHub..."
git clone --depth=1 "$REPO_URL" "$TMP_DIR" >/dev/null 2>&1 || error "Failed to clone repository."
SRC_DIR="$TMP_DIR"
[[ -d "$SRC_DIR/BashBard" ]] || error "Repository structure invalid (missing BashBard/ directory)."

# --- Install paths ---
if [[ "$MODE" == "system" ]]; then
  INSTALL_ROOT="/usr/local/share/bashbard"
  BIN_DIR="/usr/local/bin"
  SUDO="sudo"
  PIP_USER_FLAG=()
else
  INSTALL_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/bashbard"
  BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
  SUDO=""
  PIP_USER_FLAG=(--user)
fi

BIN_MAIN="$BIN_DIR/BashBard"
BIN_LOWER="$BIN_DIR/bashbard"

# --- Copy package ---
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
  [[ $DEP_STATUS -eq 0 ]] || warn "Some dependencies failed or had version conflicts; continuing..."
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

# Optional key prompt during INSTALL (only if interactive)
if [[ -t 0 && -t 1 ]]; then
  echo ""
  read -rp "🔑 Enter your Google Gemini API key (or press Enter to skip): " GEMINI_KEY || true
  if [[ -n "${GEMINI_KEY:-}" ]]; then
    $SUDO awk -v key="$GEMINI_KEY" '
      BEGIN{done=0}
      /^GOOGLE_API_KEY=/{print "GOOGLE_API_KEY=" key; done=1; next}
      {print}
      END{if(!done) print "GOOGLE_API_KEY=" key}
    ' "$ENV_PATH" | $SUDO tee "$ENV_PATH.tmp" >/dev/null
    $SUDO mv "$ENV_PATH.tmp" "$ENV_PATH"
    success "Gemini API key saved to $ENV_PATH"
  else
    warn "No API key entered during install. The launcher will prompt on first run."
  fi
else
  warn "Non-interactive install detected. The launcher will prompt for API on first run."
fi

# --- Launcher with FIRST-RUN API prompt built-in ---
# This wrapper:
#   - ensures PYTHONPATH includes the installed package
#   - checks GOOGLE_API_KEY in $INSTALL_ROOT/.env
#   - if empty, prompts via /dev/tty (so it works even if stdin is not a TTY)
#   - saves the key back into .env and exports it for the Python module
LAUNCHER='#!/usr/bin/env bash
set -euo pipefail

PKG_PARENT="__PKG_PARENT__"
ENV_PATH="$PKG_PARENT/.env"

# Make package importable
if [[ -n "${PYTHONPATH:-}" ]]; then
  export PYTHONPATH="$PKG_PARENT:$PYTHONPATH"
else
  export PYTHONPATH="$PKG_PARENT"
fi

# Read GOOGLE_API_KEY from .env (if present)
read_env_key() {
  [[ -f "$ENV_PATH" ]] || return 1
  # shellcheck disable=SC2002
  cat "$ENV_PATH" | awk -F= "/^GOOGLE_API_KEY=/{\$1=\"\"; sub(/^=/,\"\"); print; exit}"
}

write_env_key() {
  local key="$1"
  awk -v key="$key" "
    BEGIN{done=0}
    /^GOOGLE_API_KEY=/{print \"GOOGLE_API_KEY=\" key; done=1; next}
    {print}
    END{if(!done) print \"GOOGLE_API_KEY=\" key}
  " "$ENV_PATH" > "$ENV_PATH.tmp"
  mv "$ENV_PATH.tmp" "$ENV_PATH"
}

prompt_key() {
  local prompt_device=""
  # Prefer /dev/tty so we can prompt even if stdin is piped
  if [[ -r /dev/tty && -w /dev/tty ]]; then
    prompt_device="/dev/tty"
  elif [[ -t 0 ]]; then
    prompt_device="/dev/stdin"
  else
    return 1
  fi

  echo -n "🔑 Enter your Google Gemini API key: " > "$prompt_device"
  local input
  IFS= read -r input < "$prompt_device" || true
  echo "$input"
}

ensure_key() {
  local key
  key="$(read_env_key || true)"
  if [[ -z "${key:-}" ]]; then
    # Try to prompt
    if key="$(prompt_key || true)"; [[ -n "${key:-}" ]]; then
      # Ensure .env exists
      [[ -f "$ENV_PATH" ]] || cat > "$ENV_PATH" <<EOF
# Auto-generated by BashBard launcher
LLM_PROVIDER=google
GOOGLE_API_KEY=
GOOGLE_MODEL=gemini-2.5-flash-lite
DRY_RUN=0
EOF
      write_env_key "$key"
      echo "✅ Saved API key to $ENV_PATH"
    else
      echo "❌ GOOGLE_API_KEY is not set and no interactive TTY available to prompt."
      echo "   Please add it to: $ENV_PATH"
      echo "   Example:"
      echo "     sed -i \"s/^GOOGLE_API_KEY=.*/GOOGLE_API_KEY=YOUR_KEY/\" \"$ENV_PATH\""
      exit 1
    fi
  fi
}

ensure_key

# Export the key for the Python runtime
export $(grep -E \"^(GOOGLE_API_KEY|LLM_PROVIDER|GOOGLE_MODEL|DRY_RUN)=\" \"$ENV_PATH\" | xargs -d \"\n\")

exec /usr/bin/env python3 -m BashBard "$@"
'

# --- Create launchers in BIN_DIR ---
info "Creating launcher(s) in: $BIN_DIR"
$SUDO mkdir -p "$BIN_DIR"
printf '%s\n' "${LAUNCHER/__PKG_PARENT__/$INSTALL_ROOT}" | $SUDO tee "$BIN_MAIN" >/dev/null
$SUDO chmod 0755 "$BIN_MAIN"

# lowercase convenience (symlink or wrapper)
if $SUDO ln -sf "BashBard" "$BIN_LOWER" 2>/dev/null; then :; else
  $SUDO bash -c "cat > '$BIN_LOWER' <<'EOW'
#!/usr/bin/env bash
exec BashBard \"\$@\"
EOW"
  $SUDO chmod 0755 "$BIN_LOWER"
fi

# --- Make it runnable *now* in this shell ---
is_on_path() { case ":$PATH:" in *":$1:"*) return 0;; *) return 1;; esac; }
make_shim() {
  local target="$1" dest_dir="$2" name="$3"
  mkdir -p "$dest_dir" 2>/dev/null || true
  if ln -sf "$target" "$dest_dir/$name" 2>/dev/null; then
    :
  else
    cat > "$dest_dir/$name" <<EOF
#!/usr/bin/env bash
exec "$target" "\$@"
EOF
    chmod 0755 "$dest_dir/$name"
  fi
}

activate_now=false
if is_on_path "$BIN_DIR"; then
  activate_now=true
else
  if is_on_path "/usr/local/bin"; then
    if ln -sf "$BIN_MAIN" "/usr/local/bin/BashBard" 2>/dev/null && ln -sf "$BIN_MAIN" "/usr/local/bin/bashbard" 2>/dev/null; then
      activate_now=true
    elif [[ "$MODE" == "system" ]]; then
      $SUDO ln -sf "$BIN_MAIN" "/usr/local/bin/BashBard" 2>/dev/null || true
      $SUDO ln -sf "$BIN_MAIN" "/usr/local/bin/bashbard" 2>/dev/null || true
      [[ -x "/usr/local/bin/BashBard" ]] && activate_now=true
    fi
  fi
  if ! $activate_now; then
    IFS=':' read -r -a path_dirs <<< "$PATH"
    for d in "${path_dirs[@]}"; do
      [[ -z "$d" ]] && continue
      if [[ -d "$d" && -w "$d" && -x "$d" ]]; then
        make_shim "$BIN_MAIN" "$d" "BashBard"
        make_shim "$BIN_MAIN" "$d" "bashbard"
        activate_now=true
        break
      fi
    done
  fi
fi

# Persist PATH for future shells (user mode only)
if [[ "$MODE" != "system" ]]; then
  persist_line='export PATH="$HOME/.local/bin:$PATH"'
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$rc" ]]; then
      if ! grep -qs 'export PATH="$HOME/.local/bin:$PATH"' "$rc"; then
        echo "$persist_line" >> "$rc"
        success "Added ~/.local/bin to PATH in $rc"
      fi
    else
      echo "$persist_line" >> "$rc" 2>/dev/null || true
    fi
  done
fi

echo ""
success "BashBard installed successfully!"
if $activate_now; then
  echo -e "${CYAN}💡 You can run now:${RESET}  BashBard --help    ${CYAN}or${RESET}  bashbard --help"
  echo -e "${CYAN}💡 First run will prompt for your API key if missing and save it to:${RESET}  $ENV_PATH"
else
  warn "Could not place a shim in a directory already on your current PATH."
  echo -e "${CYAN}👉 Run by absolute path now:${RESET}  $BIN_MAIN --help"
  echo -e "${CYAN}👉 Or export PATH for this shell:${RESET}  export PATH=\"$BIN_DIR:\$PATH\""
  echo -e "${CYAN}💡 First run will prompt for your API key if missing and save it to:${RESET}  $ENV_PATH"
fi

echo ""
success "Installation complete."
