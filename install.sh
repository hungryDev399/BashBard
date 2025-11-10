#!/usr/bin/env bash
# ==========================================================
#  BashBard Installer (PEP 668/Kali-safe)
#  AI Assistant for Shell Automation and Command Correction
#  Author: Khafagy | Co-Developer: Naggar
#  Maintainer of this fix: (installer rewrite w/ venv)
#  License: Apache 2.0
# ==========================================================

# Re-exec with bash if invoked by sh/dash
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail
umask 022

REPO_URL="https://github.com/5afagy/BashBard.git"
TMP_DIR="$(mktemp -d -t bashbard-install-XXXXXX)"
trap '[[ -d "${TMP_DIR:-}" ]] && rm -rf "$TMP_DIR"' EXIT

# Colors + helpers
GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[1;31m'; CYAN=$'\033[1;36m'; RESET=$'\033[0m'
info(){ echo -e "${CYAN}➡${RESET} $*"; }
warn(){ echo -e "${YELLOW}⚠${RESET} $*"; }
error(){ echo -e "${RED}❌${RESET} $*" >&2; exit 1; }
success(){ echo -e "${GREEN}✅${RESET} $*"; }

# Usage
usage() {
  cat <<'USAGE'
Usage:
  ./install.sh [user|system]

Modes:
  user   → installs to ~/.local (default)
  system → installs to /usr/local (requires sudo or su)
USAGE
}

MODE="${1:-user}"
case "$MODE" in
  user|system) ;;
  -h|--help|help) usage; exit 0 ;;
  *) warn "Unknown mode '$MODE' — defaulting to 'user'"; MODE="user" ;;
esac

# Elevation helper
_elev=""
if command -v sudo >/dev/null 2>&1; then
  _elev="sudo"
elif command -v su >/dev/null 2>&1; then
  _elev="su -c"
fi

# Requirements
command -v git >/dev/null 2>&1 || error "git not found."
PY="${PYTHON:-python3}"
command -v "$PY" >/dev/null 2>&1 || error "Python 3 not found."
"$PY" -m pip --version >/dev/null 2>&1 || "$PY" -m ensurepip --upgrade >/dev/null 2>&1 || true

info "Using Python: $("$PY" -c 'import sys; print(sys.executable)')"
info "Pip version:  $("$PY" -m pip --version || echo 'unknown')"

# Clone source
info "Downloading BashBard from GitHub..."
git clone --depth=1 "$REPO_URL" "$TMP_DIR" >/dev/null 2>&1 || error "Failed to clone repository."
[[ -d "$TMP_DIR/BashBard" ]] || error "Repository structure invalid (missing BashBard/)."

# Layout per mode
if [[ "$MODE" == "system" ]]; then
  [[ -n "$_elev" ]] || error "Need elevated privileges but no sudo/su found."
  INSTALL_ROOT="/usr/local/share/bashbard"
  BIN_DIR="/usr/local/bin"
else
  INSTALL_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/bashbard"
  BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
fi

ENV_PATH="$INSTALL_ROOT/.env"
VENV_DIR="$INSTALL_ROOT/venv"
PY_VENV="$VENV_DIR/bin/python"
PIP_VENV="$VENV_DIR/bin/pip"

# Copy code
info "Installing BashBard package to: $INSTALL_ROOT"
if [[ "$MODE" == "system" ]]; then
  $_elev mkdir -p "$INSTALL_ROOT"
  $_elev rm -rf "$INSTALL_ROOT/BashBard"
  $_elev cp -a "$TMP_DIR/BashBard" "$INSTALL_ROOT/"
else
  mkdir -p "$INSTALL_ROOT"
  rm -rf "$INSTALL_ROOT/BashBard"
  cp -a "$TMP_DIR/BashBard" "$INSTALL_ROOT/"
fi

# Create/upgrade virtualenv — ALWAYS use venv to avoid PEP 668 issues
create_venv() {
  local py="$1" venv_dir="$2"
  if [[ "$MODE" == "system" ]]; then
    $_elev "$py" -m venv "$venv_dir" || return 1
    $_elev "$venv_dir/bin/python" -m pip install --upgrade pip || true
  else
    "$py" -m venv "$venv_dir" || return 1
    "$venv_dir/bin/python" -m pip install --upgrade pip || true
  fi
}

info "Creating/upgrading virtual environment at: $VENV_DIR"
if ! create_venv "$PY" "$VENV_DIR"; then
  # Detect classic Debian/Ubuntu/Kali missing python3-venv
  if "$PY" -m pip -V >/dev/null 2>&1; then :; fi
  warn "Could not create venv. Your system may be missing the python3-venv package (PEP 668-safe environments)."
  if [[ "$MODE" == "system" && -n "$_elev" && ( -x /usr/bin/apt || -x /bin/apt ) ]]; then
    warn "Attempting to install python3-venv using apt (requires privileges)."
    if $_elev apt-get update -y >/dev/null 2>&1 && $_elev apt-get install -y python3-venv >/dev/null 2>&1; then
      info "python3-venv installed. Retrying venv creation..."
      create_venv "$PY" "$VENV_DIR" || error "Virtualenv creation still failing. Aborting."
    else
      error "Failed to install python3-venv via apt. Please install it and re-run."
    fi
  else
    error $'Venv creation failed. On Debian/Ubuntu/Kali, install python3-venv (or pypy3-venv) and re-run.\nSee: /usr/share/doc/python3*/README.venv'
  fi
