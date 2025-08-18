#!/usr/bin/env python3
"""
AI Terminal Shim — PTY-based terminal with LangGraph integration
- Spawns a real bash under a PTY
- Properly relays keystrokes and output
- Handles window resize and Ctrl-C/Z/\ signals
- Intercepts completed input lines for AI transformation
- Integrates with existing LangGraph nodes for command processing
"""

import os
import pty
import sys
import tty
import termios
import fcntl
import struct
import signal
import select
import subprocess
from typing import Optional, Dict, Tuple
import re

from .graph import build_graph
from .state import State
from .safety import check_danger
from .nodes import replan as llm_replan, from_english as llm_from_english, from_error as llm_from_error
from .llm import get_llm


# Configure bash command
BASH = ["bash", "--noprofile", "--norc"]   # Use ["bash", "-l"] if you want rc files


# ----------------------------
# LangGraph Integration Functions
# ----------------------------

def _sanitize_llm_command_text(text: str) -> Optional[str]:
    """
    Best-effort extraction of a runnable single-line shell command from model output.
    - If text looks like JSON or contains a "command" field, extract that value via regex
    - Reject multi-line or brace-heavy payloads to avoid sending JSON to bash
    - Trim and return None if nothing safe is found
    """
    if not isinstance(text, str):
        return None
    candidate = text.strip()
    # If we accidentally got a JSON-ish blob, try to extract command value
    if '"command"' in candidate or candidate.startswith('{'):
        m = re.search(r'"command"\s*:\s*"(.*?)"', candidate, re.DOTALL)
        if m:
            extracted = m.group(1).strip()
            # Collapse whitespace/newlines inside extracted
            extracted = extracted.replace('\r', ' ').replace('\n', ' ').strip()
            return extracted if extracted else None
        # If we can't extract safely, refuse to run
        return None
    # Reject multi-line payloads
    if '\n' in candidate or '\r' in candidate:
        return None
    # Otherwise return as-is
    return candidate or None

def english_to_command_if_needed(user_line: str, *, cwd: str, env: dict) -> str:
    """
    Transform plain English to command using the existing LangGraph from_english node.
    """
    try:
        state: State = {"user_request": user_line, "dry_run": False, "quiet": True, "strict_json": True}
        result = llm_from_english(state)
        raw_cmd = result.get("candidate_command", "")
        mode = (result.get("candidate_mode") or "run").lower()
        if raw_cmd and mode != "explain":
            cmd = _sanitize_llm_command_text(raw_cmd)
            if not cmd: 
                # Refuse to run ambiguous blob; inform the user
                print("\r\n[AI] Command extraction failed; model returned non-shell content.\r\n", end="")
                return ""
            if result.get("candidate_explanation"):
                print(f"\r\n[AI] {result['candidate_explanation']}\r\n", end="")
            return cmd
        elif result.get("candidate_explanation"):
            print(f"\r\n[AI] {result['candidate_explanation']}\r\n", end="")
            return ""
        # If the model did not provide a runnable command, do not attempt to run the raw English
        return ""
    except Exception as e:
        print(f"\r\n[AI Error] {e}\r\n", end="")
        # On error, avoid executing the raw English text
        return ""


def repair_command_if_needed(prev_cmd: str, last_output_chunk: str, *, cwd: str, env: dict) -> Optional[str]:
    """
    Use recent output to propose a corrected command using the existing from_error node.
    """
    try:
        state: State = {
            "last_command": prev_cmd,
            "last_error": last_output_chunk,
            "dry_run": False,
            "quiet": True,
            "strict_json": True,
        }
        result = llm_from_error(state)
        raw_cmd = result.get("candidate_command", "")
        mode = (result.get("candidate_mode") or "run").lower()
        if raw_cmd and mode != "explain":
            cmd = _sanitize_llm_command_text(raw_cmd)
            if not cmd:
                print("\r\n[AI Repair] Command extraction failed; model returned non-shell content.\r\n", end="")
                return None
            if result.get("candidate_explanation"):
                print(f"\r\n[AI Repair] {result['candidate_explanation']}\r\n", end="")
            return cmd
        elif result.get("candidate_explanation"):
            print(f"\r\n[AI] {result['candidate_explanation']}\r\n", end="")
        return None
    except Exception as e:
        print(f"\r\n[AI Repair Error] {e}\r\n", end="")
        return None


