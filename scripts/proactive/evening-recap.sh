#!/usr/bin/env bash
# Evening Recap - end of day summary and next-day prep
# Runs once at end of workday

set -euo pipefail

OPENCLAW_BIN="/opt/openclaw/bin/openclaw"
CONFIG="/home/openclaw/.openclaw/config.json"
LOG="/var/log/openclaw/evening-recap.log"

echo "[$(date -Iseconds)] Generating evening recap..." >> "$LOG"

$OPENCLAW_BIN run --config "$CONFIG" --channel telegram --prompt "$(cat <<'PROMPT'
Generate my evening recap. Include:

1. **Today's Summary** — What happened today based on our conversations, tasks completed, and calendar events that occurred. Keep it brief — bullet points.

2. **Unfinished Items** — Anything I started but didn't complete, or tasks I mentioned but didn't act on. List with suggested next steps.

3. **Tomorrow's Preview** — Check tomorrow's calendar. List events with times. Flag anything that needs prep (presentations, meetings with clients, deadlines).

4. **Inbox Status** — How many unread emails remain? Any that I should address before tomorrow?

5. **Suggested Priority** — Based on everything, what's the single most important thing I should tackle first tomorrow morning?

Keep the entire recap under 300 words. Conversational tone, like a quick debrief.
PROMPT
)" >> "$LOG" 2>&1

echo "[$(date -Iseconds)] Evening recap sent." >> "$LOG"
