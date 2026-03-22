#!/usr/bin/env bash
# Healthcheck script for OpenClaw container

set -euo pipefail

# Check OpenClaw API is responding
if ! curl -sf http://localhost:3000/health > /dev/null 2>&1; then
    echo "UNHEALTHY: OpenClaw API not responding"
    exit 1
fi

# Check supervisor processes
if ! supervisorctl status openclaw 2>/dev/null | grep -q "RUNNING"; then
    echo "UNHEALTHY: OpenClaw process not running"
    exit 1
fi

# Check Telegram bot if configured
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
    if ! supervisorctl status telegram 2>/dev/null | grep -q "RUNNING"; then
        echo "UNHEALTHY: Telegram bot not running"
        exit 1
    fi
fi

echo "HEALTHY"
exit 0
