#!/usr/bin/env bash
# News Digest - curated news based on user interests
# Runs once daily, mid-morning

set -euo pipefail

OPENCLAW_BIN="/opt/openclaw/bin/openclaw"
CONFIG="/home/openclaw/.openclaw/config.json"
LOG="/var/log/openclaw/news-digest.log"

echo "[$(date -Iseconds)] Generating news digest..." >> "$LOG"

$OPENCLAW_BIN run --config "$CONFIG" --channel telegram --prompt "$(cat <<'PROMPT'
Generate a personalized news digest. Check my memory and past conversations to understand my interests and industry.

1. Search the web for the top 5 stories from the last 24 hours relevant to my interests
2. For each story, include:
   - Headline
   - Source
   - 2-sentence summary
   - Why it matters to me specifically (based on what you know about my work/interests)

3. If there are any major breaking news stories (regardless of my interests), include those too with a "🌍 General" tag.

Format as a clean list. Start with "📰 **Your Daily Brief**"

Keep the entire digest under 400 words. Skip anything I've already seen in recent conversations.
PROMPT
)" >> "$LOG" 2>&1

echo "[$(date -Iseconds)] News digest sent." >> "$LOG"
