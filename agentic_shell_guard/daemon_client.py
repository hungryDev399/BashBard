from __future__ import annotations

import contextlib
import json
import os
import socket
from typing import Dict, Any, Optional


def default_socket_path() -> str:
    user = os.getenv("USER") or str(os.getuid())
    return f"/tmp/bashbard-{user}.sock"


class DaemonClient:
    def __init__(self, socket_path: Optional[str] = None) -> None:
        self.socket_path = socket_path or default_socket_path()

    def send(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        data = json.dumps(payload) + "\n"
        with contextlib.closing(socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)) as s:
            s.connect(self.socket_path)
            s.sendall(data.encode("utf-8"))
            # Read one line response
            buf = b""
            while True:
                chunk = s.recv(65536)
                if not chunk:
                    break
                buf += chunk
                if b"\n" in buf:
                    line, _rest = buf.split(b"\n", 1)
                    try:
                        return json.loads(line.decode("utf-8", errors="replace"))
                    except Exception:
                        return {"error": "Invalid JSON from daemon"}
        return {"error": "No response from daemon"}


