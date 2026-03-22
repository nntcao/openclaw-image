#!/usr/bin/env bash
# Weekly Review - comprehensive week summary every Sunday
# Reviews accomplishments, patterns, and plans for next week

set -euo pipefail

OPENCLAW_BIN="/opt/openclaw/bin/openclaw"
CONFIG="/home/openclaw/.openclaw/config.json"
LOG="/var/log/openclaw/weekly-review.log"

echo "[$(date -Iseconds)] Generating weekly review..." >> "$LOG"

$OPENCLAW_BIN run --config "$CONFIG" --channel telegram --prompt "$(cat <<'PROMPT'
Generate my weekly review for the past 7 days. Include:

1. **Accomplishments** — What we got done this week. Pull from our conversations, completed tasks, and any notable outputs.

2. **Patterns** — Anything you noticed about how I worked this week. What topics came up most? Was I focused or scattered? Any recurring frustrations?

3. **Unresolved** — Items carried over from the week that still need attention. Be specific.

4. **Next Week Preview** — Check calendar for next week. List key events, deadlines, and commitments by day.

5. **Recommendation** — One concrete suggestion for next week based on what you observed. Could be a process improvement, a task to prioritize, or something I've been avoiding.

Keep it under 500 words. Honest and direct — you're my chief of staff, not a yes-man.
PROMPT
)" >> "$LOG" 2>&1

echo "[$(date -Iseconds)] Weekly review sent." >> "$LOG"
