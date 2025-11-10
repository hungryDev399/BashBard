#!/usr/bin/env bash
# ==========================================================
# BashBard Installer — Expert hardened final version
# - Always uses a venv (PEP 668 safe)
# - Works on Kali/Debian/Ubuntu/Fedora/Arch/RHEL families
# - Safe .env handling (0600); hidden prompts
# - Robust elevation handling (sudo or su -c)
# - Safe file edits using local temp + elevated move (avoids quoting bugs)
# - Ensures module importability (.pth + PYTHONPATH)
# ==========================================================
set -euo pipefail
umask 022

# ---------- Configuration (override via env) ----------------
REPO_URL="${BASHBARD_REPO_URL:-https://github.com/5afagy/BashBard}"
REPO_REF="${BASHBARD_REPO_REF:-refs/heads/main}"
MODE="${1:-${BASHBARD_MODE:-user}}"   # user | system
NONINTERACTIVE="${BASHBARD_NONINTERACTIVE:-}"
PY_BIN="${PYTHON:-python3}"

DEFAULT_LLM_PROVIDER="${LLM_PROVIDER:-google}"
DEFAULT_GOOGLE_MODEL="${GOOGLE_MODEL:-gemini-2.5-flash-lite}"
DEFAULT_OPENAI_MODEL="${OPENAI_MODEL:-gpt-4o-mini}"
PRESEEDED_GOOGLE_KEY="${GOOGLE_API_KEY:-}"
PRESEEDED_OPENAI_KEY="${OPENAI_API_KEY:-}"

# ---------- UI helpers --------------------------------------
GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[1;31m'; CYAN=$'\033[1;36m'; RESET=$'\033[0m'
info(){ echo -e "${CYAN}➡${RESET} $*"; }
warn(){ echo -e "${YELLOW}⚠${RESET} $*"; }
error(){ echo -e "${RED}❌${RESET} $*" >&2; exit 1; }
success(){ echo -e "${GREEN}✅${RESET} $*"; }

usage() {
  cat <<USAGE
Usage: ./install.sh [user|system]

Env overrides:
  PYTHON=/path/to/python3
  BASHBARD_NONINTERACTIVE=1
  BASHBARD_REPO_URL=...
  BASHBARD_REPO_REF=refs/tags/vX.Y.Z
  LLM_PROVIDER=google|openai
  GOOGLE_API_KEY=...
  OPENAI_API_KEY=...
USAGE
}

case "$MODE" in
  user|system) ;;
  -h|--help|help) usage; exit 0 ;;
  *) warn "Unknown mode '$MODE' — defaulting to 'user'"; MODE=user ;;
esac

# ---------- Elevation helpers --------------------------------
# Provide a function to run a command with elevation, robustly.
# For file changes we will write locally then move with elevation.
if command -v sudo >/dev/null 2>&1; then
  run_elev() { sudo --preserve-env=PATH,HOME,USER bash -c "$*"; }
elif command -v su >/dev/null 2>&1; then
  run_elev() { su -c "$*"; }
else
  run_elev() { bash -c "$*"; }  # no elevation available; will fail when privileges needed
fi

# ---------- sanity / preflight --------------------------------
command -v "$PY_BIN" >/dev/null 2>&1 || error "Python 3 not found. Set PYTHON=/path/to/python3"
PY_VER=$("$PY_BIN" -c 'import sys;print("%d.%d"%(sys.version_info[0],sys.version_info[1]))' 2>/dev/null || echo "3.0")
case "$PY_VER" in
  3.[8-9]|3.1[0-9]|3.2[0-9]) : ;;  # >=3.8
  *) warn "Python $PY_VER detected. Python >=3.8 recommended." ;;
esac

