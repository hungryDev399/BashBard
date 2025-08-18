# BashBard Terminal - Enhanced PTY Shell

## Overview

The BashBard Terminal is now powered by a full PTY (pseudo-terminal) implementation that provides a real bash shell experience with AI enhancements. This new terminal offers:

- **Full Terminal Emulation**: Real bash shell with proper handling of colors, cursor movement, and control sequences
- **Signal Handling**: Proper support for Ctrl-C, Ctrl-Z, and Ctrl-\ signals
- **Command Interception**: AI processing of commands before execution
- **Auto-Repair**: Automatic fixing of failed commands
- **Natural Language**: Convert English requests to shell commands

## Usage

### Starting the Terminal

```bash
# Default: Launch the new PTY terminal
python -m agentic_shell_guard

# Use the legacy interactive shell
python -m agentic_shell_guard --legacy
```

### Terminal Commands

Once in the terminal, you can use these special commands:

- `/e <request>` - Convert natural language to command
  - Example: `/e show all python files in current directory`
  
- `/repair on` or `/repair interactive` - Enable auto-repair with approval prompts
- `/repair auto` - Enable auto-repair and auto-run fixes
- `/repair off` - Disable auto-repair

- `/dry on` - Enable dry-run mode (commands won't execute)
- `/dry off` - Disable dry-run mode

- `/help` - Show available commands
- `/quit` or `/exit` - Exit the terminal

### Regular Shell Usage

You can use the terminal just like a normal bash shell:

```bash
# Regular commands work as expected
ls -la
cd /path/to/directory
git status
python script.py

# Pipes, redirections, and complex commands are supported
cat file.txt | grep "pattern" | wc -l
find . -name "*.py" -exec wc -l {} \;

# Background jobs and job control work
python long_running.py &
jobs
fg %1
```

### AI Features

#### Natural Language to Command

```bash
# Use /e prefix for natural language
/e find all PDF files modified in the last week
/e show system memory usage
/e compress all images in current folder
```

#### Auto-Repair

When a command fails, the AI will suggest a fix. With `/repair auto` it will auto-run safe fixes; otherwise it will prompt:

```bash
# Type a misspelled command
sl
# AI will detect the error and suggest: ls (and prompt to run/edit/replan/cancel)

# Missing dependencies
pytohn script.py
# AI will suggest: python script.py
```

#### Safety Checks

Dangerous commands are automatically detected and require confirmation:

```bash
rm -rf /
# Warning: DANGEROUS COMMAND
# Reasons: Recursive delete from root
# Run this command? [y/N]:
```

## One-Shot Modes (Backward Compatible)

The original one-shot modes are still available:

```bash
# Convert English to command (one-shot)
python -m agentic_shell_guard --english "show disk usage"

# Fix a failing command (one-shot)
python -m agentic_shell_guard --fix --cmd "gti status" --err "bash: gti: command not found"
```

## Configuration

### Environment Variables

Create a `.env` file in the project root:

```bash
# LLM Provider (openai or google)
LLM_PROVIDER=openai

# API Keys
OPENAI_API_KEY=your-key-here
# or
GOOGLE_API_KEY=your-key-here

# Model selection
OPENAI_MODEL=gpt-4o-mini
GOOGLE_MODEL=gemini-1.5-flash

# Default modes
DRY_RUN=0  # Set to 1 for dry-run by default
QUIET=0    # Set to 1 for quiet mode
```

## Technical Details

### PTY Implementation

The new terminal uses a pseudo-terminal (PTY) to spawn a real bash process. This provides:

- Full terminal capabilities (colors, cursor control, etc.)
- Proper signal handling
- Line buffering for command interception
- Context tracking for error detection

### Command Processing Flow

1. User types command and presses Enter
2. Terminal intercepts the complete line
3. If `/e` prefix: Convert natural language to command
4. Run safety checks on the command
5. If dangerous: Request user confirmation
6. Execute command in bash
7. Monitor output for errors
8. If error detected and auto-repair enabled: Generate and execute fix

### Integration with LangGraph

The terminal integrates with the existing LangGraph workflow:

- `from_english` node: Natural language processing
- `from_error` node: Error repair logic
- `danger_check`: Safety verification
- `approval_gate`: User confirmation for dangerous commands

## Troubleshooting

### Terminal Not Starting

```bash
# Check Python version (3.8+ required)
python --version

# Install missing dependencies
pip install -r requirements.txt

# Verify API keys are set
echo $OPENAI_API_KEY
```

### Commands Not Working

- Ensure you're not in dry-run mode (`/dry off`)
- Check if auto-repair is interfering (`/repair off`)
- Use the legacy shell for comparison (`--legacy` flag)

### Performance Issues

- Reduce context tracking: The terminal keeps last 100 lines by default
- Use quiet mode to reduce output
- Consider using a faster LLM model in `.env`