def approval_gate(cmd: str, *, context: str) -> bool:
    """
    Risk check + human approval using the existing danger_check function.
    """
    try:
        # Use the existing danger check
        danger_result = check_danger(cmd)
        is_dangerous = danger_result.get("danger", False)
        reasons = danger_result.get("reasons", [])
        
        if is_dangerous:
            print(f"\r\n=== DANGEROUS COMMAND ===\r\n$ {cmd}\r\n", end="")
            if reasons:
                print("Reasons:\r\n", end="")
                for r in reasons:
                    print(f" - {r}\r\n", end="")
            
            # Ask for confirmation
            print("Run this command? [y/N]: ", end="")
            sys.stdout.flush()
            
            # Read user response in raw mode
            response = ""
            while True:
                ch = os.read(sys.stdin.fileno(), 1)
                if ch in (b"\r", b"\n"):
                    print("\r\n", end="")
                    break
                if ch == b"\x03":  # Ctrl-C
                    print("\r\n", end="")
                    return False
                response += ch.decode("utf-8", "ignore")
                os.write(sys.stdout.fileno(), ch)
            
            return response.lower() in ("y", "yes")
        
        # Safe command - auto-approve
        return True
    except Exception as e:
        print(f"\r\n[Approval Error] {e}\r\n", end="")
        return True  # Default to allowing on error


# ----------------------------
# Terminal helpers
# ----------------------------

def get_winsize(fd: int) -> Tuple[int, int]:
    try:
        s = fcntl.ioctl(fd, termios.TIOCGWINSZ, b"\x00" * 8)
        rows, cols, _xp, _yp = struct.unpack("HHHH", s)
        return rows or 24, cols or 80
    except Exception:
        return 24, 80


def set_winsize(fd: int, rows: int, cols: int) -> None:
    s = struct.pack("HHHH", rows, cols, 0, 0)
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, s)
    except Exception:
        pass


# ----------------------------
# Main PTY Terminal Class
# ----------------------------

