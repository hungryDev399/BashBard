#!/usr/bin/env bash
# ==========================================================
#  BashBard Installer (final hardened, pretty-TUI)
#  - PEP 668/Kali-safe: always uses venv
#  - Secure .env (0600), hidden API prompts
#  - Avoids sudo+awk quoting issues (uses Python patcher)
#  - Ensures importability (.pth + PYTHONPATH)
#  - Installs UI extras: rich, prompt_toolkit
#  - Works user/system; keeps your UX and colors
# ==========================================================

# Re-exec with bash if invoked by sh/dash
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail
umask 022

REPO_URL="${BASHBARD_REPO_URL:-https://github.com/5afagy/BashBard.git}"
TMP_DIR="$(mktemp -d -t bashbard-install-XXXXXX)"
cleanup(){ [[ -d "${TMP_DIR:-}" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Colors + helpers
GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[1;31m'; CYAN=$'\033[1;36m'; RESET=$'\033[0m'
info(){ echo -e "${CYAN}➡${RESET} $*"; }
warn(){ echo -e "${YELLOW}⚠${RESET} $*"; }
error(){ echo -e "${RED}❌${RESET} $*" >&2; exit 1; }
success(){ echo -e "${GREEN}✅${RESET} $*"; }

usage() {
  cat <<'USAGE'
Usage:
  ./install.sh [user|system]

Modes:
  user   → installs to ~/.local (default)
  system → installs to /usr/local (requires sudo or su)

Env (optional):
  BASHBARD_REPO_URL=...           # override repo
  LLM_PROVIDER=google|openai      # default: google
  GOOGLE_API_KEY=...              # preseed key (optional)
  OPENAI_API_KEY=...              # preseed key (optional)
USAGE
}

MODE="${1:-user}"
case "$MODE" in
  user|system) ;;
  -h|--help|help) usage; exit 0 ;;
  *) warn "Unknown mode '$MODE' — defaulting to 'user'"; MODE="user" ;;
esac

# Python and git
PY="${PYTHON:-python3}"
command -v "$PY" >/dev/null 2>&1 || error "Python 3 not found."
command -v git >/dev/null 2>&1 || warn "git not found — if clone fails, install git."

# Elevation command
SUDO=""
if [[ "$MODE" == "system" ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  elif command -v su >/dev/null 2>&1; then
    SUDO="su -c"
  else
    error "System mode requires sudo or su."
  fi
fi

# Paths
if [[ "$MODE" == "system" ]]; then
  INSTALL_ROOT="/usr/local/share/bashbard"
  BIN_DIR="/usr/local/bin"
else
  INSTALL_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/bashbard"
  BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
fi
BIN_MAIN="$BIN_DIR/BashBard"
BIN_LOWER="$BIN_DIR/bashbard"
ENV_PATH="$INSTALL_ROOT/.env"
VENV_DIR="$INSTALL_ROOT/venv"
PY_VENV="$VENV_DIR/bin/python"
PIP_VENV="$VENV_DIR/bin/pip"

# Show python/pip info
"$PY" -m pip --version >/dev/null 2>&1 || "$PY" -m ensurepip --upgrade >/dev/null 2>&1 || true
info "Using Python: $("$PY" -c 'import sys; print(sys.executable)')"
info "Pip version:  $("$PY" -m pip --version || echo 'unknown')"

# Download
info "Downloading BashBard from GitHub..."
if ! git clone --depth=1 "$REPO_URL" "$TMP_DIR" >/dev/null 2>&1; then
  error "Failed to clone repository. Check network or install git."
fi
[[ -d "$TMP_DIR/BashBard" ]] || error "Repository structure invalid (missing BashBard/)."

# Install files
info "Installing BashBard package to: $INSTALL_ROOT"
if [[ -n "$SUDO" ]]; then
  $SUDO "mkdir -p '$INSTALL_ROOT'"
  $SUDO "rm -rf '$INSTALL_ROOT/BashBard'"
  $SUDO "cp -a '$TMP_DIR/BashBard' '$INSTALL_ROOT/'"
else
  mkdir -p "$INSTALL_ROOT"
  rm -rf "$INSTALL_ROOT/BashBard"
  cp -a "$TMP_DIR/BashBard" "$INSTALL_ROOT/"
fi

# Create a dedicated venv (PEP 668 safe)
create_venv() {
  if [[ -n "$SUDO" ]]; then
    $SUDO "'$PY' -m venv '$VENV_DIR'" || return 1
    $SUDO "'$PY_VENV' -m pip install --upgrade pip setuptools wheel" >/dev/null 2>&1 || true
  else
    "$PY" -m venv "$VENV_DIR" || return 1
    "$PY_VENV" -m pip install --upgrade pip setuptools wheel >/dev/null 2>&1 || true
  fi
}
info "Creating virtual environment: $VENV_DIR"
if ! create_venv; then
  warn "venv creation failed. On Debian/Ubuntu/Kali install: sudo apt-get install python3-venv"
  error "Virtualenv creation failed."
fi

# Install dependencies into venv (never system pip)
REQ_FILE="$TMP_DIR/requirements.txt"
if [[ -f "$REQ_FILE" ]]; then
  info "Installing dependencies into venv..."
  set +e
  if [[ -n "$SUDO" ]]; then
    $SUDO "'$PY_VENV' -m pip install -r '$REQ_FILE' --no-warn-script-location"
  else
    "$PY_VENV" -m pip install -r "$REQ_FILE" --no-warn-script-location
  fi
  RC=$?; set -e
  [[ $RC -eq 0 ]] || error "Failed to install one or more dependencies into the virtualenv."
else
  warn "No requirements.txt; skipping dependency install."
fi

# UI extras for pretty TUI
info "Ensuring UI extras (rich, prompt_toolkit) are installed..."
set +e
"$PY_VENV" - <<'PY'
import importlib, sys
missing=[m for m in ("rich","prompt_toolkit") if importlib.util.find_spec(m) is None]
print(" ".join(missing))
PY
MISSING="$("$PY_VENV" - <<'PY'
import importlib
print(" ".join([m for m in ("rich","prompt_toolkit") if importlib.util.find_spec(m) is None]))
PY
)"
set -e
if [[ -n "$MISSING" ]]; then
  info "Installing UI extras into venv: $MISSING"
  if [[ -n "$SUDO" ]]; then
    $SUDO "'$PY_VENV' -m pip install --no-warn-script-location $MISSING"
  else
    "$PY_VENV" -m pip install --no-warn-script-location $MISSING
  fi
fi

# Make package importable:
# 1) Write .pth to venv site-packages
SITE_PKGS="$("$PY_VENV" - <<'PY'
import sysconfig
print(sysconfig.get_paths().get('purelib') or sysconfig.get_paths().get('platlib') or '')
PY
)"
if [[ -n "$SITE_PKGS" && -d "$SITE_PKGS" ]]; then
  PTH_FILE="$SITE_PKGS/bashbard_install_root.pth"
  echo "$INSTALL_ROOT" > "$TMP_DIR/bashbard_install_root.pth"
  if [[ -n "$SUDO" ]]; then
    $SUDO "mkdir -p '$(dirname "$PTH_FILE")' && mv '$TMP_DIR/bashbard_install_root.pth' '$PTH_FILE'"
  else
    mv "$TMP_DIR/bashbard_install_root.pth" "$PTH_FILE"
  fi
  info "Linked site-packages via .pth: $PTH_FILE"
else
  warn "Could not determine site-packages; launcher will export PYTHONPATH."
fi

# 2) Secure .env (0600), create if missing
info "Configuring BashBard environment..."
if [[ ! -f "$ENV_PATH" ]]; then
  if [[ -n "$SUDO" ]]; then
    $SUDO "mkdir -p '$(dirname "$ENV_PATH")'"
    printf '%s\n' "# Agentic BashBard environment configuration" \
                  "# Automatically generated during installation" \
                  "" \
                  "LLM_PROVIDER=${LLM_PROVIDER:-google}" \
                  "GOOGLE_API_KEY=${GOOGLE_API_KEY:-}" \
                  "GOOGLE_MODEL=${GOOGLE_MODEL:-gemini-2.5-flash-lite}" \
                  "OPENAI_API_KEY=${OPENAI_API_KEY:-}" \
                  "OPENAI_MODEL=${OPENAI_MODEL:-gpt-4o-mini}" \
                  "DRY_RUN=0" > "$TMP_DIR/.env.new"
    $SUDO "install -m 600 '$TMP_DIR/.env.new' '$ENV_PATH'"
  else
    mkdir -p "$(dirname "$ENV_PATH")"
    install -m 600 /dev/null "$ENV_PATH"
    cat > "$ENV_PATH" <<EOF
# Agentic BashBard environment configuration
# Automatically generated during installation

LLM_PROVIDER=${LLM_PROVIDER:-google}
GOOGLE_API_KEY=${GOOGLE_API_KEY:-}
GOOGLE_MODEL=${GOOGLE_MODEL:-gemini-2.5-flash-lite}
OPENAI_API_KEY=${OPENAI_API_KEY:-}
OPENAI_MODEL=${OPENAI_MODEL:-gpt-4o-mini}
DRY_RUN=0
EOF
    chmod 600 "$ENV_PATH" || true
  fi
  success "Created .env at $ENV_PATH (0600)"
else
  if [[ -n "$SUDO" ]]; then $SUDO "chmod 600 '$ENV_PATH'" || true; else chmod 600 "$ENV_PATH" || true; fi
  warn ".env already exists — keeping existing values (permissions set to 0600)."
fi

# Prompt during install only if interactive; otherwise defer to first run
if [[ -t 0 && -t 1 ]]; then
  echo ""
  read -srp "🔑 Enter your Google Gemini API key (or press Enter to skip): " GEMINI_KEY || true
  echo ""
  if [[ -n "${GEMINI_KEY:-}" ]]; then
    "$PY" - <<PY > "$TMP_DIR/.env.updated"
import sys
p = r"""$ENV_PATH"""
key = "GOOGLE_API_KEY"
val = r"""$GEMINI_KEY""".replace('"','\\"')
try:
    with open(p, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
except FileNotFoundError:
    lines = []
done=False
out=[]
for ln in lines:
    if ln.startswith(key+"="):
        out.append(f"{key}={val}")
        done=True
    else:
        out.append(ln)
if not done:
    out.append(f"{key}={val}")
print("\\n".join(out))
PY
    if [[ -n "$SUDO" ]]; then
      $SUDO "mv '$TMP_DIR/.env.updated' '$ENV_PATH' && chmod 600 '$ENV_PATH' || true"
    else
      mv "$TMP_DIR/.env.updated" "$ENV_PATH"
      chmod 600 "$ENV_PATH" || true
    fi
    success "Gemini API key saved to $ENV_PATH"
  else
    warn "No API key entered now; launcher will prompt on first run."
  fi
else
  warn "Non-interactive install; launcher will prompt for API key on first run."
fi

# --- Hardened launcher (venv, PYTHONPATH, pretty TTY, hidden prompt) ---
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

# Create minimal .env if missing (0600)
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

# helper to set key in .env (safe)
set_kv(){
  local k="$1" v="$2"
  python3 - "$k" "$v" "${ENV_PATH}" <<'PY'
import sys
k, v, p = sys.argv[1], sys.argv[2].replace('"','\\"'), sys.argv[3]
try:
  with open(p,"r",encoding="utf-8") as f:
    lines=f.read().splitlines()
except FileNotFoundError:
  lines=[]
done=False; out=[]
for ln in lines:
  if ln.startswith(k+"="):
    out.append(f"{k}={v}"); done=True
  else:
    out.append(ln)
if not done:
  out.append(f"{k}={v}")
with open(p+".tmp","w",encoding="utf-8") as f:
  f.write("\\n".join(out))
PY
  mv "${ENV_PATH}.tmp" "${ENV_PATH}" || true
  chmod 600 "${ENV_PATH}" || true
}

# Export env vars
set -a
. "${ENV_PATH}"
set +a

# Pretty TTY defaults
export PYTHONUTF8=1
export PYTHONIOENCODING=UTF-8
export RICH_FORCE_TERMINAL=1
export TERM="${TERM:-xterm-256color}"

# First-run hidden prompts (if interactive)
if [[ -t 0 && -t 1 ]]; then
  if [[ "${LLM_PROVIDER:-google}" == "google" && -z "${GOOGLE_API_KEY:-}" ]]; then
    printf "🔑 Enter your Google Gemini API key: " >/dev/tty
    IFS= read -rs key </dev/tty || true; echo >/dev/tty
    if [[ -n "${key:-}" ]]; then set_kv "GOOGLE_API_KEY" "${key}"; export GOOGLE_API_KEY="${key}"; fi
  elif [[ "${LLM_PROVIDER:-google}" == "openai" && -z "${OPENAI_API_KEY:-}" ]]; then
    printf "🔑 Enter your OpenAI API key: " >/dev/tty
    IFS= read -rs key </dev/tty || true; echo >/dev/tty
    if [[ -n "${key:-}" ]]; then set_kv "OPENAI_API_KEY" "${key}"; export OPENAI_API_KEY="${key}"; fi
  fi
fi

# Ensure import visibility (.pth should handle this; PYTHONPATH as safety net)
if [[ -n "${PYTHONPATH:-}" ]]; then
  export PYTHONPATH="${PKG_PARENT}:${PYTHONPATH}"
else
  export PYTHONPATH="${PKG_PARENT}"
fi

exec "${PY}" -m BashBard "$@"
'

info "Creating launcher(s) in: $BIN_DIR"
if [[ -n "$SUDO" ]]; then
  $SUDO "mkdir -p '$BIN_DIR'"
  printf '%s\n' "${LAUNCHER/__PKG_PARENT__/$INSTALL_ROOT}" > "$TMP_DIR/launcher.new"
  $SUDO "mv '$TMP_DIR/launcher.new' '$BIN_MAIN' && chmod 0755 '$BIN_MAIN'"
else
  mkdir -p "$BIN_DIR"
  printf '%s\n' "${LAUNCHER/__PKG_PARENT__/$INSTALL_ROOT}" > "$BIN_MAIN"
  chmod 0755 "$BIN_MAIN"
fi

# Lowercase convenience (symlink or wrapper)
if [[ -n "$SUDO" ]]; then
  if $SUDO ln -sf "BashBard" "$BIN_LOWER" 2>/dev/null; then :; else
    printf '%s\n' '#!/usr/bin/env bash' 'exec BashBard "$@"' > "$TMP_DIR/bashbard.new"
    $SUDO "mv '$TMP_DIR/bashbard.new' '$BIN_LOWER' && chmod 0755 '$BIN_LOWER'"
  fi
else
  if ln -sf "BashBard" "$BIN_LOWER" 2>/dev/null; then :; else
    cat > "$BIN_LOWER" <<'EOW'
#!/usr/bin/env bash
exec BashBard "$@"
EOW
    chmod 0755 "$BIN_LOWER"
  fi
fi

# Make runnable now (try a shim in a PATH dir)
is_on_path(){ case ":$PATH:" in *":$1:"*) return 0;; *) return 1;; esac; }
make_shim(){
  local target="$1" dest="$2" name="$3"
  mkdir -p "$dest" 2>/dev/null || true
  if ln -sf "$target" "$dest/$name" 2>/dev/null; then :; else
    cat > "$dest/$name" <<EOF
#!/usr/bin/env bash
exec "$target" "\$@"
EOF
    chmod 0755 "$dest/$name"
  fi
}

activate_now=false
if is_on_path "$BIN_DIR"; then
  activate_now=true
else
  if is_on_path "/usr/local/bin"; then
    if ln -sf "$BIN_MAIN" "/usr/local/bin/BashBard" 2>/dev/null && ln -sf "$BIN_MAIN" "/usr/local/bin/bashbard" 2>/dev/null; then
      activate_now=true
    elif [[ -n "$SUDO" ]]; then
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
        activate_now=true; break
      fi
    done
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

echo ""
success "BashBard installed successfully!"
if $activate_now; then
  echo -e "${CYAN}💡 Run now:${RESET}  BashBard --help  ${CYAN}or${RESET}  bashbard --help"
  echo -e "${CYAN}💡 First run will prompt for API key if missing and save to:${RESET}  $ENV_PATH"
else
  warn "Could not place a shim in a directory already on your current PATH."
  echo -e "${CYAN}👉 Run by absolute path:${RESET}  $BIN_MAIN --help"
  echo -e "${CYAN}👉 Or export PATH for this shell:${RESET}  export PATH=\"$BIN_DIR:\$PATH\""
fi
echo ""
success "Installation complete."
