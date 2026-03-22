#!/usr/bin/env bash
# Email Triage - checks inbox and notifies on urgent items
# Runs every 30 minutes during waking hours

set -euo pipefail

OPENCLAW_BIN="/opt/openclaw/bin/openclaw"
CONFIG="/home/openclaw/.openclaw/config.json"
LOG="/var/log/openclaw/email-triage.log"

echo "[$(date -Iseconds)] Running email triage..." >> "$LOG"

$OPENCLAW_BIN run --config "$CONFIG" --channel telegram --prompt "$(cat <<'PROMPT'
Check my email inbox for new unread messages received in the last 30 minutes.

For each new email:
1. Classify urgency: URGENT / IMPORTANT / LOW
2. Extract: sender name, subject, one-line summary

Rules:
- URGENT: from my boss/manager, contains words like "ASAP", "urgent", "deadline today", "emergency", meeting cancellation/change within 2 hours
- IMPORTANT: from known contacts, action items, meeting invites, requires a decision
- LOW: newsletters, notifications, automated emails, marketing

Only message me if there are URGENT or IMPORTANT emails. For URGENT, include the full summary. For IMPORTANT, include just sender + subject + one line.

If nothing urgent or important, do NOT send any message — stay silent.

If there ARE urgent items, start with "📬 **Email Alert**" so I know immediately.
PROMPT
)" >> "$LOG" 2>&1

echo "[$(date -Iseconds)] Email triage complete." >> "$LOG"
