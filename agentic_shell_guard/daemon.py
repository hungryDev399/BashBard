from __future__ import annotations

import argparse
import json
import os
import socket
import sys
import threading
from typing import Dict, Any

# Reuse existing functionality; avoid duplication
from .nodes import from_english, from_error, danger_check


def _default_socket_path() -> str:
    user = os.getenv("USER") or str(os.getuid())
    return f"/tmp/bashbard-{user}.sock"


def _handle_preexec(payload: Dict[str, Any]) -> Dict[str, Any]:
    cmd: str = (payload.get("cmd") or "").strip()
    cwd: str = payload.get("cwd") or os.getcwd()

    # English mode: lines starting with "/e " are translated
    if cmd.startswith("/e "):
        request = cmd[3:].strip()
        state = {"user_request": request}
        out = from_english(state)
        candidate = (out.get("candidate_command") or "").strip()
        expl = out.get("candidate_explanation") or ""

        if not candidate:
            return {
                "action": "message",
                "message": expl or "No runnable command produced.",
            }

        # Check danger on the translated command
        d = danger_check({"candidate_command": candidate})
        return {
            "action": "replace",
            "command": candidate,
            "explanation": expl,
            "require_confirmation": bool(d.get("danger")),
            "danger_reasons": d.get("danger_reasons", []),
            "cwd": cwd,
        }

    # Direct command: perform danger check only
    d = danger_check({"candidate_command": cmd})
    return {
        "action": "proceed",
        "command": cmd,
        "require_confirmation": bool(d.get("danger")),
        "danger_reasons": d.get("danger_reasons", []),
        "cwd": cwd,
    }


def _handle_postexec(payload: Dict[str, Any]) -> Dict[str, Any]:
    cmd: str = payload.get("cmd") or ""
    exit_code: int = int(payload.get("exit_code") or 0)
    stderr_tail: str = payload.get("stderr_tail") or ""

    if exit_code == 0:
        return {"action": "ok"}

    # Ask the fixer for a suggested correction
    st: Dict[str, Any] = {"last_command": cmd, "last_error": stderr_tail}
    out = from_error(st)
    suggestion = (out.get("candidate_command") or "").strip()
    expl = out.get("candidate_explanation") or ""

    if not suggestion:
        return {"action": "no_fix", "explanation": expl}

    d = danger_check({"candidate_command": suggestion})
    return {
        "action": "suggest_fix",
        "suggested_command": suggestion,
        "explanation": expl,
        "danger": bool(d.get("danger")),
        "danger_reasons": d.get("danger_reasons", []),
    }


def _handle_event(data: Dict[str, Any]) -> Dict[str, Any]:
    event = data.get("event")
    if event == "preexec":
        return _handle_preexec(data)
    if event == "postexec":
        return _handle_postexec(data)
    return {"error": f"Unknown event: {event}"}


def _serve_client(conn: socket.socket, addr: str, verbose: bool = False) -> None:
    try:
        with conn:
            buf = b""
            while True:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    if not line.strip():
                        continue
                    try:
                        req = json.loads(line.decode("utf-8", errors="replace"))
                    except Exception as e:
                        resp = {"error": f"Invalid JSON: {e}"}
                    else:
                        if verbose:
                            print(f"[daemon] <- {req}")
                        try:
                            resp = _handle_event(req)
                        except Exception as e:
                            resp = {"error": str(e)}
                        if verbose:
                            print(f"[daemon] -> {resp}")
                    conn.sendall((json.dumps(resp) + "\n").encode("utf-8"))
    except Exception as e:
        if verbose:
            print(f"[daemon] client error: {e}")


def serve(socket_path: str, verbose: bool = False) -> None:
    # Ensure no stale socket exists
    try:
        if os.path.exists(socket_path):
            os.unlink(socket_path)
    except Exception:
        pass

    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(socket_path)
    os.chmod(socket_path, 0o600)
    srv.listen(64)
    if verbose:
        print(f"[daemon] listening on {socket_path}")
    try:
        while True:
            conn, addr = srv.accept()
            t = threading.Thread(target=_serve_client, args=(conn, str(addr), verbose), daemon=True)
            t.start()
    finally:
        try:
            srv.close()
        finally:
            try:
                os.unlink(socket_path)
            except Exception:
                pass


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Agentic Shell Guard daemon")
    p.add_argument("--socket", dest="socket_path", default=_default_socket_path(), help="Unix socket path")
    p.add_argument("--verbose", action="store_true")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    serve(args.socket_path, verbose=bool(args.verbose))


if __name__ == "__main__":
    main()


