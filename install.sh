#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
#  BashBard .env Setup Script
#  Prompts user for API key and writes environment file
# ==========================================================

ENV_PATH="./.env"
TEMPLATE_COMMENT="# Agentic BashBard environment example"

# --- Colors ---
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

echo -e "${CYAN}➡ Setting up your BashBard environment...${RESET}"
echo ""

# --- Ask for Gemini API key ---
read -rp "Enter your Google Gemini API key: " GEMINI_KEY

if [[ -z "$GEMINI_KEY" ]]; then
  echo -e "${YELLOW}⚠ No API key entered. Exiting setup.${RESET}"
  exit 1
fi

# --- Create or overwrite .env file ---
cat > "$ENV_PATH" <<EOF
$TEMPLATE_COMMENT
# Copy to .env and fill the values. Use a dotenv loader or export manually.

# LLM provider: "openai" (default) or "google"
LLM_PROVIDER=google

# Google Generative AI settings (used when LLM_PROVIDER=google)
GOOGLE_API_KEY=$GEMINI_KEY
GOOGLE_MODEL=gemini-2.5-flash-lite

# If set to 1, commands are not executed (dry-run)
DRY_RUN=0
EOF

echo ""
echo -e "${GREEN}✅ .env file created successfully at:${RESET} $(realpath "$ENV_PATH")"
echo ""
echo "Contents:"
echo "--------------------------------"
cat "$ENV_PATH"
echo "--------------------------------"
echo ""
echo -e "${CYAN}💡 Tip:${RESET} You can edit this file later to change provider or model."
echo -e "Example: set ${YELLOW}LLM_PROVIDER=openai${RESET} for OpenAI models."
echo ""
echo -e "${GREEN}Environment setup complete.${RESET}"
