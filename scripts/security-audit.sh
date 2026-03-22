#!/usr/bin/env bash
# Security Audit - periodic security check and hardening verification
# Runs daily, alerts on any findings

set -euo pipefail

LOG="/var/log/openclaw/security-audit.log"
FINDINGS=""
SEVERITY="INFO"

echo "[$(date -Iseconds)] Starting security audit..." >> "$LOG"

# --- Check for unauthorized SSH access attempts ---
if [ "${SSH_ENABLE:-true}" = "true" ]; then
    FAILED_SSH=$(grep -c "Failed password\|Failed publickey" /var/log/auth.log 2>/dev/null || echo 0)
    if [ "$FAILED_SSH" -gt 100 ]; then
        FINDINGS="${FINDINGS}\n🔴 HIGH: $FAILED_SSH failed SSH attempts in auth.log"
        SEVERITY="HIGH"
    elif [ "$FAILED_SSH" -gt 20 ]; then
        FINDINGS="${FINDINGS}\n🟡 MEDIUM: $FAILED_SSH failed SSH attempts in auth.log"
        [ "$SEVERITY" = "INFO" ] && SEVERITY="MEDIUM"
    fi
fi

# --- Check file permissions ---
if [ -f /home/openclaw/.openclaw/config.json ]; then
    PERMS=$(stat -c %a /home/openclaw/.openclaw/config.json 2>/dev/null || echo "unknown")
    if [ "$PERMS" != "600" ] && [ "$PERMS" != "640" ] && [ "$PERMS" != "644" ]; then
        FINDINGS="${FINDINGS}\n🟡 Config file permissions too open: $PERMS"
        [ "$SEVERITY" = "INFO" ] && SEVERITY="MEDIUM"
    fi
fi

# --- Check for world-readable secrets ---
for f in /home/openclaw/.openclaw/*.json; do
    if [ -f "$f" ] && grep -qE '"(sk-|ghp_|xoxb-|api[_-]?key)' "$f" 2>/dev/null; then
        PERMS=$(stat -c %a "$f" 2>/dev/null || echo "unknown")
        if [ "${PERMS:2:1}" != "0" ]; then
            FINDINGS="${FINDINGS}\n🔴 HIGH: $f contains secrets and is world-readable"
            SEVERITY="HIGH"
        fi
    fi
done

# --- Check for processes running as root that shouldn't be ---
ROOT_PROCS=$(ps aux | grep -E "openclaw|opik|composio" | grep "^root" | grep -v grep | wc -l)
if [ "$ROOT_PROCS" -gt 0 ]; then
    FINDINGS="${FINDINGS}\n🟡 $ROOT_PROCS openclaw-related processes running as root"
    [ "$SEVERITY" = "INFO" ] && SEVERITY="MEDIUM"
fi

# --- Check disk encryption (if available) ---
if command -v lsblk &> /dev/null; then
    UNENCRYPTED=$(lsblk -o NAME,TYPE,FSTYPE | grep -c "part.*ext4" || echo 0)
    # Just log, don't alert — informational
    echo "[$(date -Iseconds)] Unencrypted ext4 partitions: $UNENCRYPTED" >> "$LOG"
fi

# --- Check for outdated packages with known CVEs ---
if command -v apt-get &> /dev/null; then
    UPGRADABLE=$(apt-get -s upgrade 2>/dev/null | grep -c "^Inst" || echo 0)
    if [ "$UPGRADABLE" -gt 20 ]; then
        FINDINGS="${FINDINGS}\n🟡 $UPGRADABLE packages have available security updates"
        [ "$SEVERITY" = "INFO" ] && SEVERITY="MEDIUM"
    fi
fi

# --- Check OpenClaw security audit (if available) ---
if [ -x /opt/openclaw/bin/openclaw ]; then
    /opt/openclaw/bin/openclaw security audit --deep >> "$LOG" 2>&1 || true
fi

# --- Report ---
if [ -n "$FINDINGS" ]; then
    echo -e "[$(date -Iseconds)] Findings:${FINDINGS}" >> "$LOG"

    # Alert via Telegram if MEDIUM or HIGH
    if [ "$SEVERITY" != "INFO" ] && [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_ALLOWED_USERS:-}" ]; then
        MSG="🔒 *Security Audit* ($SEVERITY)\n${FINDINGS}"
        IFS=',' read -ra USERS <<< "$TELEGRAM_ALLOWED_USERS"
        for user_id in "${USERS[@]}"; do
            user_id=$(echo "$user_id" | xargs)
            curl -sf -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d chat_id="$user_id" \
                -d text="$(echo -e "$MSG")" \
                -d parse_mode="Markdown" > /dev/null 2>&1 || true
        done
    fi
else
    echo "[$(date -Iseconds)] No findings — all checks passed." >> "$LOG"
fi

echo "[$(date -Iseconds)] Security audit complete. Severity: $SEVERITY" >> "$LOG"
