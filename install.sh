#!/usr/bin/env bash
# ==========================================================
#  BashBard Installer — Ultra-hardened, PEP 668-safe, all-in-one
#  Handles: Kali/Debian externally-managed envs, missing venv, missing git,
#           offline fallbacks (tarball), non-interactive shells, secure .env,
#           ModuleNotFound errors, PATH shims, sudo/su detection, fish/zsh,
#           provider selection via env, preseeded keys, and more.
#  Author: Khafagy | Co-Developer: Naggar
#  Maintainer of this fix: (installer rewrite w/ venv + .pth)
#  License: Apache 2.0
# ==========================================================

# Re-exec with bash if invoked by sh/dash
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail
umask 022

# ------- Configuration (override via env) ------------------------------------
REPO_URL="${BASHBARD_REPO_URL:-https://github.com/5afagy/BashBard}"
REPO_REF="${BASHBARD_REPO_REF:-refs/heads/main}"   # can be refs/tags/vX.Y.Z
INSTALL_MODE="${1:-${BASHBARD_MODE:-user}}"       # user|system
NONINTERACTIVE="${BASHBARD_NONINTERACTIVE:-}"     # set to 1 to skip prompts
PY_BIN="${PYTHON:-python3}"

# Provider defaults (can be overridden via env before first run)
DEFAULT_LLM_PROVIDER="${LLM_PROVIDER:-google}"
DEFAULT_GOOGLE_MODEL="${GOOGLE_MODEL:-gemini-2.5-flash-lite}"
DEFAULT_OPENAI_MODEL="${OPENAI_MODEL:-gpt-4o-mini}"
PRESEEDED_GOOGLE_KEY="${GOOGLE_API_KEY:-}"
PRESEEDED_OPENAI_KEY="${OPENAI_API_KEY:-}"

# ------- UI helpers ----------------------------------------------------------
GREEN=$'[1;32m'; YELLOW=$'[1;33m'; RED=$'[1;31m'; CYAN=$'[1;36m'; RESET=$'[0m'
info(){ echo -e "${CYAN}➡${RESET} $*"; }
warn(){ echo -e "${YELLOW}⚠${RESET} $*"; }
error(){ echo -e "${RED}❌${RESET} $*" >&2; exit 1; }
success(){ echo -e "${GREEN}✅${RESET} $*"; }

usage(){ cat <<'USAGE'
Usage:
  ./install.sh [user|system]

Env overrides (optional):
  BASHBARD_MODE=user|system
  BASHBARD_NONINTERACTIVE=1   (skip prompts)
  BASHBARD_REPO_URL=...
  BASHBARD_REPO_REF=refs/tags/vX.Y.Z
  PYTHON=/path/to/python3
  LLM_PROVIDER=google|openai
  GOOGLE_API_KEY=...  OPENAI_API_KEY=...
  GOOGLE_MODEL=...    OPENAI_MODEL=...

Examples:
  curl -sSL https://github.com/5afagy/BashBard/raw/refs/heads/main/install.sh | bash
  BASHBARD_NONINTERACTIVE=1 bash install.sh system
USAGE
}

case "$INSTALL_MODE" in
  user|system) ;;
  -h|--help|help) usage; exit 0 ;;
  *) warn "Unknown mode '$INSTALL_MODE' — defaulting to 'user'"; INSTALL_MODE=user ;;
esac

# ------- Elevation & package manager detection --------------------------------
ELEV=""; if command -v sudo >/dev/null 2>&1; then ELEV="sudo"; elif command -v su >/dev/null 2>&1; then ELEV="su -c"; fi
pkg_install(){
  # $1 = packages...
  local pkgs=("$@")
  if command -v apt-get >/dev/null 2>&1; then
    [[ -n "$ELEV" ]] || error "Need privileges to install: ${pkgs[*]}";
    $ELEV apt-get update -y && $ELEV apt-get install -y "${pkgs[@]}"
  elif command -v dnf >/dev/null 2>&1; then
    [[ -n "$ELEV" ]] || error "Need privileges to install: ${pkgs[*]}";
    $ELEV dnf install -y "${pkgs[@]}"
  elif command -v yum >/dev/null 2>&1; then
    [[ -n "$ELEV" ]] || error "Need privileges to install: ${pkgs[*]}";
    $ELEV yum install -y "${pkgs[@]}"
  elif command -v pacman >/dev/null 2>&1; then
    [[ -n "$ELEV" ]] || error "Need privileges to install: ${pkgs[*]}";
    $ELEV pacman -Sy --noconfirm "${pkgs[@]}"
  else
    error "Unsupported package manager; install these manually: ${pkgs[*]}"
  fi
}

