"""
Lightweight ANSI styling helpers for a consistent, professional CLI UX.

- Color output only when supported (Linux TTY and NO_COLOR not set)
- Provide helpers for headers, labels, key/value blocks, prompts
"""

from __future__ import annotations

import os
import sys
from shutil import get_terminal_size


def _supports_color(stream) -> bool:
    if os.getenv("NO_COLOR") is not None:
        return False
    try:
        # Linux-only tool: prefer color on POSIX TTY
        return hasattr(stream, "isatty") and stream.isatty()
    except Exception:
        return False


_COLOR_ENABLED = _supports_color(sys.stdout)


class SGR:
    RESET = "\x1b[0m"
    BOLD = "\x1b[1m"
    DIM = "\x1b[2m"
    UNDERLINE = "\x1b[4m"
    # Colors
    RED = "\x1b[31m"
    GREEN = "\x1b[32m"
    YELLOW = "\x1b[33m"
    BLUE = "\x1b[34m"
    MAGENTA = "\x1b[35m"
    CYAN = "\x1b[36m"
    GRAY = "\x1b[90m"


def style(text: str, *codes: str) -> str:
    if not _COLOR_ENABLED or not text:
        return text
    return "".join(codes) + text + SGR.RESET


def bold(text: str) -> str:
    return style(text, SGR.BOLD)


def dim(text: str) -> str:
    return style(text, SGR.GRAY)


def code(text: str) -> str:
    return style(text, SGR.CYAN)


def success(text: str) -> str:
    return style(text, SGR.GREEN)


def warn(text: str) -> str:
    return style(text, SGR.YELLOW)


def error(text: str) -> str:
    return style(text, SGR.RED)


def label(name: str, kind: str = "info") -> str:
    name = name.upper()
    if kind == "success":
        return style(f"[{name}]", SGR.BOLD, SGR.GREEN)
    if kind == "warning":
        return style(f"[{name}]", SGR.BOLD, SGR.YELLOW)
    if kind == "danger":
        return style(f"[{name}]", SGR.BOLD, SGR.RED)
    if kind == "muted":
        return style(f"[{name}]", SGR.GRAY)
    return style(f"[{name}]", SGR.BOLD, SGR.CYAN)


def header(title: str, kind: str = "info") -> str:
    """Single-line header with color and emphasis."""
    if kind == "danger":
        return style(bold(title), SGR.RED)
    if kind == "success":
        return style(bold(title), SGR.GREEN)
    if kind == "warning":
        return style(bold(title), SGR.YELLOW)
    return style(bold(title), SGR.CYAN)


def bullet(text_line: str) -> str:
    return f"  - {text_line}"


def kv_line(key: str, value: str, key_width: int = 10) -> str:
    k = style(f"{key:<{key_width}}", SGR.GRAY)
    return f"  {k} {value}"


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
    "label",
    "header",
    "bullet",
    "kv_line",
    "term_width",
]


