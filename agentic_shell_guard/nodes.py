from __future__ import annotations

import json
import os
import subprocess
from typing import Dict
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeoutError

from .llm import get_llm
from .safety import check_danger
from .state import State


_LLM = None


def _ensure_llm():
    global _LLM
    if _LLM is None:
        _LLM = get_llm()
    return _LLM


def _llm_invoke_with_timeout(llm, prompt: str, timeout_seconds: int = 30):
    # Ensure this starts on a fresh line for better UX when used in PTY
    print(f"\n[LLM] Contacting provider... (timeout {timeout_seconds}s)")
    with ThreadPoolExecutor(max_workers=1) as pool:
        future = pool.submit(llm.invoke, prompt)
        try:
            return future.result(timeout=timeout_seconds)
        except FuturesTimeoutError as exc:
            raise TimeoutError("LLM request timed out") from exc


def route(state: State):
    if state.get("user_request"):
        return "from_english"
    if state.get("last_command") and state.get("last_error"):
        return "from_error"
    if state.get("direct_command"):
        return "from_direct"
    raise ValueError("Provide either --english or --fix with --cmd and --err")


def _parse_llm_json(content: str) -> Dict[str, str]:
    text = content.strip()
    if text.startswith("```"):
        lines = text.splitlines()
        body = "\n".join(lines[1:])
        if body.rstrip().endswith("```"):
            body = body.rstrip()[:-3]
        text = body.strip()
    try:
        return json.loads(text)
    except Exception:
        try:
            start = text.index('{')
            end = text.rindex('}') + 1
            return json.loads(text[start:end])
        except Exception:
            return {"command": text, "explanation": "Model returned plain text; review carefully.", "mode": "run"}


def from_english(state: State) -> State:
    llm = _ensure_llm()
    strict = bool(state.get("strict_json"))
    base_prompt = (
        "You are a Linux shell expert. Convert the user's natural-language request into a single, safe (if possible), POSIX-compatible command when possible.\n"
        "If the command is dangerous, return the command and explanation; a separate danger check will assess it before running.\n"
        "Return ONLY JSON with keys: command, explanation, mode. NO prose, NO code fences.\n"
        "If no safe/runnable command is appropriate, set mode to 'explain' and put your guidance in 'explanation' and leave 'command' empty.\n"
        f"Request: {state['user_request']}"
    )
    prompts = [base_prompt]
    if strict:
        prompts.append(base_prompt + "\nRespond STRICTLY in JSON. No extra text. Schema: {\"command\": string, \"explanation\": string, \"mode\": \"run\"|\"explain\"}.")

    last_exc = None
    for p in prompts:
        try:
            msg = _llm_invoke_with_timeout(llm, p)
        except Exception as e:
            last_exc = e
            continue
        data = _parse_llm_json(getattr(msg, "content", str(msg)))
        # If parser fell back to "plain text" message, retry if strict
        if strict and (data.get("explanation", "").lower().startswith("model returned plain text")):
            continue
        mode = (data.get("mode") or "run").strip().lower()
        return {"candidate_command": data.get("command", ""), "candidate_explanation": data.get("explanation", ""), "candidate_mode": mode}
    # All attempts failed
    if last_exc is not None:
        return {"candidate_command": "", "candidate_explanation": f"LLM error: {last_exc}", "candidate_mode": "explain"}
    return {"candidate_command": "", "candidate_explanation": "", "candidate_mode": "explain"}


def from_error(state: State) -> State:
    llm = _ensure_llm()
    intent = state.get("user_request", "")
    strict = bool(state.get("strict_json"))
    base_prompt = (
        "You are a Linux CLI fixer. Given a command that failed and its error output, propose a corrected command.\n"
        "Assume a typical Debian/Ubuntu environment unless specified.\n"
        "If the intent is ambiguous, choose the most likely command.\n"
        "Return ONLY JSON: {command, explanation, mode}. NO prose, NO code fences.\n"
        "If the best action is to explain instead of running anything (e.g., user typed a non-existent command or must supply operands), set mode to 'explain' and leave 'command' empty.\n\n"
        f"Intent (optional): {intent}\n"
        f"Command: {state['last_command']}\n"
        f"Error: {state['last_error']}\n"
    )
    prompts = [base_prompt]
    if strict:
        prompts.append(base_prompt + "\nRespond STRICTLY in JSON. No extra text. Schema: {\"command\": string, \"explanation\": string, \"mode\": \"run\"|\"explain\"}.")

    last_exc = None
    for p in prompts:
        try:
            msg = _llm_invoke_with_timeout(llm, p)
        except Exception as e:
            last_exc = e
            continue
        data = _parse_llm_json(getattr(msg, "content", str(msg)))
        if strict and (data.get("explanation", "").lower().startswith("model returned plain text")):
            continue
        mode = (data.get("mode") or "run").strip().lower()
        return {"candidate_command": data.get("command", ""), "candidate_explanation": data.get("explanation", ""), "candidate_mode": mode}
    if last_exc is not None:
        return {"candidate_command": "", "candidate_explanation": f"LLM error: {last_exc}", "candidate_mode": "explain"}
    return {"candidate_command": "", "candidate_explanation": "", "candidate_mode": "explain"}


def from_direct(state: State) -> State:
    # Pass through a directly-entered shell command
    cmd = state.get("direct_command", "").strip()
    if not cmd:
        return {"candidate_command": "", "candidate_explanation": ""}
    return {"candidate_command": cmd, "candidate_explanation": "Direct command", "candidate_mode": "run", "source": "direct"}


