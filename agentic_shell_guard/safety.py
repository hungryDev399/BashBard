from __future__ import annotations

import re
import shlex
from typing import Dict, List


DANGEROUS_PATTERNS: List[tuple[str, str]] = [
    (r"\brm\b[^\n]*\b(-rf|--no-preserve-root)\b[^\n]*/\s*$", "Recursive delete from root"),
    (r"\brm\b[^\n]*\b(-rf)?\b\s+(\*/\*|\*\s*$)", "Wildcard recursive delete"),
    (r"\bdd\b[^\n]*(of=)?/dev/sd[a-z]\b", "Raw disk write with dd"),
    (r"\bmkfs\.[a-z0-9]+\b", "Filesystem creation (mkfs)"),
    (r"\b(:\s*\(\)\s*\{\s*:\|:\s*;\s*\}\s*;\s*:)\b", "Fork bomb"),
    (r"\b(chown|chmod)\b[^\n]*\b-R\b[^\n]*/\s*$", "Recursive perm change at root"),
    (r"\bshred\b[^\n]*(/dev/sd[a-z]|/\s*$)", "Shred on device or root"),
    (r"\bshutdown\b|\breboot\b|\bhalt\b", "System power action"),
    (r"\bmount\b[^\n]*\b--bind\b[^\n]*/proc\b", "Risky bind mount proc"),
    (r"\buserdel\b[^\n]*\b--remove\b\s+\w+", "User delete with remove"),
    (r"\bkill\b\s+-9\s+1\b", "SIGKILL PID 1"),
    (r"\b(echo|printf)\b[^\n]*\s*>\s*/etc/\w+", "Write into /etc"),
    (r"\b(curl|wget)\b[^\n]*\|\s*(sh|bash)\b", "Pipe remote script to shell"),
]


ALLOWED_PREFIXES = [
    "ls",
    "cat",
    "head",
    "tail",
    "grep",
    "egrep",
    "fgrep",
    "find",
    "pwd",
    "whoami",
    "id",
    "date",
    "uptime",
    "df",
    "du",
    "free",
    "uname",
    "stat",
    "wc",
    "cut",
    "sort",
    "uniq",
    "echo",
    "printf",
    "sed",
    "awk",
    "ps",
    "top",
    "htop",
    "ss",
]


def check_danger(cmd: str) -> Dict:
    reasons: List[str] = []
    stripped = cmd.strip()
    for pattern, label in DANGEROUS_PATTERNS:
        if re.search(pattern, stripped):
            reasons.append(label)

    first = shlex.split(stripped)[0] if stripped else ""
    if "sudo" in stripped and first not in ALLOWED_PREFIXES:
        reasons.append("Uses sudo on non-allowlisted command")

    if re.search(r">\s*/(etc|boot|bin|sbin|usr)/", stripped):
        reasons.append("Redirection into system path")

    return {"danger": len(reasons) > 0, "reasons": reasons}


