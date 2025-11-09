#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./setup.sh [source_dir] [user|system]

source_dir: directory that contains the BashBard/ package folder (default: current dir)
mode      : "user" (default) installs to ~/.local; "system" installs to /usr/local (needs sudo)

What it does:
  1) Copies BashBard/ into a shared location
  2) Installs Python dependencies from requirements.txt if present
  3) Creates a 'BashBard' launcher on your PATH that runs: python3 -m BashBard
USAGE
}

SRC_DIR="${1:-$PWD}"
MODE="${2:-user}"

# --- Validate source ---
if [[ ! -d "$SRC_DIR/BashBard" ]]; then
  echo "❌ Could not find 'BashBard/' inside: $SRC_DIR"
  usage
  exit 1
fi

# --- Paths & permissions ---
if [[ "$MODE" == "system" ]]; then
  INSTALL_ROOT="/usr/local/share/bashbard"
  BIN_PATH="/usr/local/bin/BashBard"
  SUDO="sudo"
  PIP_PREFIX=()                 # system site-packages
else
  INSTALL_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/bashbard"
  BIN_PATH="$HOME/.local/bin/BashBard"
  SUDO=""
  PIP_PREFIX=(--user)           # user site-packages
fi

# --- Pick Python/Pip ---
PY="${PYTHON:-python3}"
if ! command -v "$PY" >/dev/null 2>&1; then
  echo "❌ '$PY' not found. Install Python 3 or set PYTHON=/path/to/python"
  exit 1
fi
PIP=( "$PY" -m pip )

echo "➡  Using Python: $("$PY" -c 'import sys; print(sys.executable)')"
echo "➡  Pip version:  $("${PIP[@]}" --version)"

# --- Copy package ---
echo "➡  Installing BashBard package to: $INSTALL_ROOT"
$SUDO mkdir -p "$INSTALL_ROOT"
$SUDO rm -rf "$INSTALL_ROOT/BashBard"
$SUDO cp -a "$SRC_DIR/BashBard" "$INSTALL_ROOT/"

# --- Ensure __main__.py exists hint (won't modify, just warn) ---
if [[ ! -f "$INSTALL_ROOT/BashBard/__main__.py" ]]; then
  echo "⚠  Note: '$INSTALL_ROOT/BashBard/__main__.py' not found."
  echo "    'python -m BashBard' will fail unless your entrypoint is in __main__.py."
  echo "    If your entry is in cli.py, edit the launcher below to use: -m BashBard.cli"
fi

# --- Install requirements if present ---
REQ_FILE=""
if [[ -f "$SRC_DIR/requirements.txt" ]]; then
  REQ_FILE="$SRC_DIR/requirements.txt"
elif [[ -f "$SRC_DIR/BashBard/requirements.txt" ]]; then
  REQ_FILE="$SRC_DIR/BashBard/requirements.txt"
fi

if [[ -n "$REQ_FILE" ]]; then
  echo "➡  Installing Python requirements from: $REQ_FILE"
  if [[ "$MODE" == "system" ]]; then
    # system-wide (requires sudo)
    $SUDO "${PIP[@]}" install -r "$REQ_FILE"
  else
    # user install
    "${PIP[@]}" install "${PIP_PREFIX[@]}" -r "$REQ_FILE"
  fi
else
  echo "ℹ  No requirements.txt found (skipping dependency install)."
fi

# --- Create launcher (adds our package parent to PYTHONPATH then runs module) ---
LAUNCHER='#!/usr/bin/env bash
set -euo pipefail
PKG_PARENT="__PKG_PARENT__"
# Make sure Python can import the copied BashBard package
if [[ -n "${PYTHONPATH:-}" ]]; then
  export PYTHONPATH="$PKG_PARENT:$PYTHONPATH"
else
  export PYTHONPATH="$PKG_PARENT"
fi
# Change this to BashBard.cli if you don\'t have __main__.py
exec /usr/bin/env python3 -m BashBard "$@"'

echo "➡  Writing launcher: $BIN_PATH"
if [[ "$MODE" == "system" ]]; then
  echo "${LAUNCHER/__PKG_PARENT__/$INSTALL_ROOT}" | sudo tee "$BIN_PATH" >/dev/null
  sudo chmod 0755 "$BIN_PATH"
else
  mkdir -p "$(dirname "$BIN_PATH")"
  printf '%s\n' "${LAUNCHER/__PKG_PARENT__/$INSTALL_ROOT}" > "$BIN_PATH"
  chmod 0755 "$BIN_PATH"
fi

echo "✅ Done. Try: BashBard"
if [[ "$MODE" != "system" ]]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) : ;;
    *) echo 'ℹ  Add to your shell rc if needed: export PATH="$HOME/.local/bin:$PATH"';;
  esac
fi
