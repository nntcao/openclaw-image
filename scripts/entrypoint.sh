#!/usr/bin/env bash
set -euo pipefail

echo "=== OpenClaw Docker Image ==="
echo "Starting initialization..."

# ---------------------------------------------------------------------------
# Create log directories
# ---------------------------------------------------------------------------
mkdir -p /var/log/openclaw /var/log/supervisor /var/log/caddy
chown -R openclaw:openclaw /var/log/openclaw

# ---------------------------------------------------------------------------
# Tailscale (zero-trust VPN)
# ---------------------------------------------------------------------------
if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
    echo "[init] Starting Tailscale..."
    # Use userspace networking — Docker containers typically lack /dev/net/tun
    TS_FLAGS="--state=/data/tailscale/tailscaled.state"
    if [ ! -e /dev/net/tun ]; then
        echo "[init] No /dev/net/tun — using Tailscale userspace networking"
        TS_FLAGS="$TS_FLAGS --tun=userspace-networking"
    fi
    tailscaled $TS_FLAGS &
    sleep 2
    tailscale up --authkey="${TAILSCALE_AUTHKEY}" --hostname="${TAILSCALE_HOSTNAME:-openclaw}" --ssh 2>/dev/null || true
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
    echo "[init] Tailscale connected: $TAILSCALE_IP"
    echo "[init] SSH accessible via: ssh openclaw@${TAILSCALE_HOSTNAME:-openclaw}"
else
    echo "[init] Tailscale disabled (set TAILSCALE_AUTHKEY to enable)"
fi

# ---------------------------------------------------------------------------
# SSH setup
# ---------------------------------------------------------------------------
if [ "${SSH_ENABLE:-true}" = "true" ]; then
    echo "[init] Configuring SSH..."

    # Generate host keys if missing
    ssh-keygen -A 2>/dev/null || true

    # Fix permissions on mounted SSH dir (may be read-only mount, so don't fail)
    if [ -d /home/openclaw/.ssh ]; then
        chown -R openclaw:openclaw /home/openclaw/.ssh 2>/dev/null || echo "[init] WARNING: .ssh is read-only, skipping chown (mount without :ro to fix)"
        chmod 700 /home/openclaw/.ssh 2>/dev/null || true
        [ -f /home/openclaw/.ssh/authorized_keys ] && chmod 600 /home/openclaw/.ssh/authorized_keys 2>/dev/null || true
    fi

    # FIDO2 / hardware key setup
    if [ "${FIDO2_ENABLE:-false}" = "true" ]; then
        echo "[init] FIDO2 hardware key support enabled"
        # Start pcscd for smart card / YubiKey access
        pcscd --daemon 2>/dev/null || true
    fi

    echo "[init] SSH ready on port 22"
else
    echo "[init] SSH disabled"
fi

# ---------------------------------------------------------------------------
# Persistent data directory links
# ---------------------------------------------------------------------------
echo "[init] Linking persistent data..."

# Symlink memory
ln -sfn /data/memory /home/openclaw/.openclaw/memory
ln -sfn /data/sessions /home/openclaw/.openclaw/sessions
ln -sfn /data/traces /home/openclaw/.openclaw/traces

# Ensure SQLite dir exists and is writable
chown -R openclaw:openclaw /data/sqlite

# ---------------------------------------------------------------------------
# Plugin initialization (OpenClaw has 41 stock plugins — doctor enables them)
# ---------------------------------------------------------------------------
echo "[init] Initializing plugins..."
OPENCLAW="/opt/openclaw/bin/openclaw"

# Run doctor to auto-configure stock plugins based on env/config
echo "[init] Running openclaw doctor --fix..."
su -s /bin/bash -c "PATH=/opt/openclaw/bin:\$PATH $OPENCLAW doctor --fix" openclaw 2>/dev/null || true

# Lossless-Claw: ensure DB exists
if [ "${LCM_ENABLED:-true}" = "true" ]; then
    LCM_DB="${LCM_DB_PATH:-/data/sqlite/lcm.db}"
    if [ ! -f "$LCM_DB" ]; then
        echo "[init] Creating Lossless-Claw database at $LCM_DB"
        su -c "sqlite3 '$LCM_DB' 'SELECT 1;'" openclaw
    fi
    echo "[init] Lossless-Claw enabled (threshold=${LCM_CONTEXT_THRESHOLD:-0.75}, tail=${LCM_FRESH_TAIL_COUNT:-32})"
fi


