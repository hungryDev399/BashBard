"""
Wrapper to run the Agentic Shell Guard package CLI.

Usage:
  python -m agentic_shell_guard --english "list only hidden files in /etc"
  python -m agentic_shell_guard --fix --cmd "ls -z" --err "ls: invalid option -- 'z'"
"""

from agentic_shell_guard import main


if __name__ == "__main__":
    main()


