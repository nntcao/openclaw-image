#!/usr/bin/env bash
# Morning Briefing - pushed to Telegram daily
# Gathers calendar, email, weather, tasks, and news into a single digest

set -euo pipefail

OPENCLAW_BIN="/opt/openclaw/bin/openclaw"
CONFIG="/home/openclaw/.openclaw/config.json"
LOG="/var/log/openclaw/morning-briefing.log"

echo "[$(date -Iseconds)] Starting morning briefing..." >> "$LOG"

$OPENCLAW_BIN run --config "$CONFIG" --channel telegram --prompt "$(cat <<'PROMPT'
Generate my morning briefing. Include these sections in order:

1. **Today's Schedule** — Check my calendar for today's events. List each with time, title, and location. Flag any conflicts or back-to-back meetings. If nothing scheduled, say so.

2. **Email Digest** — Check my inbox for unread emails since yesterday evening. Categorize as:
   - 🔴 Urgent (needs response today)
   - 🟡 Important (should read today)
   - ⚪ FYI (can wait)
   Show sender, subject, and a one-line summary for each. If inbox is empty, say so.

3. **Weather** — Current conditions and forecast for today. Include high/low temp and precipitation chance.

4. **Tasks & Reminders** — Check my task list and memory for any pending items, deadlines, or reminders for today.

5. **News Brief** — Top 3 stories relevant to my interests from the last 24 hours. One sentence each.

Keep the entire briefing under 500 words. Use a warm, natural tone — like a chief of staff giving a quick rundown.
PROMPT
)" >> "$LOG" 2>&1

echo "[$(date -Iseconds)] Morning briefing sent." >> "$LOG"