fi

# Install dependencies into venv (never system pip)
REQ_FILE="$TMP_DIR/requirements.txt"
if [[ -f "$REQ_FILE" ]]; then
  info "Installing dependencies into venv..."
  set +e
  if [[ "$MODE" == "system" ]]; then
    $_elev "$PY_VENV" -m pip install -r "$REQ_FILE" --no-warn-script-location
  else
    "$PY_VENV" -m pip install -r "$REQ_FILE" --no-warn-script-location
  fi
  RC=$?; set -e
  if [[ $RC -ne 0 ]]; then
    error $'Failed to install one or more dependencies into the virtualenv.\nThis installer avoids system pip per PEP 668; please review the error above.'
  fi
else
  warn "No requirements.txt; skipping dependency install."
fi

# .env handling — secure perms and hidden input
info "Configuring BashBard environment..."
mkdir -p "$(dirname "$ENV_PATH")" 2>/dev/null || true
if [[ ! -f "$ENV_PATH" ]]; then
  # create with 600 regardless of umask
  if [[ "$MODE" == "system" ]]; then
    $_elev install -m 600 /dev/null "$ENV_PATH"
    $_elev bash -c "cat > '$ENV_PATH' <<'EOF'
# Agentic BashBard environment configuration
# Automatically generated during installation
LLM_PROVIDER=google
GOOGLE_API_KEY=
GOOGLE_MODEL=gemini-2.5-flash-lite
DRY_RUN=0
EOF"
    $_elev chmod 600 "$ENV_PATH" || true
  else
    install -m 600 /dev/null "$ENV_PATH"
    cat > "$ENV_PATH" <<'EOF'
# Agentic BashBard environment configuration
# Automatically generated during installation
LLM_PROVIDER=google
GOOGLE_API_KEY=
GOOGLE_MODEL=gemini-2.5-flash-lite
DRY_RUN=0
EOF
    chmod 600 "$ENV_PATH" || true
  fi
  success "Created .env at $ENV_PATH (0600)"
else
  if [[ "$MODE" == "system" ]]; then $_elev chmod 600 "$ENV_PATH" || true; else chmod 600 "$ENV_PATH" || true; fi
  warn ".env already exists — keeping existing values (permissions set to 0600)."
fi

# Prompt during install only if interactive; otherwise defer to first run
if [[ -t 0 && -t 1 ]]; then
  echo ""
  read -srp "🔑 Enter your Google Gemini API key (or press Enter to skip): " GEMINI_KEY || true
  echo ""
  if [[ -n "${GEMINI_KEY:-}" ]]; then
    # Safe in-place update of GOOGLE_API_KEY
    if [[ "$MODE" == "system" ]]; then
      $_elev awk -v key="$GEMINI_KEY" '
        BEGIN{done=0}
        /^GOOGLE_API_KEY=/{print "GOOGLE_API_KEY=" key; done=1; next}
        {print}
        END{if(!done) print "GOOGLE_API_KEY=" key}
      ' "$ENV_PATH" | $_elev tee "$ENV_PATH.tmp" >/dev/null
      $_elev mv "$ENV_PATH.tmp" "$ENV_PATH"
      $_elev chmod 600 "$ENV_PATH" || true
    else
      awk -v key="$GEMINI_KEY" '
        BEGIN{done=0}
        /^GOOGLE_API_KEY=/{print "GOOGLE_API_KEY=" key; done=1; next}
        {print}
        END{if(!done) print "GOOGLE_API_KEY=" key}
      ' "$ENV_PATH" > "$ENV_PATH.tmp"
      mv "$ENV_PATH.tmp" "$ENV_PATH"
      chmod 600 "$ENV_PATH" || true
    fi
    success "Gemini API key saved to $ENV_PATH"
  else
    warn "No API key entered now; launcher will prompt on first run."
  fi
else
  warn "Non-interactive install; launcher will prompt for API key on first run."
fi

# --- Hardened launcher (venv, hidden prompt, 0600) ---
LAUNCHER='#!/usr/bin/env bash
set -euo pipefail

PKG_PARENT="__PKG_PARENT__"
ENV_PATH="${PKG_PARENT}/.env"
VENV="${PKG_PARENT}/venv"
PY="${VENV}/bin/python"

# Ensure venv exists
if [[ ! -x "${PY}" ]]; then
  echo "❌ Virtualenv missing at ${VENV}. Reinstall BashBard." >&2
  exit 1
fi

# Ensure .env directory exists
mkdir -p "$(dirname "${ENV_PATH}")"

# Bootstrap minimal .env if missing (0600)
if [[ ! -f "${ENV_PATH}" ]]; then
  umask 177
  cat >"${ENV_PATH}" <<EOF
