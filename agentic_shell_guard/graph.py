from __future__ import annotations

from langgraph.graph import StateGraph, END

from .state import State
from .nodes import (
    route,
    from_english,
    from_error,
    from_direct,
    danger_check,
    approval_gate,
    replan,
    run_command,
    error_decision,
)


def build_graph():
    g = StateGraph(State)
    g.add_node("from_english", from_english)
    g.add_node("from_error", from_error)
    g.add_node("from_direct", from_direct)
    g.add_node("danger_check", danger_check)
    g.add_node("approval_gate", approval_gate)
    g.add_node("replan", replan)
    g.add_node("run", run_command)

    g.set_entry_point("router")
    g.add_node("router", lambda s: s)
    g.add_conditional_edges("router", route, {
        "from_english": "from_english",
        "from_error": "from_error",
        "from_direct": "from_direct",
    })

    g.add_edge("from_english", "danger_check")
    g.add_edge("from_error", "danger_check")
    # Direct commands bypass approval and run immediately
    g.add_edge("from_direct", "run")
    g.add_edge("danger_check", "approval_gate")

    def post_approval(state: State):
        decision = state.get("approval")
        if decision in ("auto", "approved"):
            return "run"
        if decision == "cancelled":
            return "end"
        return "replan"

    g.add_conditional_edges("approval_gate", post_approval, {"run": "run", "replan": "replan", "end": END})
    g.add_edge("replan", "danger_check")

    def post_run(state: State):
        res = state.get("result") or {}
        exit_code = res.get("exit_code")
        if isinstance(exit_code, int) and exit_code != 0:
            return "decide"
        return "ok"

    g.add_conditional_edges("run", post_run, {"ok": END, "decide": "error_decision"})
    g.add_node("error_decision", error_decision)

    def post_decision(state: State):
        if state.get("fix_decision") == "llm":
            return "fix"
        return "end"

    g.add_conditional_edges("error_decision", post_decision, {"fix": "from_error", "end": END})

    return g.compile()


