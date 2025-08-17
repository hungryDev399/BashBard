from __future__ import annotations

import os
import importlib


def get_llm():
    """Return a chat LLM instance based on env vars.

    Env:
      - LLM_PROVIDER: "openai" (default) or "google"
      - OPENAI_MODEL: default "gpt-4o-mini"
      - GOOGLE_MODEL: default "gemini-1.5-flash"
    """
    provider = os.getenv("LLM_PROVIDER")
    if not provider:
        # Prefer Google if GOOGLE_API_KEY is present, otherwise default to OpenAI
        provider = "google" if os.getenv("GOOGLE_API_KEY") else "openai"
    provider = provider.lower()
    if provider.startswith("goog"):
        try:
            mod = importlib.import_module("langchain_google_genai")
        except ModuleNotFoundError as exc:
            raise RuntimeError(
                "langchain-google-genai is not installed. Install it to use LLM_PROVIDER=google:\n"
                "  pip install langchain-google-genai"
            ) from exc
        ChatGoogleGenerativeAI = getattr(mod, "ChatGoogleGenerativeAI")
        model = os.getenv("GOOGLE_MODEL", "gemini-1.5-flash")
        return ChatGoogleGenerativeAI(model=model, temperature=0)
    else:
        try:
            mod = importlib.import_module("langchain_openai")
        except ModuleNotFoundError as exc:
            raise RuntimeError(
                "langchain-openai is not installed. Install it to use LLM_PROVIDER=openai (default):\n"
                "  pip install langchain-openai"
            ) from exc
        ChatOpenAI = getattr(mod, "ChatOpenAI")
        model = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
        return ChatOpenAI(model=model, temperature=0)


