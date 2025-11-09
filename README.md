![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![LLM: Gemini](https://img.shields.io/badge/LLM-Google%20Gemini-brightgreen.svg)
![Downloads](https://img.shields.io/github/downloads/5afagy/BashBard/total)
![Visitors](https://visitor-badge.laobi.icu/badge?page_id=5afagy.BashBard)

# 🧠 **BashBard**
### *AI Assistant for Shell Automation and Command Correction*


### ⚡ Overview

**BashBard** is an **AI-powered command-line assistant** that transforms your Linux terminal into an intelligent, safety-aware environment.  
It understands natural language, translates it into optimized shell commands, repairs failing commands, and provides built-in safety checks, all inside a **real PTY-based bash experience**.

Built for developers, system administrators, security engineers, DevOps professionals, AI automation enthusiasts, and *anyone who lives in the terminal*, BashBard makes your command line **smarter, safer, and faster**.


## 💡 Why BashBard Exists

Working in the terminal can be powerful, but also risky and repetitive.  
We all forget syntax, mistype commands, or execute something destructive by accident.  
**BashBard** was created to eliminate these pain points:

- **Forget the syntax**: just describe what you want in plain English.  
- **Fix errors instantly**: BashBard learns from stderr and replans your command.  
- **Stay safe**: every command is analyzed by an AI safety layer before execution.  
- **Automate intuitively**: BashBard combines intelligence with the raw power of bash.

> **“Your terminal, reimagined, smarter, safer, and built for humans.”**


## ⚙️ Installation

BashBard ships with an automated installer that sets up everything for you.
```bash
git clone https://github.com/5afagy/BashBard.git
cd BashBard
chmod +x install.sh
./install.sh
````

During installation, the script will:

* Create a **dedicated virtual environment**.
* Install all dependencies from `requirements.txt`.
* Prompt you for your **Google Gemini API key**.
* Auto-generate your `.env` file.

### Start BashBard

```bash
BashBard
```

### Uninstall

```bash
rm -rf ~/.local/share/bashbard ~/.local/bin/BashBard
```

## 🔧 Configuration

Your `.env` file stores the main configuration variables.
You can edit it anytime (found at `~/.local/share/bashbard/.env`):

```bash
LLM_PROVIDER=google
GOOGLE_API_KEY=your_api_key_here
GOOGLE_MODEL=gemini-2.5-flash-lite
DRY_RUN=0
```
## Core Features

| Feature                        | Description                                                         |                             |
| ------------------------------ | ------------------------------------------------------------------- | --------------------------- |
| 🗣️ Natural Language → Command | Type `/e <request>` to turn plain English into bash.                |                             |
| 🔧 Command Repair              | Fixes typos and broken commands automatically.                      |                             |
| 🛡️ Safety Checks              | Detects risky commands (`rm -rf /`, `curl                           | sh`) and asks for approval. |
| 🧪 Dry-Run Mode                | Preview commands without running them (`/dry on`).                  |                             |
| 💻 Real Bash Integration       | Runs inside a true PTY — supports colors, jobs, signals, and pipes. |                             |

### ⚙️ **Advanced Features**

* Context-aware **auto-repair** with re-planning (`/repair auto`)
* Intelligent **output filtering** for clean AI feedback
* Quick **alias injection** (`/alias basic`)
* Customizable **dry-run**, **quiet**, and **auto-repair** modes
* Built-in **danger heuristics** to prevent destructive actions

> 💡 **Pro Tip:** Run `/repair on` to let BashBard automatically fix simple typos like `gti` → `git`.

## Usage Examples

```bash
# Convert natural language to command
/e show all python files in current folder
# AI → ls -R | grep '\.py$'

# Fix broken commands
gti status
# AI detects typo → Did you mean: git status?

# Toggle modes
/repair on     # enable auto-repair
/dry on        # preview commands without execution
/dry off       # execute normally
/quit          # exit BashBard
```

BashBard understands your intent, it’s not just syntax-aware, it’s *context-aware.*

## Technology Overview

BashBard is engineered with a modular architecture built on modern AI and system libraries.

**Stack:**

* Python 3.12+
* Google Gemini (default) via **LangChain / LangGraph**
* PTY shell system (using `pty`, `termios`, and `fcntl`)

### Architecture

```
BashBard/
├── cli.py          → Command-line entry & argument parsing
├── terminal.py     → PTY AI-powered interactive shell
├── llm.py          → AI provider (Gemini / OpenAI)
├── nodes.py        → LangGraph nodes for AI actions
├── safety.py       → Danger detection & safety logic
├── graph.py        → Graph orchestration
├── state.py        → State management
└── ux.py           → Rich text & user interface helpers
```

**Core engine:** `terminal.py` runs the real-time AI terminal.
**CLI wrapper:** `cli.py` decides mode (interactive, legacy, one-shot).
**LLM logic:** `llm.py`, `nodes.py`, and `safety.py` handle intelligence and protection.

## Future Roadmap *Legend of Features*

BashBard is evolving. Below is a focused, visionary roadmap, a **legend** of planned capabilities that will make the tool indispensable for developers, security pros, and anyone who uses Linux daily.

### Legend Key Future Capabilities
- 🔄 **Multi-model Orchestration**  
  Combine the best of Google Gemini, OpenAI, and other models to balance cost, latency, and accuracy.

- 🧠 **Session Memory & Context**  
  Persistent, privacy-respecting session memory so BashBard understands earlier commands, project context, and multi-step workflows, enabling smarter suggestions and fewer repeated prompts.

- ⚙️ **Local / Offline Model Support**  
  Run models on-prem or locally for air-gapped environments and sensitive workflows.

- ☁️ **Cloud Audit & Command Analytics**  
  Optional, privacy-first telemetry and cloud dashboards for reviewing executed commands, trends, and team activity (opt-in only).

- 🧩 **Plugin API & Extensibility**  
  Allow third-party plugins to add domain-specific intelligence (e.g., Docker, Kubernetes, AWS, pentest helpers).

- 🔐 **Safe Execution Sandboxes**  
  Built-in sandboxing modes for testing risky commands before applying to production systems.

- 🛠️ **Pentester Companion Mode** *(expert-focused)*  
  Tools for security assessments: capture evidence, checkpoint results, checklist automation, recommended next steps, and context-aware exploit mitigation suggestions, designed to help pentesters work faster and more auditable.

- 📊 **Command History Intelligence**  
  Analyze history to recommend automation, refactors, aliases, or safe scripts; surface repeated manual steps for conversion into reproducible tasks.

- 🧾 **Explainability & Provenance**  
  Track why a suggested command was produced (model prompt, reasoning, relevant context) so results are auditable and defensible.

- 🤝 **Collaboration & Team Profiles**  
  Share context, safe policies, and custom rule sets across teams (with privacy controls).

## 🤝 How You Can Help (Open to Collaborators)

BashBard is a community project, contributions are welcome. Ways to contribute:

- ⭐ Star & fork the repo  
- 🐛 Open issues for bugs or improvement ideas  
- ✍️ Submit pull requests (features, docs, tests)  
- 💬 Join Discussions to propose roadmap items or plugins  
- 🔒 Help with security reviews and safe execution patterns

**Contribution guide:** Fork → branch → PR → review. Keep changes focused and well-documented.

## 👨‍💻 Authors & License

**Author:** Khafagy  
**Co-Developer:** Naggar

**License:** [MIT License](https://opensource.org/licenses/MIT)

> Built with ❤️ open to contributors and collaborators from the security, devops, and AI communities.

## 🏁 Get Involved

Want to build a plugin, propose a pentest helper, or sponsor a feature? Open an issue or start a discussion at the project repo:

`https://github.com/5afagy/BashBard`

Together we’ll make BashBard an essential, trustworthy companion for anyone working at the shell.
