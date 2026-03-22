#!/usr/bin/env bash
# Calendar Reminders - sends upcoming meeting alerts
# Runs every 15 minutes, alerts for events starting within 15 minutes

set -euo pipefail

OPENCLAW_BIN="/opt/openclaw/bin/openclaw"
CONFIG="/home/openclaw/.openclaw/config.json"
LOG="/var/log/openclaw/calendar-reminders.log"

echo "[$(date -Iseconds)] Checking upcoming events..." >> "$LOG"

$OPENCLAW_BIN run --config "$CONFIG" --channel telegram --prompt "$(cat <<'PROMPT'
Check my calendar for any events starting in the next 15 minutes.

If there is an upcoming event:
1. Send a reminder with the event title, time, location (if any), and meeting link (if any)
2. If it's a meeting with other people, briefly check my recent emails and memory for any relevant context about the attendees or topic — include a 1-2 sentence prep note
3. Format as: "⏰ **In 15 min**: [Event Title] at [Time]\n[Location/Link]\n📋 [Prep note if applicable]"

If no events are coming up in the next 15 minutes, do NOT send any message — stay completely silent.
PROMPT
)" >> "$LOG" 2>&1

echo "[$(date -Iseconds)] Calendar check complete." >> "$LOG"