# ---------- temp dir & cleanup --------------------------------
TMP_DIR="$(mktemp -d -t bashbard-install-XXXXXX)" || error "mktemp failed"
cleanup(){ [[ -d "${TMP_DIR:-}" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# ---------- install paths ------------------------------------
if [[ "$MODE" == "system" ]]; then
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

info "Install mode: $MODE"
info "Install root: $INSTALL_ROOT"
info "Launcher dir: $BIN_DIR"

# ---------- fetch source (git or tarball) ---------------------
fetch_source() {
  local dest="$1"
  info "Downloading BashBard..."
  if command -v git >/dev/null 2>&1; then
    if git clone --depth=1 "$REPO_URL" "$dest" >/dev/null 2>&1; then
      return 0
    else
      warn "git clone failed; falling back to tarball."
    fi
  else
    warn "git not available; using tarball fallback."
  fi

  # tarball fallback
  local gh_path
  gh_path="$(echo "$REPO_URL" | sed -E 's#https?://github.com/##' )"
  local tar_url="https://codeload.github.com/${gh_path}/tar.gz/${REPO_REF#refs/heads/}"
  info "Downloading tarball: $(printf '%.80s' "$tar_url")"
  curl -fsSL "$tar_url" -o "$TMP_DIR/repo.tar.gz" || error "Failed to download repository tarball."
  mkdir -p "$dest.extracted"
  tar -xzf "$TMP_DIR/repo.tar.gz" -C "$dest.extracted" || error "Failed to extract tarball."
  local inner
  inner="$(find "$dest.extracted" -maxdepth 1 -type d -name 'BashBard*' | head -n1)"
  [[ -n "$inner" ]] || error "Unexpected tarball layout."
  mkdir -p "$dest"
  cp -a "$inner"/* "$dest"/ || error "Copy from tarball failed."
}

fetch_source "$TMP_DIR"
[[ -d "$TMP_DIR/BashBard" ]] || error "Repository layout missing (expected BashBard/)."

# ---------- copy files to install root ------------------------
info "Copying files to: $INSTALL_ROOT"
if [[ "$MODE" == "system" ]]; then
  run_elev "mkdir -p '$INSTALL_ROOT'"
  run_elev "rm -rf '$INSTALL_ROOT/BashBard'"
  run_elev "cp -a '$TMP_DIR/BashBard' '$INSTALL_ROOT/'"
else
  mkdir -p "$INSTALL_ROOT"
  rm -rf "$INSTALL_ROOT/BashBard"
  cp -a "$TMP_DIR/BashBard" "$INSTALL_ROOT/"
fi

# ---------- create virtualenv (PEP 668 safe) -------------------
create_venv() {
  local py="$1" vdir="$2"
  if [[ "$MODE" == "system" ]]; then
    run_elev "'$py' -m venv '$vdir'" || return 1
    run_elev "'$vdir/bin/python' -m pip install --upgrade pip setuptools wheel" || true
  else
    "$py" -m venv "$vdir" || return 1
    "$vdir/bin/python" -m pip install --upgrade pip setuptools wheel || true
  fi
}

info "Creating/updating virtualenv at: $VENV_DIR"
if ! create_venv "$PY_BIN" "$VENV_DIR"; then
  warn "Virtualenv creation failed. Attempting to install python3-venv for your distro..."
  if command -v apt-get >/dev/null 2>&1; then
    run_elev "apt-get update -y && apt-get install -y python3-venv" || error "Failed to install python3-venv"
  elif command -v dnf >/dev/null 2>&1; then
    run_elev "dnf install -y python3-venv || true"
  elif command -v pacman >/dev/null 2>&1; then
    run_elev "pacman -S --noconfirm python-virtualenv || true"
  else
    error "Please install your distro's python venv package and re-run."
  fi
  info "Retrying virtualenv creation..."
  create_venv "$PY_BIN" "$VENV_DIR" || error "Virtualenv creation still failing."
fi

# ---------- install requirements into venv ---------------------
REQ_FILE="$TMP_DIR/requirements.txt"
if [[ -f "$REQ_FILE" ]]; then
  info "Installing Python dependencies into venv..."
  set +e
  if [[ "$MODE" == "system" ]]; then
    run_elev "'$PY_VENV' -m pip install -r '$REQ_FILE' --no-warn-script-location"
    RC=$?
  else
    "$PY_VENV" -m pip install -r "$REQ_FILE" --no-warn-script-location
    RC=$?
  fi
  set -e
  [[ $RC -eq 0 ]] || error "Dependency installation failed (vended into virtualenv)."
else
  warn "No requirements.txt found — skipping dependency installation."
fi

# ---------- link venv site-packages via .pth (ensure importable) ----------
info "Linking install root into venv site-packages (.pth)"
SITE_PKGS="$("$PY_VENV" - <<'PY'
import sysconfig
p = sysconfig.get_paths().get('purelib') or sysconfig.get_paths().get('platlib') or ''
print(p)
PY
)"
if [[ -n "$SITE_PKGS" && -d "$SITE_PKGS" ]]; then
  PTH_FILE="$SITE_PKGS/bashbard_install_root.pth"
  if [[ "$MODE" == "system" ]]; then
    # create tmp file then move with elevation to avoid piping through sudo/awk quirks
    echo "$INSTALL_ROOT" > "$TMP_DIR/bashbard_install_root.pth"
    run_elev "mkdir -p '$(dirname "$PTH_FILE")' && mv '$TMP_DIR/bashbard_install_root.pth' '$PTH_FILE'"
  else
    echo "$INSTALL_ROOT" > "$PTH_FILE"
  fi
  info "Linked site-packages via .pth: $PTH_FILE"
else
  warn "Could not determine site-packages directory; launcher will set PYTHONPATH."
fi

# ---------- secure .env (0600) and initial content -------------------------
info "Configuring environment file: $ENV_PATH"
mkdir -p "$(dirname "$ENV_PATH")" 2>/dev/null || true

emit_env() {
  cat <<EOF
# BashBard environment
LLM_PROVIDER=${DEFAULT_LLM_PROVIDER}
GOOGLE_API_KEY=${PRESEEDED_GOOGLE_KEY}
GOOGLE_MODEL=${DEFAULT_GOOGLE_MODEL}
OPENAI_API_KEY=${PRESEEDED_OPENAI_KEY}
OPENAI_MODEL=${DEFAULT_OPENAI_MODEL}
DRY_RUN=0
EOF
}

create_or_keep_env() {
  if [[ ! -f "$ENV_PATH" ]]; then
    if [[ "$MODE" == "system" ]]; then
      # write tmp locally then move with elevation
      emit_env > "$TMP_DIR/env.new"
      run_elev "install -m 600 '$TMP_DIR/env.new' '$ENV_PATH'"
      run_elev "chmod 600 '$ENV_PATH' || true"
    else
      emit_env > "$ENV_PATH"
      chmod 600 "$ENV_PATH" || true
    fi
    success "Created .env at $ENV_PATH (0600)"
  else
    if [[ "$MODE" == "system" ]]; then run_elev "chmod 600 '$ENV_PATH' || true"; else chmod 600 "$ENV_PATH" || true; fi
    warn ".env already exists — keeping existing values (permissions set to 0600)."
  fi
}
create_or_keep_env

# ---------- helper: safely set key in env using python (local write then elevate) ----
# Usage: set_env_key KEY VALUE
set_env_key() {
  local key="$1" value="$2"
  # produce tmp file locally using python to avoid awk quoting issues
  "$PY_BIN" - <<PY > "$TMP_DIR/env.updated"
import io,sys
p = "$ENV_PATH"
key = "$key"
val = "$value".replace('"', '\\"')
out = []
try:
    with open(p, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
except FileNotFoundError:
    lines = []
done = False
for ln in lines:
    if ln.startswith(key + "="):
        out.append(f"{key}={val}")
        done = True
    else:
        out.append(ln)
if not done:
    out.append(f"{key}={val}")
print("\\n".join(out))
PY
  # move into place with elevation if needed
  if [[ "$MODE" == "system" ]]; then
    run_elev "mv '$TMP_DIR/env.updated' '$ENV_PATH' && chmod 600 '$ENV_PATH' || true"
  else
    mv "$TMP_DIR/env.updated" "$ENV_PATH"
    chmod 600 "$ENV_PATH" || true
  fi
}

# ---------- prompt for missing keys (interactive) -------------------------
if [[ -z "$NONINTERACTIVE" && -t 0 && -t 1 ]]; then
  # load existing env values safely
  # shellcheck disable=SC1090
  . "$ENV_PATH" || true
  # prompt depending on provider
  if [[ "${LLM_PROVIDER:-$DEFAULT_LLM_PROVIDER}" == "google" && -z "${GOOGLE_API_KEY:-}" ]]; then
    read -srp "🔑 Enter Google Gemini API key (or Enter to skip): " GEMINI_KEY || true; echo
    if [[ -n "${GEMINI_KEY:-}" ]]; then set_env_key "GOOGLE_API_KEY" "$GEMINI_KEY"; success "Saved Google key to $ENV_PATH"; fi
  elif [[ "${LLM_PROVIDER:-$DEFAULT_LLM_PROVIDER}" == "openai" && -z "${OPENAI_API_KEY:-}" ]]; then
    read -srp "🔑 Enter OpenAI API key (or Enter to skip): " OAI_KEY || true; echo
    if [[ -n "${OAI_KEY:-}" ]]; then set_env_key "OPENAI_API_KEY" "$OAI_KEY"; success "Saved OpenAI key to $ENV_PATH"; fi
  fi
else
  warn "Non-interactive install; launcher will prompt for missing API key(s) on first run."
fi

# ---------- launcher (venv + PYTHONPATH guard) -----------------------------
LAUNCHER='#!/usr/bin/env bash
set -euo pipefail
PKG_PARENT="__PKG_PARENT__"
ENV_PATH="${PKG_PARENT}/.env"
VENV="${PKG_PARENT}/venv"
PY="${VENV}/bin/python"

# check venv
if [[ ! -x "${PY}" ]]; then
  echo "❌ Virtualenv missing at ${VENV}. Reinstall BashBard." >&2
  exit 1
fi

# ensure .env exists
mkdir -p "$(dirname "${ENV_PATH}")" 2>/dev/null || true
if [[ ! -f "${ENV_PATH}" ]]; then
  umask 177
  cat > "${ENV_PATH}" <<EOF
LLM_PROVIDER=google
GOOGLE_API_KEY=
GOOGLE_MODEL=gemini-2.5-flash-lite
OPENAI_API_KEY=
OPENAI_MODEL=gpt-4o-mini
DRY_RUN=0
EOF
  chmod 600 "${ENV_PATH}" || true
fi

# helper to set key in env (append/update)
set_kv() {
  local k="$1" v="$2"
  # write locally then move
  python3 - <<PY > "${PKG_PARENT}/.env.tmp"
import os
p = "${ENV_PATH}"
k = "${k}"
v = "${v}".replace('"', '\\"')
try:
    with open(p, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
except FileNotFoundError:
    lines = []
done=False
out=[]
for ln in lines:
    if ln.startswith(k + "="):
        out.append(f"{k}={v}")
        done=True
    else:
        out.append(ln)
if not done:
    out.append(f"{k}={v}")
print("\\n".join(out))
PY
  mv "${PKG_PARENT}/.env.tmp" "${ENV_PATH}" || true
  chmod 600 "${ENV_PATH}" || true
}

# prompt for missing key if interactive
if [[ -t 0 && -t 1 ]]; then
  set -a; . "${ENV_PATH}"; set +a
  if [[ "${LLM_PROVIDER:-google}" == "google" && -z "${GOOGLE_API_KEY:-}" ]]; then
    printf "🔑 Enter your Google Gemini API key: " >/dev/tty 2>/dev/null || true
    IFS= read -rs key </dev/tty || true; echo
    if [[ -n "${key:-}" ]]; then set_kv "GOOGLE_API_KEY" "${key}"; export GOOGLE_API_KEY="${key}"; fi
  elif [[ "${LLM_PROVIDER:-google}" == "openai" && -z "${OPENAI_API_KEY:-}" ]]; then
    printf "🔑 Enter your OpenAI API key: " >/dev/tty 2>/dev/null || true
    IFS= read -rs key </dev/tty || true; echo
    if [[ -n "${key:-}" ]]; then set_kv "OPENAI_API_KEY" "${key}"; export OPENAI_API_KEY="${key}"; fi
  fi
fi

# Ensure package import visibility (also handled by .pth)
if [[ -n "${PYTHONPATH:-}" ]]; then
  export PYTHONPATH="${PKG_PARENT}:${PYTHONPATH}"
else
  export PYTHONPATH="${PKG_PARENT}"
fi

exec "${PY}" -m BashBard "$@"
'

info "Creating launcher in: $BIN_DIR"
if [[ "$MODE" == "system" ]]; then
  run_elev "mkdir -p '$BIN_DIR' && printf '%s\n' \"${LAUNCHER/__PKG_PARENT__/$INSTALL_ROOT}\" > '$BIN_DIR/BashBard' && chmod 0755 '$BIN_DIR/BashBard'"
else
  mkdir -p "$BIN_DIR"
  printf '%s\n' "${LAUNCHER/__PKG_PARENT__/$INSTALL_ROOT}" > "$BIN_DIR/BashBard"
  chmod 0755 "$BIN_DIR/BashBard"
fi

# lowercase convenience: create symlink or small wrapper
if ln -sf "BashBard" "$BIN_DIR/bashbard" 2>/dev/null; then :; else
  if [[ "$MODE" == "system" ]]; then
    run_elev "printf '%s\n' '#!/usr/bin/env bash' 'exec BashBard \"\$@\"' > '$BIN_DIR/bashbard' && chmod 0755 '$BIN_DIR/bashbard'"
  else
    cat > "$BIN_DIR/bashbard" <<'EOW'
#!/usr/bin/env bash
exec BashBard "$@"
EOW
    chmod 0755 "$BIN_DIR/bashbard"
  fi
fi

# ---------- persist PATH for user shells ---------------------------
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
  # fish
  if command -v fish >/dev/null 2>&1; then
    FISH_CFG="$HOME/.config/fish/config.fish"
    if ! grep -qs 'set -gx PATH $HOME/.local/bin $PATH' "$FISH_CFG" 2>/dev/null; then
      mkdir -p "$(dirname "$FISH_CFG")"
      echo 'set -gx PATH $HOME/.local/bin $PATH' >> "$FISH_CFG"
      success "Added ~/.local/bin to PATH in fish config"
    fi
  fi
fi

# ---------- done ------------------------------------------------------------
echo
success "BashBard installed successfully!"
if command -v BashBard >/dev/null 2>&1 || command -v bashbard >/dev/null 2>&1; then
  echo -e "${CYAN}💡 Run now:${RESET}  BashBard --help  ${CYAN}or${RESET}  bashbard --help"
  echo -e "${CYAN}💡 First run will prompt for missing API key(s) and save to:${RESET}  $ENV_PATH"
else
  warn "Your PATH may not include $BIN_DIR."
  echo -e "${CYAN}👉 Run by absolute path:${RESET}  $BIN_DIR/BashBard --help"
  echo -e "${CYAN}👉 Or export PATH for this shell:${RESET}  export PATH=\"$BIN_DIR:\$PATH\""
fi
