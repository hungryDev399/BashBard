from __future__ import annotations

from typing import Dict, List
from typing_extensions import TypedDict


class State(TypedDict, total=False):
    # inputs (choose one path)
    user_request: str
    last_command: str
    last_error: str
    direct_command: str

    # candidate proposed by LLM
    candidate_command: str
    candidate_explanation: str
    candidate_mode: str  # 'run' | 'explain'

    # safety
    danger: bool
    danger_reasons: List[str]

    # approval loop
    approval: str  # 'auto', 'approved', 'rejected'
    user_feedback: str

    # execution
    result: Dict  # {'exit_code':int, 'stdout':str, 'stderr':str}

    # runtime flags
    dry_run: bool
    quiet: bool
    interactive: bool
    displayed_candidate: bool
    
    # error handling decision
    fix_decision: str  # 'llm' | 'stop'


