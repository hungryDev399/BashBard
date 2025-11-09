![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)
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
curl -sSL https://github.com/5afagy/BashBard/raw/refs/heads/main/install.sh | bash && BashBard
```

> **One command. Zero hassle.**  
> Installs, configures, and launches BashBard — even on fresh systems.

### What the installer does:
- Creates a **dedicated virtual environment**
- Installs dependencies from `requirements.txt`
- Prompts for your **Google Gemini API key** (on first run)
- Auto-generates `.env` at `~/.local/share/bashbard/.env`
- Installs launcher to `~/.local/bin/BashBard`

**Example first-run output:**

```bash
Configuring BashBard environment...
Installation complete.
Enter your Google Gemini API key: ??
Saved API key to /root/.local/share/bashbard/.env
```

### Start BashBard

```bash
BashBard
```

### Uninstall

```bash
rm -rf ~/.local/share/bashbard ~/.local/bin/BashBard
```
## Core Features

| Feature                        | Description                                                         |                         
| ------------------------------ | ------------------------------------------------------------------- | 
| 🗣️ Natural Language → Command | Type `/e <request>` to turn plain English into bash.                |                      
| 🔧 Command Repair              | Fixes typos and broken commands automatically.                      |                      
| 🛡️ Safety Checks              | Detects risky commands (`rm -rf /`, `curl sh`) and asks for approval. |                     
| 🧪 Dry-Run Mode                | Preview commands without running them (`/dry on`).                  |                             
| 💻 Real Bash Integration       | Runs inside a true PTY — supports colors, jobs, signals, and pipes. |                        

### ⚙️ **Advanced Features**

* Context-aware **auto-repair** with re-planning (`/repair auto`)
* Intelligent **output filtering** for clean AI feedback
* Quick **alias injection** (`/alias basic`)
* Customizable **dry-run**, **quiet**, and **auto-repair** modes
* Built-in **danger heuristics** to prevent destructive actions

> 💡 **Pro Tip:** Run `/repair on` to let BashBard automatically fix simple typos like `gti` → `git`.

## Usage Examples
<img width="1106" height="401" alt="image" src="https://github.com/user-attachments/assets/7160800a-4b77-4513-a346-baaa81639e82" />


BashBard understands your intent, it’s not just syntax-aware, it’s *context-aware.*

## Technology Overview

BashBard is engineered with a modular architecture built on modern AI and system libraries.

**Stack:**

* Python 3.12+
* Google Gemini (default) via **LangChain / LangGraph**
* PTY shell system (using `pty`, `termios`, and `fcntl`)

**Core engine:** `terminal.py` runs the real-time AI terminal.
**CLI wrapper:** `cli.py` decides mode (interactive, legacy, one-shot).
**LLM logic:** `llm.py`, `nodes.py`, and `safety.py` handle intelligence and protection.

## Future Roadmap

| Feature | Description |
|--------|-------------|
| **Multi-model support** | Gemini + OpenAI + local models (cost/latency balance) |
| **Session memory** | Retain context across commands, privacy-first |
| **Offline mode** | Run fully on-prem or air-gapped |
| **Plugin API** | Extend with Docker, K8s, AWS, pentest modules |
| **Safe sandboxes** | Test risky commands in isolation |
| **Pentester mode** | Evidence capture, checklists, exploit guidance |
| **History intelligence** | Auto-refactor repeated tasks |
| **Explainability** | Show prompt + reasoning for every suggestion |
| **Team sync (opt-in)** | Share policies, not data |

*All telemetry and cloud features are **opt-in only**.*

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

**License:** [Apache 2.0](https://opensource.org/licenses/Apache-2.0)

> Built with ❤️ open to contributors and collaborators from the security, devops, and AI communities.

## 🏁 Get Involved

Want to build a plugin, propose a pentest helper, or sponsor a feature? Open an issue or start a discussion at the project repo:

`https://github.com/5afagy/BashBard`

Together we’ll make BashBard an essential, trustworthy companion for anyone working at the shell.

<div align="center">

## Installation & Demo Video

[Watch: Install & Use BashBard in 60 Seconds](https://your-video-link-here.com) *(coming soon)*

<!--```bash
curl -sSL https://github.com/5afagy/BashBard/raw/refs/heads/main/install.sh | bash && BashBard
```

</div>
-->
