#!/usr/bin/env python3
import subprocess
from prompt_toolkit import PromptSession
from rich.console import Console
from rich.markdown import Markdown
from rich.panel import Panel
from rich.align import Align
import ai_client
import memory

console = Console()

# ──────────────────────────────────────────────────────────────────────────────
# Professional Banner using Rich Panel
banner_text = (
    "[bold cyan]BashBard[/bold cyan]\n"
    "[white]AI-Driven Linux Shell Tutor & Storyteller[/white]\n\n"
    "[green]Author:[/] Khafagy\n"
    "[green]LinkedIn:[/] https://linkedin.com/in/khafagy\n"
    "[green]Email:[/] Ali5afagy@gmail.com"
)
BANNER = Panel(
    Align.center(banner_text, vertical="middle"),
    border_style="bright_blue",
    padding=(1, 4),
)
# ──────────────────────────────────────────────────────────────────────────────

DANGEROUS = {
    "rm -rf /": "Wipes the entire filesystem!",
    "mkfs.":   "Formats partitions—data loss guaranteed!"
}

def is_dangerous(cmd: str) -> str:
    for sig, warn in DANGEROUS.items():
        if cmd.strip().startswith(sig):
            return warn
    return ""

def run_shell(cmd: str):
    proc = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return proc.stdout + proc.stderr, proc.returncode

def main():
    # Show professional banner once at startup
    console.print(BANNER)
    console.print("[bold magenta]🐧 Welcome to BashBard! Type 'exit' to quit.[/]\n")

    session = PromptSession()
    history = memory.load_history()

    while True:
        try:
            user_in = session.prompt("BashBard> ").strip()

            # Exit condition
            if user_in.lower() in ("exit", "quit"):
                break

            # Clear-screen exception: handle locally, no AI call
            if user_in == "clear":
                console.clear()
                continue

            if not user_in:
                continue

            # 1) Dangerous-command guard
            warn = is_dangerous(user_in)
            if warn:
                console.print(f"[bold red]⚠️ Dangerous:[/] {warn}")
                confirm = session.prompt("Type 'YES' to proceed: ")
                if confirm.strip().upper() != "YES":
                    console.print("[yellow]Aborted.[/]\n")
                    continue

            # 2) Execute the command locally
            out, code = run_shell(user_in)
            console.print(out, end="")

            # 3) Determine if we need AI help
            if code != 0:
                prompt = (
                    f"I ran:\n```\n{user_in}\n```\n"
                    f"Error:\n```\n{out}\n```"
                )
            else:
                # treat multi-word/keyword inputs as English requests
                if any(k in user_in for k in [" ", "find", "list", "search", "install"]):
                    prompt = f"User wants: {user_in}"
                else:
                    history.append({"cmd": user_in, "out": out, "tutor": None})
                    memory.save_history(history)
                    continue

            # 4) Ask BashBard for guidance
            console.print("\n[cyan]🤖 BashBard ▶️[/]")
            advice = ai_client.ask_tutor(prompt)
            console.print(Markdown(advice), end="\n\n")

            # 5) Log history
            history.append({"cmd": user_in, "out": out, "tutor": advice})
            memory.save_history(history)

        except KeyboardInterrupt:
            console.print("\nPress Ctrl-D or type 'exit' to quit.\n")
        except Exception as e:
            console.print(f"[bold red]Error:[/] {e}\n")

if __name__ == "__main__":
    main()