LLM_PROVIDER=google
GOOGLE_API_KEY=
GOOGLE_MODEL=gemini-2.5-flash-lite
DRY_RUN=0
EOF
  chmod 600 "${ENV_PATH}" || true
fi

get_key() {
  grep -m1 "^GOOGLE_API_KEY=" "${ENV_PATH}" | cut -d"=" -f2- || true
}

set_key() {
  local key="$1"
  umask 177
  awk -v key="$key" "
    BEGIN{done=0}
    /^GOOGLE_API_KEY=/{print \"GOOGLE_API_KEY=\" key; done=1; next}
    {print}
    END{if(!done) print \"GOOGLE_API_KEY=\" key}
  " "${ENV_PATH}" > "${ENV_PATH}.tmp"
  mv "${ENV_PATH}.tmp" "${ENV_PATH}"
  chmod 600 "${ENV_PATH}" || true
}

prompt_key() {
  local dev=""
  if [[ -r /dev/tty && -w /dev/tty ]]; then dev=/dev/tty
  elif [[ -t 0 ]]; then dev=/dev/stdin
  else return 1
  fi
  printf "🔑 Enter your Google Gemini API key: " >"$dev"
  local input; IFS= read -rs input <"$dev" || true
  printf "\n" >"$dev"
  printf "%s" "$input"
}

key="$(get_key)"
if [[ -z "${key:-}" ]]; then
  key="$(prompt_key || true)"
  if [[ -n "${key:-}" ]]; then
    set_key "$key"
    echo "✅ Saved API key to ${ENV_PATH}"
  else
    echo "❌ GOOGLE_API_KEY is not set and no TTY available to prompt." >&2
    echo "   Please edit: ${ENV_PATH}" >&2
    exit 1
  fi
fi

# Export vars from .env
set -a
. "${ENV_PATH}"
set +a

# Run using the venv interpreter
exec "${PY}" -m BashBard "$@"
'

info "Creating launcher(s) in: $BIN_DIR"
if [[ "$MODE" == "system" ]]; then
  $_elev mkdir -p "$BIN_DIR"
  printf '%s\n' "${LAUNCHER/__PKG_PARENT__/$INSTALL_ROOT}" | $_elev tee "$BIN_DIR/BashBard" >/dev/null
  $_elev chmod 0755 "$BIN_DIR/BashBard"
else
  mkdir -p "$BIN_DIR"
  printf '%s\n' "${LAUNCHER/__PKG_PARENT__/$INSTALL_ROOT}" > "$BIN_DIR/BashBard"
  chmod 0755 "$BIN_DIR/BashBard"
fi

# Lowercase convenience (symlink or wrapper)
if ln -sf "BashBard" "$BIN_DIR/bashbard" 2>/dev/null; then :; else
  if [[ "$MODE" == "system" ]]; then
    $_elev bash -c "cat > '$BIN_DIR/bashbard' <<'EOW'\n#!/usr/bin/env bash\nexec BashBard \"\$@\"\nEOW"
    $_elev chmod 0755 "$BIN_DIR/bashbard"
  else
    cat > "$BIN_DIR/bashbard" <<'EOW'
#!/usr/bin/env bash
exec BashBard "$@"
EOW
    chmod 0755 "$BIN_DIR/bashbard"
  fi
fi

# Try to make runnable now via PATH, else suggest
is_on_path(){ case ":$PATH:" in *":$1:"*) return 0;; *) return 1;; esac; }
activate_now=false
if is_on_path "$BIN_DIR"; then
  activate_now=true
else
  # Try /usr/local/bin if writable
  if is_on_path "/usr/local/bin"; then
    if [[ "$MODE" == "system" ]]; then
      $_elev ln -sf "$BIN_DIR/BashBard" "/usr/local/bin/BashBard" 2>/dev/null || true
      $_elev ln -sf "$BIN_DIR/BashBard" "/usr/local/bin/bashbard" 2>/dev/null || true
      [[ -x "/usr/local/bin/BashBard" ]] && activate_now=true
    fi
  fi
fi

# Persist PATH for future shells (user mode)
if [[ "$MODE" != "system" ]]; then
  persist_line='export PATH="$HOME/.local/bin:$PATH"'
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$rc" ]]; then
      if ! grep -qs 'export PATH="$HOME/.local/bin:$PATH"' "$rc"; then
        echo "$persist_line" >> "$rc"; success "Added ~/.local/bin to PATH in $rc"
      fi
    else
      echo "$persist_line" >> "$rc" 2>/dev/null || true
    fi
  done
fi

# Final messages
echo ""
success "BashBard installed successfully!"
if $activate_now; then
  echo -e "${CYAN}💡 Run now:${RESET}  BashBard --help  ${CYAN}or${RESET}  bashbard --help"
  echo -e "${CYAN}💡 First run will prompt for API key if missing and save to:${RESET}  $ENV_PATH"
else
  warn "Your current PATH may not include $BIN_DIR."
  echo -e "${CYAN}👉 Run by absolute path:${RESET}  $BIN_DIR/BashBard --help"
  echo -e "${CYAN}👉 Or export PATH for this shell:${RESET}  export PATH=\"$BIN_DIR:$PATH\""
fi
