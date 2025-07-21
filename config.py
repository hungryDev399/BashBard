import os
from dotenv import load_dotenv

load_dotenv()  # read .env

API_KEY    = os.getenv("GEMINI_API_KEY", "")
MODEL_NAME = os.getenv("GEMINI_MODEL", "gemini-2.0-flash")

if not API_KEY:
    raise RuntimeError("GEMINI_API_KEY must be set in .env")