def danger_check(state: State) -> State:
    # Base check on the actual command
    out = check_danger(state["candidate_command"]) if state.get("candidate_command") else {"danger": True, "reasons": ["No command generated"]}

    # Augment with intent/explanation signals (prompt even if LLM "simulates" with echo)
    reasons = list(out["reasons"]) if isinstance(out.get("reasons"), list) else []
    is_danger = bool(out["danger"])

    req = (state.get("user_request") or "").lower()
    expl = (state.get("candidate_explanation") or "").lower()
    intent_keywords = [
        "delete the root", "rm -rf /", "wipe disk", "format /", "destroy all", "erase all",
        "drop database", "remove all files", "shred", "mkfs", "reboot", "shutdown",
    ]
    if any(k in req for k in intent_keywords):
        is_danger = True
        reasons.append("User intent appears destructive")
    if ("dangerous" in expl) or ("warning" in expl) or ("destructive" in expl):
        is_danger = True
        reasons.append("Explanation indicates danger")

    return {"danger": is_danger, "danger_reasons": reasons}


def approval_gate(state: State) -> State:
    # Bypass approval for direct commands entered by the user
    if state.get("source") == "direct":
        return {"approval": "auto"}
    # If the model requested explanation-only, print and end
    if state.get("candidate_mode") == "explain":
        return {"approval": "cancelled"}
    # Heuristic: if the command includes placeholders like <directory_name>, do not run
    cmd_text = (state.get("candidate_command") or "").strip()
    if cmd_text and ("<" in cmd_text and ">" in cmd_text):
        expl = state.get("candidate_explanation") or "The proposed command includes placeholders (e.g., <...>). Replace them with real values and run again."
        return {"approval": "cancelled", "candidate_mode": "explain", "candidate_explanation": expl}
    # Unified prompt for all commands: show candidate and ask for confirmation
    is_dangerous = bool(state.get("danger"))
    if is_dangerous:
        
        print("\n=== DANGEROUS COMMAND ===")
        print(f"$ {state['candidate_command']}")
        if state.get("candidate_explanation"):
            print(f"↳ {state['candidate_explanation']}")
    else:
        # Safe command: show explanation then auto-run
        if state.get("candidate_explanation") and not state.get("quiet"):
            print(f"\nCommand: $ {state['candidate_command']}")
            print(f"↳ {state['candidate_explanation']}")
        return {"approval": "auto"}
    if is_dangerous and state.get("danger_reasons"):
        print("Reasons:")
        for r in state.get("danger_reasons", []):
            print(f" - {r}")
    ans = input("Run this command? [y/N] (y to run, n to cancel, e to replan): ").strip().lower()
    if ans in ("y", "yes"):
        return {"approval": "approved"}
    elif ans == 'e':
        fb = input("Describe adjustments for a safer alternative (or leave blank to skip): ").strip()
        return {"approval": "rejected", "user_feedback": fb}
    else:
        # Cancel immediately and end this request
        return {"approval": "cancelled"}


def replan(state: State) -> State:
    llm = _ensure_llm()
    feedback = state.get("user_feedback", "Safer alternative")
    prompt = (
        "Rewrite the following shell command to satisfy the user's feedback while minimizing risk.\n"
        "Prefer read-only or non-destructive forms. If write action is required, add the smallest scope and backup/--dry-run flags where available.\n"
        "Return JSON: {command, explanation}.\n\n"
        f"Original: {state.get('candidate_command','')}\n"
        f"Feedback: {feedback}\n"
    )
    try:
        msg = _llm_invoke_with_timeout(llm, prompt)
    except Exception as e:
        return {"candidate_command": "", "candidate_explanation": f"LLM error: {e}"}
    data = _parse_llm_json(getattr(msg, "content", str(msg)))
    return {"candidate_command": data.get("command", ""), "candidate_explanation": data.get("explanation", "")}


def run_command(state: State) -> State:
    cmd = state.get("candidate_command", "")
    if not cmd:
        return {"result": {"exit_code": 1, "stdout": "", "stderr": "No command to run."}}

    dry = state.get("dry_run") is True if state.get("dry_run") is not None else (os.getenv("DRY_RUN", "1") == "1")
    if dry:
        print(f"\r\n[DRY-RUN] Would execute: $ {cmd}")
        return {"result": {"exit_code": 0, "stdout": "(dry-run) not executed", "stderr": ""}}

    print(f"\r\n[RUN] $ {cmd}")
    proc = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    res: Dict[str, object] = {"exit_code": proc.returncode, "stdout": proc.stdout, "stderr": proc.stderr}
    if not state.get("quiet"):
        print("-- stdout --\n" + (proc.stdout or ""))
        if proc.stderr:
            print("-- stderr --\n" + proc.stderr)
    if proc.returncode != 0:
        return {"result": res, "last_command": cmd, "last_error": proc.stderr or "(no stderr captured)"}
    return {"result": res}


def error_decision(state: State) -> State:
    # Non-interactive: default to not fixing automatically
    if not state.get("interactive"):
        return {"fix_decision": "stop"}
    # Interactive: ask the user if they'd like LLM to try a fix
    print("The last command failed.")
    while True:
        ans = input("Ask the AI to suggest a fix? [y/N]: ").strip().lower()
        if ans in ("y", "yes"):
            return {"fix_decision": "llm"}
        if ans in ("n", "no", ""):
            return {"fix_decision": "stop"}
        print("Please answer 'y' or 'n'.")


