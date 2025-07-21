import httpx
import config
from functools import lru_cache

SYSTEM_PROMPT = """
You are an expert Linux shell tutor. You will be given either:
- A mistyped shell command and its error output, OR
- A plain-English description of what the user wants to do.

For mistyped commands:
1) Identify the intended command.
2) Provide the corrected command.
3) Explain in one sentence why.

For English requests:
1) Generate the exact shell command that accomplishes the request.
2) Provide a brief explanation of each flag used.

Always reply in Markdown, with code fences around commands.
"""

BASE_URL = "https://generativelanguage.googleapis.com/v1beta"
_client = httpx.Client(http2=True, timeout=15.0)

@lru_cache(maxsize=256)
def ask_tutor(prompt: str) -> str:
    """
    Send user prompt to Gemini/OpenAI and return the Markdown response.
    """
    url = (
        f"{BASE_URL}/models/{config.MODEL_NAME}:generateContent"
        f"?key={config.API_KEY}"
    )
    body = {
        "system_instruction": {"parts":[{"text": SYSTEM_PROMPT}]},
        "contents":     [{"parts":[{"text": prompt}]}]
    }
    resp = _client.post(url, json=body)
    resp.raise_for_status()
    data = resp.json()
    cand = data.get("candidates", [])
    if not cand:
        return "❌ Tutor did not return any response."
    parts = cand[0]["content"]["parts"]
    return "".join(p["text"] for p in parts)
