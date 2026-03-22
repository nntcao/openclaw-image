#!/usr/bin/env bash
# Habit Check-in - daily prompt for habit tracking
# Asks about configured habits and logs responses to memory

set -euo pipefail

OPENCLAW_BIN="/opt/openclaw/bin/openclaw"
CONFIG="/home/openclaw/.openclaw/config.json"
LOG="/var/log/openclaw/habit-checkin.log"

echo "[$(date -Iseconds)] Sending habit check-in..." >> "$LOG"

$OPENCLAW_BIN run --config "$CONFIG" --channel telegram --prompt "$(cat <<'PROMPT'
Send a brief habit check-in message. Check my memory for any habits I've asked you to track.

If I have tracked habits:
- Ask about each one naturally (not like a form)
- Reference yesterday's data if available
- Keep it casual: "Hey — did you get your workout in today? How about reading?"

If I haven't set up any habits yet:
- Ask if I'd like to start tracking anything
- Suggest common options: exercise, reading, water intake, sleep, meditation, journaling
- Say you'll track it daily and give me a weekly summary

When I reply, save my responses to memory with today's date.
PROMPT
)" >> "$LOG" 2>&1

echo "[$(date -Iseconds)] Habit check-in sent." >> "$LOG"
