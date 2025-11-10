#!/usr/bin/env bash
# ==========================================================
#  BashBard Installer (final, hardened, pip-safe, pretty-TUI)
#  - PEP 668/Kali-safe: always uses venv
#  - Robust pip bootstrap: ensurepip -> get-pip.py fallback
#  - Secure .env (0600), hidden API-key prompt & env seeding
#  - Ensures importability (.pth + PYTHONPATH)
#  - Installs UI extras: rich, prompt_toolkit (no importlib.util, no bash globs)
#  - git fallback to tarball
#  - Supports user/system modes
# ==========================================================

if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail
umask 022

REPO_URL="${BASHBARD_REPO_URL:-https://github.com/5afagy/BashBard}"
REPO_REF="${BASHBARD_REPO_REF:-refs/heads/main}"  # or refs/tags/vX.Y.Z
TMP_DIR="$(mktemp -d -t bashbard-install-XXXXXX)"
cleanup(){ [[ -d "${TMP_DIR:-}" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

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

Optional env:
  BASHBARD_REPO_URL=...           # override repo
  BASHBARD_REPO_REF=refs/tags/vX.Y.Z
  LLM_PROVIDER=google|openai      # default: google
  GOOGLE_API_KEY=...              # preseed key (optional)
  OPENAI_API_KEY=...              # preseed key (optional)
  GOOGLE_MODEL=gemini-2.5-flash-lite
  OPENAI_MODEL=gpt-4o-mini
  PYTHON=/path/to/python3         # override Python executable
USAGE
}

MODE="${1:-user}"
case "$MODE" in
  user|system) ;;
  -h|--help|help) usage; exit 0 ;;
  *) warn "Unknown mode '$MODE' — defaulting to 'user'"; MODE="user" ;;
esac

PY="${PYTHON:-python3}"
command -v "$PY" >/dev/null 2>&1 || error "Python 3 not found. Set PYTHON=/path/to/python3"
command -v curl >/dev/null 2>&1 || error "curl is required."

SUDO=""
if [[ "$MODE" == "system" ]]; then
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"
  elif command -v su >/dev/null 2>&1; then SUDO="su -c"
  else error "System mode requires sudo or su."; fi
fi

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

pm_cmd() {
  if   command -v apt-get >/dev/null 2>&1; then echo "apt-get -y"
  elif command -v dnf     >/dev/null 2>&1; then echo "dnf -y"
  elif command -v yum     >/dev/null 2>&1; then echo "yum -y"
  elif command -v pacman  >/dev/null 2>&1; then echo "pacman --noconfirm"
  elif command -v zypper  >/dev/null 2>&1; then echo "zypper -n"
  elif command -v apk     >/dev/null 2>&1; then echo "apk --no-cache"
  else echo ""; fi
}
pm_install() {
  local pkgs=("$@"); local pm; pm="$(pm_cmd)"
  [[ -z "$pm" ]] && return 1
  case "$pm" in
    apt-get*)   $SUDO $pm update >/dev/null 2>&1 || true; $SUDO $pm install "${pkgs[@]}" ;;
    dnf*|yum*)  $SUDO $pm install "${pkgs[@]}" ;;
    pacman*)    $SUDO $pm -Sy "${pkgs[@]}" ;;
    zypper*)    $SUDO $pm install -y "${pkgs[@]}" ;;
    apk*)       $SUDO $pm add "${pkgs[@]}" ;;
  esac
}

"$PY" -m pip --version >/dev/null 2>&1 || "$PY" -m ensurepip --upgrade >/dev/null 2>&1 || true
info "Using Python: $("$PY" -c 'import sys; print(sys.executable)')"
info "Pip version:  $("$PY" -m pip --version 2>/dev/null || echo 'not present (will be bootstrapped in venv)')"

