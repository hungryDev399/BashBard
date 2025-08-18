## Agentic Shell Guard

An agentic, safety-aware Linux command assistant. It converts natural language to shell commands, or fixes failing commands using their errors. Every candidate command passes through a danger check and an approval gate before (optionally) executing.

## Features
- Natural language → single POSIX-friendly command + explanation
- Command fixing using stderr + optional user intent
- Heuristic danger checks for destructive patterns
- Human approval gate with feedback loop (replan to safer alternative)
- Dry-run mode by default

## Project structure
```text
agentic-bashbard/
├─ agentic_shell_guard/
│  ├─ __init__.py            # exports main
│  ├─ __main__.py            # enables `python -m agentic_shell_guard`
│  ├─ cli.py                 # CLI entrypoint and argument parsing
│  ├─ graph.py               # LangGraph assembly
│  ├─ llm.py                 # LLM provider selection (OpenAI / Google Gemini)
│  ├─ nodes.py               # Node implementations (LLM calls, approval, run)
│  ├─ safety.py              # Danger patterns and checks
│  └─ state.py               # TypedDict for graph state
├─ main.py                   # thin wrapper that calls package `main`
└─ README.md
```

## Requirements
- Python 3.10+

## Installation
```bash
pip install -U langchain langgraph langchain-openai langchain-google-genai typing_extensions
```

## Configuration
Set one of the following depending on your provider choice.

### OpenAI
```bash
export OPENAI_API_KEY=sk-...
export LLM_PROVIDER=openai   # default
export OPENAI_MODEL=gpt-4o-mini   # optional
```

### Google Gemini
```bash
export GOOGLE_API_KEY=...
export LLM_PROVIDER=google
export GOOGLE_MODEL=gemini-1.5-flash   # optional
```

### Windows PowerShell equivalents
```powershell
$env:OPENAI_API_KEY = "sk-..."
$env:LLM_PROVIDER = "openai"
$env:DRY_RUN = "1"    # default; set to "0" to actually execute commands
```

### Execution mode
- `DRY_RUN=1` (default) prints the command without executing.
- Set `DRY_RUN=0` to execute after approval.

## Usage

### Run as a module (preferred)
```bash
python -m agentic_shell_guard --english "list only hidden files in /etc"
```

```bash
python -m agentic_shell_guard --fix --cmd "ls -z" --err "ls: invalid option -- 'z'"
```

### Run via wrapper
```bash
python main.py --english "show disk usage for /var sorted by size"
```

### CLI options
- `--english <text>`: natural language request
- `--fix --cmd <string> --err <string>`: fix a failing command using its stderr
- `--intent <text>`: optional intent to guide the fixer when using `--fix`

## Safety model
1. A candidate command is generated (from English or by fixing an error).
2. The command runs through `danger_check` with rules for destructive patterns (e.g., `rm -rf /`, piping curl | sh, writes to `/etc`, etc.).
3. If safe: auto-approve and proceed to run (or dry-run).
4. If risky: interactive approval gate prompts to approve, reject, or edit intent.
5. On rejection: feedback is used to replan a safer alternative.

Keep a human-in-the-loop for high-risk actions. Defaults keep you safe with `DRY_RUN=1`.

## Extending
- Add or adjust patterns in `agentic_shell_guard/safety.py`.
- Modify prompts or node behavior in `agentic_shell_guard/nodes.py`.
- Swap provider defaults in `agentic_shell_guard/llm.py`.

## Troubleshooting
- If nothing runs, confirm `DRY_RUN` is set to `0` and that your API key is set.
- Ensure provider-specific packages are installed (OpenAI or Google GenAI) per your `LLM_PROVIDER`.

## License
Add your preferred license here.


