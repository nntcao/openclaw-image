#!/usr/bin/env bash
# Watchdog - monitors all services and alerts via Telegram on failure
# Runs every 5 minutes via cron

set -euo pipefail

LOG="/var/log/openclaw/watchdog.log"
STATE_FILE="/tmp/watchdog-state"
ALERT_COOLDOWN=1800  # 30 minutes between repeated alerts for same service

# Initialize state file
touch "$STATE_FILE"

send_telegram_alert() {
    local message="$1"
    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_ALLOWED_USERS:-}" ]; then
        IFS=',' read -ra USERS <<< "$TELEGRAM_ALLOWED_USERS"
        for user_id in "${USERS[@]}"; do
            user_id=$(echo "$user_id" | xargs)
            curl -sf -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d chat_id="$user_id" \
                -d text="$message" \
                -d parse_mode="Markdown" > /dev/null 2>&1 || true
        done
    fi
}

should_alert() {
    local service="$1"
    local last_alert
    last_alert=$(grep "^${service}:" "$STATE_FILE" 2>/dev/null | cut -d: -f2)
    local now
    now=$(date +%s)

    if [ -z "$last_alert" ] || [ $((now - last_alert)) -ge $ALERT_COOLDOWN ]; then
        # Update state
        grep -v "^${service}:" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
        echo "${service}:${now}" >> "${STATE_FILE}.tmp"
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
        return 0
    fi
    return 1
}

check_service() {
    local name="$1"
    local check_cmd="$2"
    local restart_cmd="${3:-}"

    if ! eval "$check_cmd" > /dev/null 2>&1; then
        echo "[$(date -Iseconds)] FAIL: $name" >> "$LOG"

        # Attempt restart if command provided
        if [ -n "$restart_cmd" ]; then
            echo "[$(date -Iseconds)] Restarting $name..." >> "$LOG"
            eval "$restart_cmd" >> "$LOG" 2>&1 || true
            sleep 5

            # Check again after restart
            if eval "$check_cmd" > /dev/null 2>&1; then
                echo "[$(date -Iseconds)] $name recovered after restart" >> "$LOG"
                if should_alert "$name"; then
                    send_telegram_alert "⚠️ *Watchdog*: $name went down and was auto-recovered."
                fi
                return 0
            fi
        fi

        # Still down — alert
        if should_alert "$name"; then
            send_telegram_alert "🔴 *Watchdog Alert*: $name is DOWN and could not be recovered. Manual intervention needed."
        fi
        return 1
    fi
    return 0
}

echo "[$(date -Iseconds)] Watchdog check starting..." >> "$LOG"

FAILURES=0

# Check OpenClaw API
check_service "OpenClaw API" \
    "curl -sf http://localhost:3000/health" \
    "supervisorctl restart openclaw" || ((FAILURES++))

# Check Telegram bot
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
    check_service "Telegram Bot" \
        "supervisorctl status telegram | grep -q RUNNING" \
        "supervisorctl restart telegram" || ((FAILURES++))
fi

# Check Opik
if [ "${OPIK_SELF_HOSTED:-true}" = "true" ]; then
    check_service "Opik Tracing" \
        "supervisorctl status opik | grep -q RUNNING" \
        "supervisorctl restart opik" || ((FAILURES++))
fi

# Check SSH
if [ "${SSH_ENABLE:-true}" = "true" ]; then
    check_service "SSH" \
        "supervisorctl status sshd | grep -q RUNNING" \
        "supervisorctl restart sshd" || ((FAILURES++))
fi

# Check disk space (alert if >90%)
DISK_USAGE=$(df /data | tail -1 | awk '{print $5}' | tr -d '%')
if [ "$DISK_USAGE" -ge 90 ]; then
    echo "[$(date -Iseconds)] WARN: Disk usage at ${DISK_USAGE}%" >> "$LOG"
    if should_alert "disk"; then
        send_telegram_alert "⚠️ *Watchdog*: Disk usage is at *${DISK_USAGE}%*. Consider cleaning up old traces/sessions."
    fi
fi

# Check memory usage (alert if >90%)
MEM_USAGE=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')
if [ "$MEM_USAGE" -ge 90 ]; then
    echo "[$(date -Iseconds)] WARN: Memory usage at ${MEM_USAGE}%" >> "$LOG"
    if should_alert "memory"; then
        send_telegram_alert "⚠️ *Watchdog*: Memory usage is at *${MEM_USAGE}%*. Services may become unstable."
    fi
fi

if [ "$FAILURES" -eq 0 ]; then
    echo "[$(date -Iseconds)] All services healthy." >> "$LOG"
fi