fetch_source() {
  local dest="$1"
  info "Downloading BashBard..."
  if command -v git >/dev/null 2>&1; then
    if git clone --depth=1 "$REPO_URL" "$dest" >/dev/null 2>&1; then return 0; else warn "git clone failed; using tarball."; fi
  else
    warn "git not available; using tarball."
  fi
  local gh_path tar_ref
  gh_path="$(echo "$REPO_URL" | sed -E 's#https?://github.com/##')"
  tar_ref="${REPO_REF#refs/heads/}"
  curl -fsSL "https://codeload.github.com/${gh_path}/tar.gz/${tar_ref}" -o "$TMP_DIR/repo.tar.gz" || error "Failed to download tarball."
  mkdir -p "$dest.extracted"
  tar -xzf "$TMP_DIR/repo.tar.gz" -C "$dest.extracted"
  local top; top="$(find "$dest.extracted" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "$top" ]] || error "Unexpected tarball layout."
  mkdir -p "$dest"
  cp -a "$top"/* "$dest"/
}
fetch_source "$TMP_DIR"
[[ -d "$TMP_DIR/BashBard" ]] || error "Repository structure invalid (missing BashBard/)."

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

ensure_venv_module() {
  if "$PY" -c 'import venv' >/dev/null 2>&1; then return 0; fi
  warn "Python venv module missing; attempting to install."
  local pm; pm="$(pm_cmd)"
  if [[ -n "$pm" && -n "$SUDO" ]]; then
    case "$pm" in
      apt-get*)   pm_install python3-venv python3-pip || true ;;
      dnf*|yum*)  pm_install python3-venv python3-pip || pm_install python3-pip || true ;;
      pacman*)    pm_install python-virtualenv python-pip || pm_install python || true ;;
      zypper*)    pm_install python3-venv python3-pip || true ;;
      apk*)       pm_install python3 py3-virtualenv py3-pip || true ;;
    esac
  else
    warn "No privileges or package manager to install venv; continuing."
  fi
  "$PY" -c 'import venv' >/dev/null 2>&1 || error "venv module unavailable. Install (e.g. sudo apt-get install python3-venv) and rerun."
}

create_venv_and_pip() {
  ensure_venv_module
  if [[ -n "$SUDO" ]]; then $SUDO "'$PY' -m venv '$VENV_DIR'" || true
  else "$PY" -m venv "$VENV_DIR" || true; fi
  [[ -x "$PY_VENV" ]] || error "Virtualenv creation failed at $VENV_DIR"

  if ! "$PY_VENV" -m pip --version >/dev/null 2>&1; then
    info "Bootstrapping pip inside venv (ensurepip)..."
    set +e
    "$PY_VENV" -m ensurepip --upgrade --default-pip 2>/dev/null
    local rc=$?
    set -e
    if [[ $rc -ne 0 || ! "$PY_VENV" -m pip --version >/dev/null 2>&1 ]]; then
      info "ensurepip unavailable; falling back to get-pip.py..."
      curl -fsSL https://bootstrap.pypa.io/get-pip.py -o "$TMP_DIR/get-pip.py" || error "Failed to download get-pip.py"
      "$PY_VENV" "$TMP_DIR/get-pip.py" || error "get-pip.py failed to install pip in venv"
    fi
  fi
  "$PY_VENV" -m pip install -q --upgrade pip setuptools wheel || true
}
info "Creating virtual environment: $VENV_DIR"
create_venv_and_pip

REQ_FILE="$TMP_DIR/requirements.txt"
if [[ -f "$REQ_FILE" ]]; then
  info "Installing dependencies into venv..."
  "$PY_VENV" -m pip install -r "$REQ_FILE" --no-warn-script-location
else
  warn "No requirements.txt; skipping dependency install."
fi

# ---------- FIXED BLOCK: robust UI extras detection (no globs/patterns) ----------
info "Ensuring UI extras (rich, prompt_toolkit) are installed..."
MISSING="$("$PY_VENV" - <<'PY'
mods = ["rich", "prompt_toolkit"]
missing = []
for m in mods:
    try:
        __import__(m)
    except Exception:
        missing.append(m)
print(" ".join(missing))
PY
)"
declare -a PKGS=()
if [[ -n "$MISSING" ]]; then
  # iterate words safely; no [[ ... == *pattern* ]] needed
  for m in $MISSING; do
    if [[ "$m" == "rich" ]]; then PKGS+=("rich>=13.9"); fi
    if [[ "$m" == "prompt_toolkit" ]]; then PKGS+=("prompt_toolkit>=3.0"); fi
  done
  if ((${#PKGS[@]})); then
    "$PY_VENV" -m pip install --no-warn-script-location "${PKGS[@]}"
  fi
fi
# -------------------------------------------------------------------------------

SITE_PKGS="$("$PY_VENV" - <<'PY'
import sysconfig
print(sysconfig.get_paths().get('purelib') or sysconfig.get_paths().get('platlib') or '')
PY
)"
if [[ -n "$SITE_PKGS" && -d "$SITE_PKGS" ]]; then
  PTH_FILE="$SITE_PKGS/bashbard_install_root.pth"
  echo "$INSTALL_ROOT" > "$TMP_DIR/bashbard_install_root.pth"
  mv "$TMP_DIR/bashbard_install_root.pth" "$PTH_FILE"
  info "Linked site-packages via .pth: $PTH_FILE"
else
  warn "Could not determine site-packages; launcher will export PYTHONPATH."
fi

info "Configuring BashBard environment..."
if [[ ! -f "$ENV_PATH" ]]; then
  mkdir -p "$(dirname "$ENV_PATH")"
  install -m 600 /dev/null "$ENV_PATH"
  cat > "$ENV_PATH" <<EOF
# Agentic BashBard environment configuration
# Automatically generated during installation

LLM_PROVIDER=\${LLM_PROVIDER:-google}
GOOGLE_API_KEY=\${GOOGLE_API_KEY:-}
GOOGLE_MODEL=\${GOOGLE_MODEL:-gemini-2.5-flash-lite}
OPENAI_API_KEY=\${OPENAI_API_KEY:-}
OPENAI_MODEL=\${OPENAI_MODEL:-gpt-4o-mini}
DRY_RUN=0
EOF
  chmod 600 "$ENV_PATH" || true
  success "Created .env at $ENV_PATH (0600)"
else
  chmod 600 "$ENV_PATH" || true
  warn ".env already exists — keeping existing values (permissions set to 0600)."
fi

if [[ -t 0 && -t 1 ]]; then
  NEED_PROMPT="$("$PY" - <<PY
import os
env_path = r"""$ENV_PATH"""
provider = os.environ.get("LLM_PROVIDER","google")
want = (provider == "google")
val=""
try:
    with open(env_path, "r", encoding="utf-8") as f:
        for ln in f:
            if ln.startswith("GOOGLE_API_KEY="):
                val = ln.strip().split("=",1)[1]
                break
except FileNotFoundError:
    pass
print("yes" if (want and (val=='')) else "no")
PY
)"
  if [[ "$NEED_PROMPT" == "yes" ]]; then
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
        out.append(f"{key}={val}"); done=True
    else:
        out.append(ln)
if not done:
    out.append(f"{key}={val}")
print("\\n".join(out))
PY
      mv "$TMP_DIR/.env.updated" "$ENV_PATH"; chmod 600 "$ENV_PATH" || true
      success "Gemini API key saved to $ENV_PATH"
    else
      warn "No API key entered now; launcher will prompt on first run."
    fi
  fi
else
  warn "Non-interactive install; launcher will prompt for API key on first run."
fi

LAUNCHER='#!/usr/bin/env bash
set -euo pipefail
PKG_PARENT="__PKG_PARENT__"
ENV_PATH="${PKG_PARENT}/.env"
VENV="${PKG_PARENT}/venv"
PY="${VENV}/bin/python"
if [[ ! -x "${PY}" ]]; then
  echo "❌ Virtualenv missing at ${VENV}. Reinstall BashBard." >&2; exit 1
fi
mkdir -p "$(dirname "${ENV_PATH}")"
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
set -a
. "${ENV_PATH}"
set +a
export PYTHONUTF8=1
export PYTHONIOENCODING=UTF-8
export RICH_FORCE_TERMINAL=1
export TERM="${TERM:-xterm-256color}"
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
if [[ -n "${PYTHONPATH:-}" ]]; then export PYTHONPATH="${PKG_PARENT}:${PYTHONPATH}"
else export PYTHONPATH="${PKG_PARENT}"; fi
exec "${PY}" -m BashBard "$@"
'

info "Creating launcher(s) in: $BIN_DIR"
mkdir -p "$BIN_DIR"
printf '%s\n' "${LAUNCHER/__PKG_PARENT__/$INSTALL_ROOT}" > "$BIN_MAIN"
chmod 0755 "$BIN_MAIN"

if ln -sf "BashBard" "$BIN_LOWER" 2>/dev/null; then :; else
  cat > "$BIN_LOWER" <<'EOW'
#!/usr/bin/env bash
exec BashBard "$@"
EOW
  chmod 0755 "$BIN_LOWER"
fi

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
  echo -e "${CYAN}💡 First run will prompt for missing API key if needed and save to:${RESET}  $ENV_PATH"
else
  warn "Could not place a shim in a directory already on your current PATH."
  echo -e "${CYAN}👉 Run by absolute path:${RESET}  $BIN_MAIN --help"
  echo -e "${CYAN}👉 Or export PATH for this shell:${RESET}  export PATH=\"$BIN_DIR:\$PATH\""
fi
echo ""
success "Installation complete."
