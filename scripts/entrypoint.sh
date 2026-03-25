#!/usr/bin/env bash
set -euo pipefail

echo "=== OpenClaw Docker Image ==="
echo "Starting initialization..."

# Run everything as root — agent gets full system access
export HOME="/home/openclaw"
export OPENCLAW_STATE_DIR="/home/openclaw/.openclaw"
export PATH="/opt/openclaw/bin:/opt/openclaw-py/bin:${PATH}"

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

# Performance: compile cache and no self-respawn in containers
export NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache
mkdir -p /var/tmp/openclaw-compile-cache
chown openclaw:openclaw /var/tmp/openclaw-compile-cache
export OPENCLAW_NO_RESPAWN=1

# Configure gateway mode and auth before doctor runs
echo "[init] Configuring gateway..."
$OPENCLAW config set gateway.mode local 2>/dev/null || true

# Generate gateway auth token if not already set
if ! $OPENCLAW config get gateway.token 2>/dev/null | grep -q .; then
    GW_TOKEN=$(openssl rand -hex 32)
    $OPENCLAW config set gateway.token "$GW_TOKEN" 2>/dev/null || true
    echo "[init] Gateway auth token generated"
fi

# Create required directories
mkdir -p /home/openclaw/.openclaw/agents/main/sessions
chown -R openclaw:openclaw /home/openclaw/.openclaw/agents
chmod 700 /home/openclaw/.openclaw

# Configure Telegram
if [ -n "${TELEGRAM_ALLOWED_USERS:-}" ]; then
    echo "[init] Configuring Telegram..."
    # Use allowlist policy (not pairing) since this is a headless server
    $OPENCLAW config set channels.telegram.dmPolicy allowlist 2>/dev/null || true
    # Set allowed user IDs (comma-separated → individual entries)
    IFS=',' read -ra TG_USERS <<< "$TELEGRAM_ALLOWED_USERS"
    ALLOW_JSON="["
    for i in "${!TG_USERS[@]}"; do
        uid=$(echo "${TG_USERS[$i]}" | xargs)
        [ "$i" -gt 0 ] && ALLOW_JSON="${ALLOW_JSON},"
        ALLOW_JSON="${ALLOW_JSON}\"${uid}\""
    done
    ALLOW_JSON="${ALLOW_JSON}]"
    $OPENCLAW config set channels.telegram.allowFrom "${ALLOW_JSON}" 2>/dev/null || true
    echo "[init] Telegram DM policy: allowlist, allowed users: ${ALLOW_JSON}"
fi

# Run doctor to auto-configure stock plugins based on env/config
echo "[init] Running openclaw doctor --fix..."
$OPENCLAW doctor --fix 2>/dev/null || true

# Lossless-Claw plugin: pre-installed in Docker image at build time.
# Only install at runtime if somehow missing (e.g. volume overwrote plugin dir).
if [ "${LCM_ENABLED:-true}" = "true" ]; then
    if $OPENCLAW plugins list 2>/dev/null | grep -q lossless-claw; then
        echo "[init] Lossless-Claw plugin present (cached in image)"
    else
        echo "[init] Lossless-Claw plugin missing — installing..."
        $OPENCLAW plugins install @martian-engineering/lossless-claw || \
            echo "[init] WARNING: Lossless-Claw plugin install failed"
    fi
fi

# Lossless-Claw: ensure DB exists
if [ "${LCM_ENABLED:-true}" = "true" ]; then
    LCM_DB="${LCM_DB_PATH:-/data/sqlite/lcm.db}"
    if [ ! -f "$LCM_DB" ]; then
        echo "[init] Creating Lossless-Claw database at $LCM_DB"
        sqlite3 "$LCM_DB" 'SELECT 1;'
    fi
    echo "[init] Lossless-Claw enabled (threshold=${LCM_CONTEXT_THRESHOLD:-0.75}, tail=${LCM_FRESH_TAIL_COUNT:-32})"
fi

# External integrations status
[ -n "${COMPOSIO_API_KEY:-}" ] && echo "[init] Composio API key configured" || echo "[init] Composio disabled (no COMPOSIO_API_KEY)"
[ -n "${HYPERSPELL_API_KEY:-}" ] && echo "[init] Hyperspell memory configured" || echo "[init] Hyperspell disabled (no HYPERSPELL_API_KEY)"
[ -n "${OPIK_API_KEY:-}" ] || [ "${OPIK_SELF_HOSTED:-true}" = "true" ] && echo "[init] Opik tracing enabled" || echo "[init] Opik disabled"

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
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "[init] ERROR: ANTHROPIC_API_KEY is required"
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

echo "[init] Initialization complete. Starting services..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/openclaw.conf
