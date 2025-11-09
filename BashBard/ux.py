"""
Lightweight ANSI styling helpers for a consistent, professional CLI UX.

- Color output only when supported (TTY, not TERM=dumb, NO_COLOR unset; FORCE_COLOR overrides)
- Left-aligned bracket labels like [LLM] (no padding / no right-justify tricks)
- Helpers for headers, labels, key/value lines, hints, and progress lines
"""

from __future__ import annotations

import os
import re
import sys
from shutil import get_terminal_size


# ------- color capability detection -------

def _supports_color(stream) -> bool:
    # Explicit opt-out
    if os.getenv("NO_COLOR") is not None:
        return False
    # Explicit opt-in
    if os.getenv("FORCE_COLOR") is not None:
        return True
    # TERM must not be "dumb"
    if os.getenv("TERM", "").lower() == "dumb":
        return False
    try:
        return hasattr(stream, "isatty") and stream.isatty()
    except Exception:
        return False


_COLOR_ENABLED = _supports_color(sys.stdout)

# Simple ANSI set
class SGR:
    RESET = "\x1b[0m"
    BOLD = "\x1b[1m"
    DIM = "\x1b[2m"
    UNDERLINE = "\x1b[4m"

    # Basic colors (8/16-color safe)
    RED = "\x1b[31m"
    GREEN = "\x1b[32m"
    YELLOW = "\x1b[33m"
    BLUE = "\x1b[34m"
    MAGENTA = "\x1b[35m"
    CYAN = "\x1b[36m"
    GRAY = "\x1b[90m"


def _apply(text: str, *codes: str) -> str:
    if not text or not _COLOR_ENABLED:
        return text
    return "".join(codes) + text + SGR.RESET


# ------- public primitives -------

def style(text: str, *codes: str) -> str:
    return _apply(text, *codes)

def bold(text: str) -> str:
    return _apply(text, SGR.BOLD)

def dim(text: str) -> str:
    # Use gray (90) instead of true DIM when available for better readability on dark themes
    return _apply(text, SGR.GRAY)

def code(text: str) -> str:
    # Teal-ish for commands/paths
    return _apply(text, SGR.CYAN)

def success(text: str) -> str:
    return _apply(text, SGR.GREEN)

def warn(text: str) -> str:
    return _apply(text, SGR.YELLOW)

def error(text: str) -> str:
    return _apply(text, SGR.RED)

def info(text: str) -> str:
    return _apply(text, SGR.BLUE)

def hint(text: str) -> str:
    # softer, dim hint
    return dim(text)


# ------- higher-level helpers -------

def label(name: str, kind: str = "info") -> str:
    """
    Left-aligned, bracketed label: [NAME]
    (No right-justification or carriage-return tricks, so it never drifts.)
    """
    n = (name or "").upper()
    if kind == "success":
        return _apply(f"[{n}]", SGR.BOLD, SGR.GREEN)
    if kind == "warning":
        return _apply(f"[{n}]", SGR.BOLD, SGR.YELLOW)
    if kind == "danger":
        return _apply(f"[{n}]", SGR.BOLD, SGR.RED)
    if kind == "muted":
        return _apply(f"[{n}]", SGR.GRAY)
    # default: info
    return _apply(f"[{n}]", SGR.BOLD, SGR.CYAN)


def header(title: str, kind: str = "info") -> str:
    """
    Single-line header with color and emphasis.
    """
    t = bold(title)
    if kind == "danger":
        return _apply(t, SGR.RED)
    if kind == "success":
        return _apply(t, SGR.GREEN)
    if kind == "warning":
        return _apply(t, SGR.YELLOW)
    return _apply(t, SGR.CYAN)


def progress(phase: str, message: str) -> str:
    """
    Left-aligned progress line, e.g.:
      [LLM] Contacting provider... (timeout 30s)
    Always starts at column 0; no centering/padding.
    """
    return f"{label(phase, 'info')} {message}"


def bullet(text_line: str) -> str:
    return f"  - {text_line}"


def kv_line(key: str, value: str, key_width: int = 10) -> str:
    k = _apply(f"{key:<{key_width}}", SGR.GRAY)
    return f"  {k} {value}"


def indent(text: str, spaces: int = 2) -> str:
    pad = " " * max(0, spaces)
    return "\n".join(pad + ln if ln else ln for ln in (text or "").splitlines())


def strip_ansi(text: str) -> str:
    # Remove ANSI sequences for logs or width calc
    return re.sub(r"\x1b\[[0-9;]*m", "", text or "")


def term_width(default: int = 80) -> int:
    try:
        return get_terminal_size().columns or default
    except Exception:
        return default


__all__ = [
    "SGR",
    "style",
    "bold",
    "dim",
    "code",
    "success",
    "warn",
    "error",
    "info",
    "hint",
    "label",
    "header",
    "progress",
    "bullet",
    "kv_line",
    "indent",
    "strip_ansi",
    "term_width",
]