# ------- Sanity checks --------------------------------------------------------
command -v "$PY_BIN" >/dev/null 2>&1 || error "Python 3 not found. Set PYTHON=/path/to/python3"
PY_VER=$("$PY_BIN" -c 'import sys;print("%d.%d"%sys.version_info[:2])')
case "$PY_VER" in
  3.[8-9]|3.1[0-9]|3.2[0-9]) : ;;  # >=3.8
  *) warn "Python $PY_VER detected. Python >=3.8 is recommended." ;;
esac

# ------- Temp dir & cleanup ---------------------------------------------------
TMP_DIR="$(mktemp -d -t bashbard-install-XXXXXX)" || error "mktemp failed"
cleanup(){ [[ -d "${TMP_DIR:-}" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# ------- Resolve install paths ------------------------------------------------
if [[ "$INSTALL_MODE" == "system" ]]; then
  [[ -n "$ELEV" ]] || error "System mode requires sudo/su."
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

# Ensure home/local dirs writable in user mode
if [[ "$INSTALL_MODE" == "user" ]]; then
  [[ -w "${HOME}" ]] || error "Home directory not writable."
fi

# ------- Fetch source (git or tarball) ---------------------------------------
fetch_source(){
  local dest="$1"
  info "Downloading BashBard from GitHub..."
  if command -v git >/dev/null 2>&1; then
    git clone --depth=1 "$REPO_URL" "$dest" >/dev/null 2>&1 || true
    if [[ ! -d "$dest/BashBard" ]]; then
      warn "git clone failed or layout unexpected; falling back to tarball."
    else
      return 0
    fi
  fi
  # Tarball fallback (no git needed)
  local tar_url="https://codeload.github.com/$(echo "$REPO_URL" | sed -E 's#https?://github.com/##')/tar.gz/${REPO_REF}"
  curl -fsSL "$tar_url" -o "$dest.tar.gz" || error "Failed to download tarball."
  mkdir -p "$dest.extracted"
  tar -xzf "$dest.tar.gz" -C "$dest.extracted" || error "Failed to extract tarball."
  # The archive root is like BashBard-<hash>/*
  local inner; inner=$(find "$dest.extracted" -maxdepth 1 -type d -name 'BashBard-*' | head -n1)
  [[ -n "$inner" ]] || error "Unexpected tarball structure."
  cp -a "$inner"/* "$dest" || error "Copy from tarball failed."
}

fetch_source "$TMP_DIR"
[[ -d "$TMP_DIR/BashBard" ]] || error "Repository structure invalid (missing BashBard/)."

# ------- Copy code to INSTALL_ROOT -------------------------------------------
info "Installing BashBard package to: $INSTALL_ROOT"
if [[ "$INSTALL_MODE" == "system" ]]; then
  $ELEV mkdir -p "$INSTALL_ROOT"
  $ELEV rm -rf "$INSTALL_ROOT/BashBard"
  $ELEV cp -a "$TMP_DIR/BashBard" "$INSTALL_ROOT/"
else
  mkdir -p "$INSTALL_ROOT"
  rm -rf "$INSTALL_ROOT/BashBard"
  cp -a "$TMP_DIR/BashBard" "$INSTALL_ROOT/"
fi

# ------- Create virtualenv (always; PEP 668 safe) ----------------------------
create_venv(){
  local py="$1" venv_dir="$2"
  if [[ "$INSTALL_MODE" == "system" ]]; then
    $ELEV "$py" -m venv "$venv_dir" || return 1
    $ELEV "$venv_dir/bin/python" -m pip install --upgrade pip setuptools wheel || true
  else
    "$py" -m venv "$venv_dir" || return 1
    "$venv_dir/bin/python" -m pip install --upgrade pip setuptools wheel || true
  fi
}

info "Creating/upgrading virtual environment at: $VENV_DIR"
if ! create_venv "$PY_BIN" "$VENV_DIR"; then
  warn "Could not create venv — likely missing python3-venv."
  if command -v apt-get >/dev/null 2>&1; then
    [[ "$INSTALL_MODE" == "system" ]] || warn "You may need system mode to install python3-venv."
    pkg_install python3-venv
    info "Retrying virtualenv creation..."
    create_venv "$PY_BIN" "$VENV_DIR" || error "Virtualenv creation still failing."
  else
    error "Install your distro's Python venv package and re-run."
  fi
fi

# ------- Install Python deps into venv ---------------------------------------
REQ_FILE="$TMP_DIR/requirements.txt"
if [[ -f "$REQ_FILE" ]]; then
  info "Installing dependencies into venv..."
  set +e
  if [[ "$INSTALL_MODE" == "system" ]]; then
    $ELEV "$PY_VENV" -m pip install -r "$REQ_FILE" --no-warn-script-location
  else
    "$PY_VENV" -m pip install -r "$REQ_FILE" --no-warn-script-location
  fi
  RC=$?; set -e
  [[ $RC -eq 0 ]] || error $'Failed to install one or more dependencies into the virtualenv.\n(We never use system pip per PEP 668.)'
else
  warn "No requirements.txt; skipping dependency install."
fi

# ------- Ensure module importability (.pth + launcher PYTHONPATH) -------------
# Add INSTALL_ROOT to venv site-packages via .pth (persistent)
SITE_PKGS=$("$PY_VENV" - <<'PY'
import sysconfig,sys
print(sysconfig.get_paths().get('purelib') or sysconfig.get_paths().get('platlib') or '')
PY
)
if [[ -n "$SITE_PKGS" && -d "$SITE_PKGS" ]]; then
  PTH_FILE="$SITE_PKGS/bashbard_install_root.pth"
  if [[ "$INSTALL_MODE" == "system" ]]; then
    echo "$INSTALL_ROOT" | $ELEV tee "$PTH_FILE" >/dev/null
  else
    echo "$INSTALL_ROOT" > "$PTH_FILE"
  fi
  info "Linked site-packages via .pth: $PTH_FILE"
else
  warn "Could not determine site-packages; relying on launcher PYTHONPATH."
fi

# ------- Secure .env (0600) & optional preseeded keys ------------------------
info "Configuring BashBard environment..."
mkdir -p "$(dirname "$ENV_PATH")" 2>/dev/null || true
emit_env(){
  cat <<EOF
# Agentic BashBard environment configuration
# Automatically generated during installation
LLM_PROVIDER=${DEFAULT_LLM_PROVIDER}
GOOGLE_API_KEY=${PRESEEDED_GOOGLE_KEY}
GOOGLE_MODEL=${DEFAULT_GOOGLE_MODEL}
OPENAI_API_KEY=${PRESEEDED_OPENAI_KEY}
OPENAI_MODEL=${DEFAULT_OPENAI_MODEL}
# If set to 1, commands are not executed (dry-run)
DRY_RUN=0
EOF
}

create_or_update_env(){
  if [[ ! -f "$ENV_PATH" ]]; then
    if [[ "$INSTALL_MODE" == "system" ]]; then
      $ELEV install -m 600 /dev/null "$ENV_PATH"
      emit_env | $ELEV tee "$ENV_PATH" >/dev/null
      $ELEV chmod 600 "$ENV_PATH" || true
    else
      install -m 600 /dev/null "$ENV_PATH"
      emit_env > "$ENV_PATH"
      chmod 600 "$ENV_PATH" || true
    fi
    success "Created .env at $ENV_PATH (0600)"
  else
    if [[ "$INSTALL_MODE" == "system" ]]; then $ELEV chmod 600 "$ENV_PATH" || true; else chmod 600 "$ENV_PATH" || true; fi
    warn ".env already exists — keeping existing values (permissions set to 0600)."
  fi
}
create_or_update_env

# Prompt key if interactive and not preseeded
if [[ -z "${NONINTERACTIVE}" && -t 0 && -t 1 ]]; then
  need_google=""; need_openai=""
  # shellcheck disable=SC1090
  . "$ENV_PATH" || true
  [[ -z "${GOOGLE_API_KEY:-}" && "${LLM_PROVIDER:-$DEFAULT_LLM_PROVIDER}" == "google" ]] && need_google=1
  [[ -z "${OPENAI_API_KEY:-}" && "${LLM_PROVIDER:-$DEFAULT_LLM_PROVIDER}" == "openai" ]] && need_openai=1
  if [[ -n "$need_google" ]]; then
    echo ""
    read -srp "🔑 Enter your Google Gemini API key (or press Enter to skip): " GEMINI_KEY || true; echo ""
    if [[ -n "${GEMINI_KEY:-}" ]]; then
      awk -v key="$GEMINI_KEY" '
        BEGIN{done=0}
        /^GOOGLE_API_KEY=/{print "GOOGLE_API_KEY=" key; done=1; next}
        {print}
        END{if(!done) print "GOOGLE_API_KEY=" key}
      ' "$ENV_PATH" > "$ENV_PATH.tmp" && mv "$ENV_PATH.tmp" "$ENV_PATH" && chmod 600 "$ENV_PATH" || true
      success "Gemini API key saved to $ENV_PATH"
    fi
  fi
  if [[ -n "$need_openai" ]]; then
    echo ""
    read -srp "🔑 Enter your OpenAI API key (or press Enter to skip): " OAI_KEY || true; echo ""
    if [[ -n "${OAI_KEY:-}" ]]; then
      awk -v key="$OAI_KEY" '
        BEGIN{done=0}
        /^OPENAI_API_KEY=/{print "OPENAI_API_KEY=" key; done=1; next}
        {print}
        END{if(!done) print "OPENAI_API_KEY=" key}
      ' "$ENV_PATH" > "$ENV_PATH.tmp" && mv "$ENV_PATH.tmp" "$ENV_PATH" && chmod 600 "$ENV_PATH" || true
      success "OpenAI API key saved to $ENV_PATH"
    fi
  fi
else
  warn "Non-interactive install; launcher will prompt for missing API keys on first run."
fi

# ------- Launcher (venv + PYTHONPATH guard) ----------------------------------
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
OPENAI_API_KEY=
OPENAI_MODEL=gpt-4o-mini
DRY_RUN=0
EOF
  chmod 600 "${ENV_PATH}" || true
fi

get_key(){ grep -m1 "^${1}=" "${ENV_PATH}" | cut -d"=" -f2- || true; }
set_kv(){
  local k="$1" v="$2"; umask 177
  awk -v k="$k" -v v="$v" '
    BEGIN{done=0}
    $0 ~ ("^" k "="){print k "=" v; done=1; next}
    {print}
    END{if(!done) print k "=" v}
  ' "${ENV_PATH}" > "${ENV_PATH}.tmp"
  mv "${ENV_PATH}.tmp" "${ENV_PATH}"; chmod 600 "${ENV_PATH}" || true
}

prompt_secret(){
  local msg="$1" dev=""
  if [[ -r /dev/tty && -w /dev/tty ]]; then dev=/dev/tty
  elif [[ -t 0 ]]; then dev=/dev/stdin
  else return 1
  fi
  printf "%s" "$msg" >"$dev"; local input; IFS= read -rs input <"$dev" || true; printf "\n" >"$dev"; printf "%s" "$input"
}

# Export .env vars
set -a; . "${ENV_PATH}"; set +a

# Prompt missing API key for selected provider if interactive
if [[ -t 0 && -t 1 ]]; then
  if [[ "${LLM_PROVIDER:-google}" == "google" && -z "${GOOGLE_API_KEY:-}" ]]; then
    key="$(prompt_secret "🔑 Enter your Google Gemini API key: " || true)"
    if [[ -n "${key:-}" ]]; then set_kv GOOGLE_API_KEY "$key"; export GOOGLE_API_KEY="$key"; fi
  elif [[ "${LLM_PROVIDER:-google}" == "openai" && -z "${OPENAI_API_KEY:-}" ]]; then
    key="$(prompt_secret "🔑 Enter your OpenAI API key: " || true)"
    if [[ -n "${key:-}" ]]; then set_kv OPENAI_API_KEY "$key"; export OPENAI_API_KEY="$key"; fi
  fi
fi

# Guard: ensure module import visibility
if [[ -n "${PYTHONPATH:-}" ]]; then
  export PYTHONPATH="${PKG_PARENT}:${PYTHONPATH}"
else
  export PYTHONPATH="${PKG_PARENT}"
fi

# Run
exec "${PY}" -m BashBard "$@"
'

info "Creating launcher(s) in: $BIN_DIR"
if [[ "$INSTALL_MODE" == "system" ]]; then
  $ELEV mkdir -p "$BIN_DIR"
  printf '%s\n' "${LAUNCHER/__PKG_PARENT__/$INSTALL_ROOT}" | $ELEV tee "$BIN_DIR/BashBard" >/dev/null
  $ELEV chmod 0755 "$BIN_DIR/BashBard"
else
  mkdir -p "$BIN_DIR"
  printf '%s\n' "${LAUNCHER/__PKG_PARENT__/$INSTALL_ROOT}" > "$BIN_DIR/BashBard"
  chmod 0755 "$BIN_DIR/BashBard"
fi

# Lowercase convenience
if ln -sf "BashBard" "$BIN_DIR/bashbard" 2>/dev/null; then :; else
  if [[ "$INSTALL_MODE" == "system" ]]; then
    $ELEV bash -c "cat > '$BIN_DIR/bashbard' <<'EOW'\n#!/usr/bin/env bash\nexec BashBard \"\$@\"\nEOW"
    $ELEV chmod 0755 "$BIN_DIR/bashbard"
  else
    cat > "$BIN_DIR/bashbard" <<'EOW'
#!/usr/bin/env bash
exec BashBard "$@"
EOW
    chmod 0755 "$BIN_DIR/bashbard"
  fi
fi

# PATH persistence for user mode (bash/zsh + fish)
if [[ "$INSTALL_MODE" != "system" ]]; then
  persist_line='export PATH="$HOME/.local/bin:$PATH"'
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$rc" ]]; then
      if ! grep -qs 'export PATH="$HOME/.local/bin:$PATH"' "$rc"; then echo "$persist_line" >> "$rc"; success "Added ~/.local/bin to PATH in $rc"; fi
    else echo "$persist_line" >> "$rc" 2>/dev/null || true; fi
  done
  # fish shell
  if command -v fish >/dev/null 2>&1; then
    mkdir -p "$HOME/.config/fish"; FISH_CFG="$HOME/.config/fish/config.fish"
    if ! grep -qs "set -gx PATH \$HOME/.local/bin \$PATH" "$FISH_CFG" 2>/dev/null; then
      echo "set -gx PATH \$HOME/.local/bin \$PATH" >> "$FISH_CFG"; success "Added ~/.local/bin to PATH in fish config"
    fi
  fi
fi

# Final messages
echo ""
success "BashBard installed successfully!"
if command -v BashBard >/dev/null 2>&1 || command -v bashbard >/dev/null 2>&1; then
  echo -e "${CYAN}💡 Run now:${RESET}  BashBard --help  ${CYAN}or${RESET}  bashbard --help"
  echo -e "${CYAN}💡 First run will prompt for missing API key(s) and save to:${RESET}  $ENV_PATH"
else
  warn "Your current PATH may not include $BIN_DIR."
  echo -e "${CYAN}👉 Run by absolute path:${RESET}  $BIN_DIR/BashBard --help"
  echo -e "${CYAN}👉 Or export PATH for this shell:${RESET}  export PATH=\"$BIN_DIR:$PATH\""
fi