# ---------------------------------------------------------------------------
# Caddy (reverse proxy / HTTPS)
# ---------------------------------------------------------------------------
if [ "${CADDY_ENABLE:-false}" = "true" ]; then
    mkdir -p /var/log/caddy /data/caddy
    if [ -n "${DOMAIN:-}" ]; then
        echo "[init] Caddy reverse proxy enabled for domain: $DOMAIN"
        if [ -z "${ACME_EMAIL:-}" ]; then
            echo "[init] WARNING: ACME_EMAIL not set - Let's Encrypt may fail"
        fi
    else
        echo "[init] Caddy enabled (localhost mode - no SSL)"
    fi
else
    echo "[init] Caddy disabled (direct port access)"
fi

# ---------------------------------------------------------------------------
# Fail2Ban (brute-force protection)
# ---------------------------------------------------------------------------
if [ "${FAIL2BAN_ENABLE:-true}" = "true" ]; then
    mkdir -p /var/run/fail2ban
    echo "[init] Fail2Ban enabled — SSH (3 attempts/ban 2h), API (20/ban 30m)"
else
    echo "[init] Fail2Ban disabled"
fi

# ---------------------------------------------------------------------------
# Backup configuration
# ---------------------------------------------------------------------------
mkdir -p /data/backups
chown openclaw:openclaw /data/backups
if [ -n "${BACKUP_REMOTE:-}" ]; then
    echo "[init] Remote backup configured: $BACKUP_REMOTE"
else
    echo "[init] Local-only backups (set BACKUP_REMOTE for offsite sync)"
fi

# ---------------------------------------------------------------------------
# Timezone
# ---------------------------------------------------------------------------
if [ -n "${TZ:-}" ]; then
    echo "[init] Timezone: $TZ"
    ln -sfn "/usr/share/zoneinfo/$TZ" /etc/localtime 2>/dev/null || true
    echo "$TZ" > /etc/timezone 2>/dev/null || true
else
    echo "[init] Timezone: UTC (set TZ env var to change)"
fi

# ---------------------------------------------------------------------------
# Proactive assistant config
# ---------------------------------------------------------------------------
echo "[init] Proactive assistant jobs configured:"
echo "       07:00 - Morning briefing"
echo "       09:30 - News digest"
echo "       */30  - Email triage (7 AM - 10 PM)"
echo "       */15  - Calendar reminders (7 AM - 10 PM)"
echo "       18:30 - Evening recap"
echo "       20:00 - Habit check-in"
echo "       Sun   - Weekly review"

# ---------------------------------------------------------------------------
# Cron jobs
# ---------------------------------------------------------------------------
echo "[init] Setting up cron jobs..."
# Crontab is already in /etc/cron.d/ with correct permissions (0644).
# cron daemon picks it up automatically — no need to load via 'crontab' command.
# (The file uses system crontab format with user fields, incompatible with 'crontab' command.)

# ---------------------------------------------------------------------------
# Config override merging
# ---------------------------------------------------------------------------
if [ -d /home/openclaw/.openclaw/config-override ] && [ "$(ls -A /home/openclaw/.openclaw/config-override 2>/dev/null)" ]; then
    echo "[init] Merging config overrides..."
    for f in /home/openclaw/.openclaw/config-override/*.json; do
        [ -f "$f" ] && echo "[init]   Merged: $(basename "$f")"
    done
fi

# ---------------------------------------------------------------------------
# Verify core requirements
# ---------------------------------------------------------------------------
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -z "${OPENAI_API_KEY:-}" ] && [ -z "${OPENROUTER_API_KEY:-}" ] && [ -z "${GROQ_API_KEY:-}" ]; then
    echo "[init] ERROR: At least one model provider API key is required"
    echo "       Set ANTHROPIC_API_KEY, OPENROUTER_API_KEY, GROQ_API_KEY, or OPENAI_API_KEY"
    exit 1
fi

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
    echo "[init] WARNING: TELEGRAM_BOT_TOKEN not set - Telegram channel will not start"
fi

# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Configure supervisord service states based on env vars
# Services default to autostart=false in supervisord.conf; enable them here.
# ---------------------------------------------------------------------------
SUPERVISOR_CONF="/etc/supervisor/conf.d/openclaw.conf"

if [ "${SSH_ENABLE:-true}" = "true" ]; then
    sed -i '/\[program:sshd\]/,/^\[/{s/autostart=false/autostart=true/}' "$SUPERVISOR_CONF"
fi

if [ "${CADDY_ENABLE:-false}" = "true" ]; then
    sed -i '/\[program:caddy\]/,/^\[/{s/autostart=false/autostart=true/}' "$SUPERVISOR_CONF"
fi

if [ "${FAIL2BAN_ENABLE:-true}" = "true" ]; then
    sed -i '/\[program:fail2ban\]/,/^\[/{s/autostart=false/autostart=true/}' "$SUPERVISOR_CONF"
fi

echo "[init] Initialization complete. Starting services..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/openclaw.conf
