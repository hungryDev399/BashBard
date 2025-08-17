#!/usr/bin/env bash
# Bash hook for Agentic Shell Guard daemon integration

# Provide a no-op preexec during sourcing to avoid recursion if a DEBUG trap is already set
__bashbard_preexec() { return 0; }

# Configuration
export BASHBARD_SOCKET="${BASHBARD_SOCKET:-/tmp/bashbard-$(id -u).sock}"
# Resolve Python from current environment (prefer venv)
# If pre-set but not found, clear it to re-resolve
if [[ -n "$BASHBARD_PYTHON" ]]; then
  if ! command -v "$BASHBARD_PYTHON" >/dev/null 2>&1; then
    unset BASHBARD_PYTHON
  fi
fi
if [[ -z "$BASHBARD_PYTHON" ]]; then
  if [[ -n "$VIRTUAL_ENV" && -x "$VIRTUAL_ENV/bin/python" ]]; then
    export BASHBARD_PYTHON="$VIRTUAL_ENV/bin/python"
  elif command -v python >/dev/null 2>&1; then
    export BASHBARD_PYTHON="$(command -v python)"
  elif command -v python3 >/dev/null 2>&1; then
    export BASHBARD_PYTHON="$(command -v python3)"
  else
    export BASHBARD_PYTHON=python3
  fi
fi

__bashbard_start_daemon() {
  if [[ -S "$BASHBARD_SOCKET" ]]; then
    return
  fi
  # Start daemon in background, redirect output
  nohup "$BASHBARD_PYTHON" -m agentic_shell_guard.daemon --socket "$BASHBARD_SOCKET" >/dev/null 2>&1 &
  # Wait briefly for socket
  for i in {1..20}; do
    [[ -S "$BASHBARD_SOCKET" ]] && break
    sleep 0.05
  done
}

__bashbard_send_json() {
  local json="$1"
  # Socket missing → daemon likely not running; fail quietly
  if [[ ! -S "$BASHBARD_SOCKET" ]]; then
    return 1
  fi
  if command -v socat >/dev/null 2>&1; then
    printf '%s\n' "$json" | socat - UNIX-CONNECT:"$BASHBARD_SOCKET"
  else
    # Fallback to python client
    "$BASHBARD_PYTHON" - "$BASHBARD_SOCKET" <<'PY'
import json, os, socket, sys
sock = sys.argv[1]
payload = sys.stdin.read()
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock)
s.sendall(payload.encode())
chunks = b""
while True:
    c = s.recv(65536)
    if not c:
        break
    chunks += c
s.close()
sys.stdout.write(chunks.decode())
PY
  fi
}

