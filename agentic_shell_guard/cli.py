from __future__ import annotations

import argparse
from dotenv import load_dotenv  # type: ignore

from .graph import build_graph
from .state import State
from .llm import get_llm  # ensures provider packages are available

# Load .env from project root (working directory)
load_dotenv()


def parse_args():
    p = argparse.ArgumentParser(description="Agentic Shell Guard")
    # Back-compat optional one-shot modes; if none provided, start interactive shell
    m = p.add_mutually_exclusive_group(required=False)
    m.add_argument("--english", type=str, help="Natural language request (one-shot)")
    m.add_argument("--fix", action="store_true", help="Fix a failing command using stderr (one-shot)")
    p.add_argument("--cmd", type=str, help="Failing command (for --fix)")
    p.add_argument("--err", type=str, help="Error output/stderr (for --fix)")
    p.add_argument("--intent", type=str, default="", help="Optional intent to guide fixing")
    return p.parse_args()


def _print_summary(out: State) -> None:
    # Only show summary if no immediate run output was printed
    if out.get("result"):
        return
    cmd = out.get("candidate_command")
    expl = out.get("candidate_explanation")
    if not cmd and not expl:
        return
    print("\n=== SUMMARY ===")
    if cmd:
        print("Command:", cmd)
    if expl:
        print("Explanation:", expl)


def _interactive_shell():
    _ = get_llm  # explicitly reference to avoid linter removal of import
    app = build_graph()
    print("Agentic Shell Guard interactive mode. Type '/help' for commands.\n")
    flags = {"dry_run": False, "quiet": False, "interactive": True}
    while True:
        try:
            line = input("BashBard> ").strip()
        except EOFError:
            print()
            break
        except KeyboardInterrupt:
            print()
            continue

        if not line:
            continue

        if line.startswith('/'):
            if line in ("/q", "/quit", "/exit"):
                break
            if line == "/help":
                print("Commands:\n  /e <request>  - natural language to command\n  /run          - disable dry-run (execute commands)\n  /dry          - enable dry-run (default)\n  /quiet        - reduce console output\n  /verbose      - verbose console output\n  /q            - quit\n  Otherwise: typed line is executed as a shell command")
                continue
            if line == "/run":
                flags["dry_run"] = False
                print("Dry-run disabled. Commands will execute.")
                continue
            if line == "/dry":
                flags["dry_run"] = True
                print("Dry-run enabled. Commands will NOT execute.")
                continue
            if line == "/quiet":
                flags["quiet"] = True
                print("Quiet mode on.")
                continue
            if line == "/verbose":
                flags["quiet"] = False
                print("Verbose mode on.")
                continue
            if line.startswith("/e"):
                request = line[2:].strip()
                if not request:
                    print("Usage: /e <natural language request>")
                    continue
                state: State = {"user_request": request, **flags}
            else:
                print("Unknown command. Type '/help'.")
                continue
        else:
            state = {"direct_command": line, **flags}

        out = app.invoke(state)
        _print_summary(out)


def main():
    args = parse_args()

    # One-shot modes remain available for scripting/back-compat
    if getattr(args, "english", None):
        _ = get_llm  # explicitly reference to avoid linter removal of import
        app = build_graph()
        state: State = {"user_request": args.english}
        out = app.invoke(state)
        _print_summary(out)
        return

    if getattr(args, "fix", False):
        if not (args.cmd and args.err):
            raise SystemExit("--fix requires --cmd and --err")
        _ = get_llm
        app = build_graph()
        state: State = {"last_command": args.cmd, "last_error": args.err}
        if args.intent:
            state["user_request"] = args.intent
        out = app.invoke(state)
        _print_summary(out)
        return

    # Default: interactive shell
    _interactive_shell()


