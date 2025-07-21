# memory.py
import json
from pathlib import Path

HISTORY_FILE = Path.home() / ".tux_tutor_history.json"

def load_history() -> list:
    if HISTORY_FILE.exists():
        try:
            return json.loads(HISTORY_FILE.read_text())
        except json.JSONDecodeError:
            return []
    return []

def save_history(history: list):
    HISTORY_FILE.write_text(json.dumps(history, indent=2))