__bashbard_confirm() {
  local prompt="$1"
  local answer
  read -r -p "$prompt [y/N]: " answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

__bashbard_preexec() {
  # $BASH_COMMAND contains the current command being executed
  local cmd="$BASH_COMMAND"
  local cwd
  cwd=$(pwd)

  # Ignore our own helper commands to avoid recursion
  case "$BASH_COMMAND" in
    bashbard_*|__bashbard_*|trap*|PROMPT_COMMAND*|eval*|socat*|*agentic_shell_guard.daemon* ) return 0 ;;
  esac
  # Skip any JSON helper invocations
  if [[ "$BASH_COMMAND" == "$BASHBARD_PYTHON"* ]]; then
    return 0
  fi

  # Prevent re-entrancy
  if [[ -n "$__BASHBARD_IN_PREEXEC" ]]; then
    return 0
  fi
  __BASHBARD_IN_PREEXEC=1

  # Skip if daemon socket is missing
  [[ -S "$BASHBARD_SOCKET" ]] || { unset __BASHBARD_IN_PREEXEC; return 0; }

  # Build JSON
  local payload
  payload=$(printf '{"event":"preexec","cmd":%s,"cwd":%s}' \
    "$(printf '%s' "$cmd" | "$BASHBARD_PYTHON" -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    "$(printf '%s' "$cwd" | "$BASHBARD_PYTHON" -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")

  local resp
  resp=$(__bashbard_send_json "$payload") || { unset __BASHBARD_IN_PREEXEC; return 0; }

  # Parse with python for robustness
  local action command explanation require_confirmation reasons
  action=$("$BASHBARD_PYTHON" -c 'import json,sys; print(json.loads(sys.stdin.read()).get("action",""))' <<<"$resp")

  if [[ "$action" == "replace" ]]; then
    command=$("$BASHBARD_PYTHON" -c 'import json,sys; print(json.loads(sys.stdin.read()).get("command",""))' <<<"$resp")
    explanation=$("$BASHBARD_PYTHON" -c 'import json,sys; print(json.loads(sys.stdin.read()).get("explanation",""))' <<<"$resp")
    require_confirmation=$("$BASHBARD_PYTHON" -c 'import json,sys; d=json.loads(sys.stdin.read()); print("yes" if d.get("require_confirmation") else "no")' <<<"$resp")
    if [[ -n "$explanation" ]]; then
      echo "$explanation"
    fi
    if [[ "$require_confirmation" == "yes" ]]; then
      reasons=$("$BASHBARD_PYTHON" -c 'import json,sys; d=json.loads(sys.stdin.read()); print("\n".join("- "+r for r in d.get("danger_reasons",[])))' <<<"$resp")
      if [[ -n "$reasons" ]]; then
        echo "Reasons:"
        echo "$reasons"
      fi
      __bashbard_confirm "Run this translated command?" || { history -s "$command"; unset __BASHBARD_IN_PREEXEC; return 1; }
    fi
    # For safety in Bash, do not auto-replace here to avoid recursion.
    # Show suggestion and add to history for easy recall.
    echo "Suggested: $command"
    history -s "$command"
    unset __BASHBARD_IN_PREEXEC
    return 1
  elif [[ "$action" == "proceed" ]]; then
    require_confirmation=$("$BASHBARD_PYTHON" -c 'import json,sys; d=json.loads(sys.stdin.read()); print("yes" if d.get("require_confirmation") else "no")' <<<"$resp")
    if [[ "$require_confirmation" == "yes" ]]; then
      reasons=$("$BASHBARD_PYTHON" -c 'import json,sys; d=json.loads(sys.stdin.read()); print("\n".join("- "+r for r in d.get("danger_reasons",[])))' <<<"$resp")
      echo "\n=== DANGEROUS COMMAND ==="
      echo "$cmd"
      if [[ -n "$reasons" ]]; then
        echo "Reasons:"
        echo "$reasons"
      fi
      __bashbard_confirm "Run anyway?" || { history -s "$cmd"; unset __BASHBARD_IN_PREEXEC; return 1; }
    fi
  elif [[ "$action" == "message" ]]; then
    local message
    message=$("$BASHBARD_PYTHON" -c 'import json,sys; print(json.loads(sys.stdin.read()).get("message",""))' <<<"$resp")
    if [[ -n "$message" ]]; then
      echo "$message"
    fi
    unset __BASHBARD_IN_PREEXEC
    return 1
  fi
  unset __BASHBARD_IN_PREEXEC
}

__bashbard_postexec() {
  local last_status=$?
  local cmd=$(fc -ln -1)

  # Capture the tail of stderr from the last command if available
  # This is best-effort; many commands print directly to terminal.
  local err_tail=""
  # Users can configure their shell to redirect 2> >(tee ...) if they want richer capture.

  # Skip if daemon socket is missing
  [[ -S "$BASHBARD_SOCKET" ]] || return $last_status

  # Prevent re-entrancy
  if [[ -n "$__BASHBARD_IN_POSTEXEC" ]]; then
    return $last_status
  fi
  __BASHBARD_IN_POSTEXEC=1

  local payload
  payload=$(printf '{"event":"postexec","cmd":%s,"exit_code":%d,"stderr_tail":%s}' \
    "$(printf '%s' "$cmd" | "$BASHBARD_PYTHON" -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    "$last_status" \
    "$(printf '%s' "$err_tail" | "$BASHBARD_PYTHON" -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")

  local resp
  resp=$(__bashbard_send_json "$payload") || { unset __BASHBARD_IN_POSTEXEC; return $last_status; }

  local action
  action=$("$BASHBARD_PYTHON" -c 'import json,sys; print(json.loads(sys.stdin.read()).get("action",""))' <<<"$resp")

  if [[ "$action" == "suggest_fix" ]]; then
    local suggestion expl
    suggestion=$("$BASHBARD_PYTHON" -c 'import json,sys; print(json.loads(sys.stdin.read()).get("suggested_command",""))' <<<"$resp")
    expl=$("$BASHBARD_PYTHON" -c 'import json,sys; print(json.loads(sys.stdin.read()).get("explanation",""))' <<<"$resp")
    if [[ -n "$expl" ]]; then
      echo "$expl"
    fi
    __bashbard_confirm "Re-run with suggested fix?" && eval "$suggestion"
  fi
  unset __BASHBARD_IN_POSTEXEC
  return $last_status
}

bashbard_enable() {
  __bashbard_start_daemon
  echo "BashBard Bash hook enabled (socket: $BASHBARD_SOCKET)"
  # Pre-exec via trap DEBUG
  trap '__bashbard_preexec' DEBUG
  # Post-exec via PROMPT_COMMAND
  if [[ -n "$PROMPT_COMMAND" ]]; then
    PROMPT_COMMAND="__bashbard_postexec; $PROMPT_COMMAND"
  else
    PROMPT_COMMAND="__bashbard_postexec"
  fi
}

bashbard_disable() {
  trap - DEBUG
  PROMPT_COMMAND=""
  echo "BashBard Bash hook disabled"
}

echo "BashBard Bash hook loaded. Run: bashbard_enable"

# Restore any previous DEBUG trap definition recorded before sourcing (if any)
if [[ -n "$__BASHBARD_PREV_DEBUG_TRAP" ]]; then
  eval "$__BASHBARD_PREV_DEBUG_TRAP"
  unset __BASHBARD_PREV_DEBUG_TRAP
fi