class AITerminal:
    def __init__(self, dry_run: bool = False, quiet: bool = False):
        self.child_pid: Optional[int] = None
        self.master_fd: Optional[int] = None
        self.orig_tattr = None
        self.line_buffer = bytearray()
        self.last_output_lines: list[str] = []
        self.max_context_lines = 100
        
        # Error/repair context tracking
        self.last_failed_command: Optional[str] = None
        self.last_error_text: Optional[str] = None
        self.last_repair_suggestion: Optional[str] = None
        
        # Per-command tracking boundaries
        self._pending_cmd: Optional[str] = None
        self._pending_output_start: int = 0
        
        # Internal guard to avoid repair loops
        self._repair_in_progress: bool = False
        self._last_repaired_for_cmd: Optional[str] = None
        self._repair_attempts: Dict[str, int] = {}  # Track repair attempts per command
        
        # Configuration flags
        self.dry_run = dry_run
        self.quiet = quiet
        self.auto_repair = False  # Changed to False by default for less aggressive behavior
        self.interactive_repair = True  # When repairing, ask run/cancel/replan/edit
        
        # Track if we're typing a special command that shouldn't go to bash
        self._typing_special_command = False
        
        # Ensure LLM is available
        try:
            _ = get_llm()
        except Exception as e:
            print(f"Warning: LLM not available: {e}")

    # --- small raw-input helpers (work in raw mode) ---

    def _read_line_raw(self) -> str:
        buf = bytearray()
        while True:
            ch = os.read(sys.stdin.fileno(), 1)
            if ch in (b"\r", b"\n"):
                print("\r\n", end="")
                break
            if ch == b"\x03":  # Ctrl-C
                print("\r\n", end="")
                return ""
            if ch in (b"\x7f", b"\x08"):
                if buf:
                    buf = buf[:-1]
                    os.write(sys.stdout.fileno(), b"\b \b")
                continue
            try:
                os.write(sys.stdout.fileno(), ch)
            except Exception:
                pass
            buf += ch
        return buf.decode("utf-8", "ignore").strip()

    def _prompt_yes_no(self, question: str, default_no: bool = True) -> bool:
        print(question, end="")
        sys.stdout.flush()
        ans = self._read_line_raw().lower()
        if ans in ("y", "yes"):
            return True
        if ans in ("n", "no"):
            return False
        return not default_no

    def _prompt_fix_choice(self, failed_cmd: str, error_text: str, suggestion: str) -> str:
        print("\r\n=== Command Failed ===", end="\r\n")
        print(f"Failed: $ {failed_cmd}", end="\r\n")
        preview = error_text.strip()
        if len(preview) > 200:
            preview = preview[:200] + "..."
        print(f"Error: {preview}", end="\r\n")
        print(f"\r\nSuggested fix: $ {suggestion}", end="\r\n")
        print("Choose: [r]un, [c]ancel, [e]dit, [p]lan (replan): ", end="")
        sys.stdout.flush()
        ans = (self._read_line_raw() or "").lower()
        if ans.startswith("r"):
            return "run"
        if ans.startswith("e"):
            return "edit"
        if ans.startswith("p"):
            return "replan"
        return "cancel"

    # --- child / pty

    def spawn_shell(self) -> None:
        pid, mfd = pty.fork()
        if pid == 0:
            # Child
            # Put child in its own process group so job control works
            try:
                os.setsid()
            except Exception:
                pass
            os.execvp(BASH[0], BASH)
        # Parent
        self.child_pid = pid
        self.master_fd = mfd
        # sync window size from our stdin
        r, c = get_winsize(sys.stdin.fileno())
        set_winsize(self.master_fd, r, c)

    # --- TTY mode

    def enter_raw(self) -> None:
        self.orig_tattr = termios.tcgetattr(sys.stdin.fileno())
        tty.setraw(sys.stdin.fileno())

    def restore_tattr(self) -> None:
        if self.orig_tattr:
            termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, self.orig_tattr)

    # --- signals

    def on_sigwinch(self, *_):
        if self.master_fd is None:
            return
        rows, cols = get_winsize(sys.stdin.fileno())
        set_winsize(self.master_fd, rows, cols)

    def forward_signal(self, sig: int) -> None:
        if self.master_fd is None and self.child_pid is None:
            return
        # Try to send the signal to the foreground process group of the PTY
        sent = False
        try:
            if self.master_fd is not None:
                fg_pgid = os.tcgetpgrp(self.master_fd)
                if isinstance(fg_pgid, int) and fg_pgid > 0:
                    os.killpg(fg_pgid, sig)
                    sent = True
        except Exception:
            pass
        # Fallback: send to the child's pid (process group)
        if not sent and self.child_pid is not None:
            try:
                os.killpg(self.child_pid, sig)
                sent = True
            except Exception:
                try:
                    os.kill(self.child_pid, sig)
                    sent = True
                except Exception:
                    pass
        # As a last resort, write the control char directly into the PTY
        try:
            if self.master_fd is not None:
                ctrl_map = {signal.SIGINT: b"\x03", signal.SIGTSTP: b"\x1a", signal.SIGQUIT: b"\x1c"}
                ctrl = ctrl_map.get(sig)
                if ctrl:
                    os.write(self.master_fd, ctrl)
        except Exception:
            pass

    def install_handlers(self) -> None:
        signal.signal(signal.SIGWINCH, self.on_sigwinch)
        signal.signal(signal.SIGCHLD, lambda *_: None)  # wake select()
        # Ensure the PTY has its own foreground pgrp (child will grab it); we only read/write

    def install_status_prompt(self) -> None:
        """
        Configure bash to print a unique status marker before each prompt, indicating
        the exit code of the previously executed command.
        """
        if self.master_fd is None:
            return
        setup = "export PROMPT_COMMAND='printf \"\\n[[AI:STATUS:%d]]\\n\" $?;'\n"
        os.write(self.master_fd, setup.encode("utf-8"))

    def _send_command_immediately(self, command: str) -> None:
        if not isinstance(command, str):
            return
        if self.master_fd is None:
            return
        # Clear current readline buffer with Ctrl-U (clear line) and send command
        os.write(self.master_fd, b"\x15")  # Ctrl-U clears the line
        os.write(self.master_fd, (command + "\n").encode("utf-8"))

    def _should_attempt_repair(self, command: str) -> bool:
        """
        Determine if we should attempt to repair a failed command.
        Skip repair for:
        - Commands we've already tried to repair multiple times
        - Very short commands (likely typos for exploration)
        """
        if not command:
            return False
        # Unlimited attempts; let LLM decide if repair makes sense
        return True

    def _try_auto_repair(self) -> None:
        """
        If auto_repair is enabled and the last command failed, attempt repair.
        """
        if not (self.last_failed_command and self.last_error_text):
            return
            
        if not self.auto_repair:
            # Only show hint for repairable commands
            if self._should_attempt_repair(self.last_failed_command):
                # Check if this looks like a typo that could be fixed
                if "command not found" in self.last_error_text.lower():
                    print("\r\n[Hint: Use '/repair on' to enable auto-repair for typos]\r\n", end="")
            return
            
        if self._repair_in_progress:
            return
        
        # Check if we should attempt repair
        if not self._should_attempt_repair(self.last_failed_command):
            return
        
        self._repair_in_progress = True
        try:
            # Track repair attempt
            # Track (optional) metrics — but do not enforce a limit anymore
            self._repair_attempts[self.last_failed_command] = \
                self._repair_attempts.get(self.last_failed_command, 0) + 1

            repaired = repair_command_if_needed(
                prev_cmd=self.last_failed_command,
                last_output_chunk=self.last_error_text,
                cwd=os.getcwd(),
                env=dict(os.environ),
            )
            if not (isinstance(repaired, str) and repaired.strip()):
                # No direct fix produced. Offer replan/edit/cancel so repair "works" every time.
                print("\r\nNo automatic fix was generated.", end="\r\n")
                print("Choose: [p]lan (replan), [e]dit, [c]ancel: ", end="")
                sys.stdout.flush()
                choice = (self._read_line_raw() or "").lower()
                if choice.startswith("p"):
                    fb = self._prompt_replan_feedback()
                    self._handle_replan(self.last_failed_command, fb)
                elif choice.startswith("e"):
                    # Allow user to edit the failing command
                    try:
                        os.write(self.master_fd, b"\x15")
                    except Exception:
                        pass
                    for ch in self.last_failed_command:
                        os.write(self.master_fd, ch.encode())
                    os.write(sys.stdout.fileno(), f"$ {self.last_failed_command}\r\n".encode())
                # cancel otherwise
                return

            self.last_repair_suggestion = repaired
            self._last_repaired_for_cmd = self.last_failed_command

            if self.interactive_repair:
                choice = self._prompt_fix_choice(self.last_failed_command, self.last_error_text or "", repaired)
                if choice == "cancel":
                    return
                if choice == "edit":
                    # Pre-fill the suggestion into readline for manual editing
                    os.write(self.master_fd, b"\x15")  # clear line
                    os.write(self.master_fd, repaired.encode("utf-8"))
                    os.write(sys.stdout.fileno(), f"$ {repaired}\r\n".encode())
                    return
                if choice == "replan":
                    fb = self._prompt_replan_feedback()
                    self._handle_replan(self.last_failed_command, fb)
                    return
                # else run
            # Safety approval before executing a repaired command
            if not approval_gate(repaired, context=self.last_output_text()):
                print("\r\n[Repaired command rejected]\r\n", end="")
                return
            # Run the repaired command
            self._pending_cmd = repaired
            self._pending_output_start = len(self.last_output_lines)
            self._send_command_immediately(repaired)
        finally:
            self._repair_in_progress = False

    def _prompt_replan_feedback(self) -> str:
        print("Describe adjustments for a safer/better alternative (blank to skip): ", end="")
        sys.stdout.flush()
        return self._read_line_raw()

    def _handle_replan(self, base_command: str, feedback: str) -> None:
        try:
            state: State = {"candidate_command": base_command, "user_feedback": feedback}
            out = llm_replan(state)
            new_cmd = (out.get("candidate_command") or "").strip()
            expl = out.get("candidate_explanation") or ""
            if expl:
                print(f"\r\n[AI Replan] {expl}\r\n", end="")
            if not new_cmd:
                return
            # Approval gate before running
            if not approval_gate(new_cmd, context=self.last_output_text()):
                print("\r\n[Replanned command rejected]\r\n", end="")
                return
            self._pending_cmd = new_cmd
            self._pending_output_start = len(self.last_output_lines)
            self._send_command_immediately(new_cmd)
        except Exception as e:
            print(f"\r\n[Replan Error] {e}\r\n", end="")

    # --- context

    def append_output_context(self, data: bytes) -> None:
        text = data.decode("utf-8", "replace")
        lines = text.splitlines()
        for line in lines:
            self.last_output_lines.append(line)
            # Heuristic fallback: detect immediate 'command not found' and trigger repair
            if self._pending_cmd is not None:
                try:
                    lower_line = line.lower()
                except Exception:
                    lower_line = ""
                if "command not found" in lower_line:
                    start = max(0, self._pending_output_start)
                    error_lines = self.last_output_lines[start:]
                    self.last_failed_command = self._pending_cmd
                    self.last_error_text = "\n".join(error_lines)
                    # Attempt repair without waiting for status marker
                    self._try_auto_repair()
                    # Avoid double-processing when status marker arrives
                    self._pending_cmd = None
                    self._pending_output_start = len(self.last_output_lines)
                    continue
            # Detect our status marker lines: [[AI:STATUS:<code>]]
            if line.startswith("[[AI:STATUS:") and line.endswith("]]"):
                try:
                    code_str = line[len("[[AI:STATUS:"):-2]
                    exit_code = int(code_str)
                except Exception:
                    exit_code = 0
                # If we had a tracked command, capture its error output when non-zero
                if self._pending_cmd is not None:
                    if exit_code != 0:
                        start = max(0, self._pending_output_start)
                        # Exclude the status line itself
                        error_lines = self.last_output_lines[start:-1]
                        self.last_failed_command = self._pending_cmd
                        self.last_error_text = "\n".join(error_lines)
                        # Attempt immediate repair once per failed command
                        self._try_auto_repair()
                    else:
                        # Command succeeded, clear any repair tracking for it
                        if self._pending_cmd in self._repair_attempts:
                            del self._repair_attempts[self._pending_cmd]
                    # Clear for next command
                    self._pending_cmd = None
                    self._pending_output_start = len(self.last_output_lines)
        if len(self.last_output_lines) > self.max_context_lines:
            self.last_output_lines = self.last_output_lines[-self.max_context_lines:]

    def last_output_text(self) -> str:
        return "\n".join(self.last_output_lines)

    # --- AI interception point

    def gate_and_send(self, user_line_utf8: str) -> None:
        """
        Called when the user pressed Enter. Intercepts the line for AI processing.
        """
        original_line = user_line_utf8.rstrip("\r\n")
        line = original_line
        
        # Skip empty lines
        if not line.strip():
            os.write(self.master_fd, b"\n")
            return
        
        # Handle special commands (these should NOT be sent to bash)
        stripped = line.lstrip()
        if stripped.startswith("/"):
            # Ensure bash readline is cleared in case any chars leaked
            try:
                os.write(self.master_fd, b"\x15")  # Ctrl-U clear line
            except Exception:
                pass
            # Since we didn't echo to PTY (or we cleared), bash won't run it
            tokens = stripped.split()
            cmd = tokens[0]
            args = tokens[1:]
            if cmd in ("/q", "/quit", "/exit"):
                # Send exit command to shell
                os.write(self.master_fd, b"exit\n")
                return
            elif cmd == "/help":
                help_text = (
                    "\r\n=== BashBard Terminal Commands ===\r\n"
                    "/e <request>  - Natural language to command\r\n"
                    "/repair on    - Enable auto-repair (interactive approval)\r\n"
                    "/repair auto  - Enable auto-repair and auto-run fixes\r\n"
                    "/repair off   - Disable auto-repair (default)\r\n"
                    "/dry on       - Enable dry-run mode\r\n"
                    "/dry off      - Disable dry-run mode\r\n"
                    "/help         - Show this help\r\n"
                    "/quit         - Exit terminal\r\n"
                    "\r\n"
                )
                os.write(sys.stdout.fileno(), help_text.encode())
                # Just get a new prompt - bash never saw the /help command
                os.write(self.master_fd, b"\n")
                return
            elif cmd == "/repair":
                sub = (args[0].lower() if args else "on")
                if sub in ("on", "interactive"):
                    self.auto_repair = True
                    self.interactive_repair = True
                    os.write(sys.stdout.fileno(), b"\r\n[Auto-repair enabled with interactive approval]\r\n")
                elif sub == "auto":
                    self.auto_repair = True
                    self.interactive_repair = False
                    os.write(sys.stdout.fileno(), b"\r\n[Auto-repair enabled: auto-run fixes]\r\n")
                elif sub == "off":
                    self.auto_repair = False
                    os.write(sys.stdout.fileno(), b"\r\n[Auto-repair disabled]\r\n")
                else:
                    os.write(sys.stdout.fileno(), b"\r\nUsage: /repair [on|interactive|auto|off]\r\n")
                os.write(self.master_fd, b"\n")
                return
            elif cmd.startswith("/e"):
                # Natural language request
                remainder = stripped[len("/e"):].strip()
                if remainder:
                    # Ensure any provider/status prints start on a fresh line
                    try:
                        os.write(sys.stdout.fileno(), b"\r\n")
                    except Exception:
                        pass
                    transformed = english_to_command_if_needed(
                        remainder,
                        cwd=os.getcwd(),
                        env=dict(os.environ),
                    )
                    if not isinstance(transformed, str):
                        transformed = ""
                    transformed = transformed.strip()
                    if transformed:
                        line = transformed
                        os.write(sys.stdout.fileno(), f"$ {line}\r\n".encode())
                    else:
                        # If NL->cmd produced nothing, offer replan/edit instead of failing silently
                        print("[AI] No command generated.", end="\r\n")
                        print("Choose: [p]lan (replan), [e]dit, [c]ancel: ", end="")
                        sys.stdout.flush()
                        choice = (self._read_line_raw() or "").lower()
                        if choice.startswith("p"):
                            fb = self._prompt_replan_feedback()
                            self._handle_replan("", fb)
                        elif choice.startswith("e"):
                            try:
                                os.write(self.master_fd, b"\x15")
                            except Exception:
                                pass
                            # Let user type new command; show a fresh prompt
                            os.write(sys.stdout.fileno(), b"\r\n")
                        else:
                            os.write(self.master_fd, b"\n")
                        return
                else:
                    os.write(sys.stdout.fileno(), b"\r\nUsage: /e <natural language request>\r\n")
                    os.write(self.master_fd, b"\n")  # Get new prompt
                    return
            else:
                # Unknown / command - let bash handle it (might be a path like /usr/bin/ls)
                # Since we intercepted it, we need to send the full command to bash
                os.write(self.master_fd, (line + "\n").encode("utf-8"))
                return
        
        # Apply approval gate for generated commands
        if line != original_line:  # Command was transformed
            if not approval_gate(line, context=self.last_output_text()):
                os.write(sys.stdout.fileno(), b"\r\n[Command rejected]\r\n")
                os.write(self.master_fd, b"\n")  # Get new prompt
                return
        
        # Check if dry-run mode
        if self.dry_run:
            os.write(sys.stdout.fileno(), f"\r\n[DRY-RUN] Would execute: $ {line}\r\n".encode())
            os.write(self.master_fd, b"\n")  # Get new prompt
            return
        
        # Mark the start of this command's output for error tracking
        self._pending_cmd = line
        self._pending_output_start = len(self.last_output_lines)
        
        # Send to the real shell
        if line == original_line:
            # User typed command directly - just send newline
            os.write(self.master_fd, b"\n")
        else:
            # Safe to re-install here because we control the whole line send
            try:
                self.install_status_prompt()
            except Exception:
                pass
            # Replace the current readline buffer with the transformed command
            os.write(self.master_fd, (line + "\n").encode("utf-8"))

    # --- main loop

    def run(self) -> None:
        print("BashBard Terminal - AI-Enhanced Shell")
        print("Type '/help' for available commands")
        print("Tip: Enable '/repair on' to auto-fix typos like 'lsf' → 'ls'\n")
        
        self.spawn_shell()
        self.install_handlers()
        self.install_status_prompt()
        self.enter_raw()
        
        try:
            while True:
                r, _, _ = select.select([self.master_fd, sys.stdin], [], [])
                
                # PTY → user
                if self.master_fd in r:
                    try:
                        data = os.read(self.master_fd, 4096)
                        if not data:
                            break  # child exited
                        # show raw bytes (preserve colors)
                        os.write(sys.stdout.fileno(), data)
                        self.append_output_context(data)
                    except OSError:
                        break
                
                # user → PTY (with newline interception)
                if sys.stdin in r:
                    ch = os.read(sys.stdin.fileno(), 1)
                    if not ch:
                        break  # stdin closed
                    
                    # Map raw control keys to signals
                    if ch == b"\x03":  # Ctrl-C
                        self.forward_signal(signal.SIGINT)
                        self.line_buffer.clear()  # Clear buffer on Ctrl-C
                        self._typing_special_command = False  # Reset special command flag
                        continue
                    if ch == b"\x1a":  # Ctrl-Z
                        self.forward_signal(signal.SIGTSTP)
                        continue
                    if ch == b"\x1c":  # Ctrl-\
                        self.forward_signal(signal.SIGQUIT)
                        continue
                    
                    # Handle backspace/delete
                    if ch in (b"\x7f", b"\x08"):  # Backspace or Del
                        if self.line_buffer:
                            self.line_buffer = self.line_buffer[:-1]
                            if not self.line_buffer:
                                # Only reset once buffer empties
                                self._typing_special_command = False
                        # Always pass backspace to PTY unless we're in special command mode
                        if not self._typing_special_command:
                            os.write(self.master_fd, ch)
                        else:
                            # Echo backspace to screen for visual feedback
                            os.write(sys.stdout.fileno(), b"\b \b")
                        continue
                    
                    # Intercept only on newline; otherwise pass through
                    if ch in (b"\r", b"\n"):
                        try:
                            line = self.line_buffer.decode("utf-8", "replace")
                        finally:
                            self.line_buffer.clear()
                            # Always reset special command mode on newline
                            # so that subsequent non-slash commands are sent to the PTY.
                            self._typing_special_command = False
                        # Our interception point
                        self.gate_and_send(line)
                    else:
                        # Keep our mirror buffer for the upcoming Enter
                        was_empty = len(self.line_buffer) == 0
                        self.line_buffer += ch
                        # Sticky detection: if first char typed is '/', treat whole line as special
                        if was_empty and ch == b"/":
                            self._typing_special_command = True
                        # Handle echoing based on whether we're typing a special command
                        if self._typing_special_command:
                            # Don't send to PTY, just echo to screen so user sees what they're typing
                            os.write(sys.stdout.fileno(), ch)
                        else:
                            # Normal operation - echo to PTY
                            os.write(self.master_fd, ch)
        
        finally:
            self.restore_tattr()
            try:
                if self.child_pid:
                    os.kill(self.child_pid, signal.SIGHUP)
            except Exception:
                pass
            if self.child_pid:
                try:
                    os.waitpid(self.child_pid, 0)
                except Exception:
                    pass


def main():
    """Entry point for standalone terminal usage."""
    import argparse
    from dotenv import load_dotenv
    
    # Load environment variables
    load_dotenv()
    
    parser = argparse.ArgumentParser(description="BashBard AI Terminal")
    parser.add_argument("--dry-run", action="store_true", help="Enable dry-run mode")
    parser.add_argument("--quiet", action="store_true", help="Reduce output verbosity")
    parser.add_argument("--auto-repair", action="store_true", help="Enable auto-repair on start")
    args = parser.parse_args()
    
    terminal = AITerminal(dry_run=args.dry_run, quiet=args.quiet)
    if args.auto_repair:
        terminal.auto_repair = True
    
    terminal.run()


if __name__ == "__main__":
    main()