# =============================================================================
# OpenClaw Personal AI Assistant - Full-Featured Docker Image
# Plugins: Lossless-Claw, Composio, Hyperspell, Foundry, Opik
# Features: Telegram bot, SSH routing, hardware security, cron, persistent memory
# =============================================================================

FROM node:22-bookworm-slim AS base

ARG OPENCLAW_VERSION=latest
ARG OPIK_VERSION=latest

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core tools
    git curl wget ca-certificates gnupg jq unzip \
    # Build tools
    build-essential python3 python3-pip python3-venv \
    # SSH & security
    openssh-server openssh-client libpam-google-authenticator \
    tpm2-tools libtpm2-pkcs11-1 libtpm2-pkcs11-tools \
    opensc softhsm2 libengine-pkcs11-openssl p11-kit \
    # Hardware security / YubiKey
    libpcsclite-dev pcscd yubikey-manager libfido2-dev \
    # Browser automation deps (Playwright/Puppeteer)
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
    libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2 \
    libxshmfence1 libx11-xcb1 \
    # Cron
    cron \
    # SQLite (for lossless-claw)
    sqlite3 libsqlite3-dev \
    # Reverse proxy
    debian-keyring debian-archive-keyring apt-transport-https \
    # Backup tools
    rclone \
    # Runtime package management & admin
    sudo apt-utils \
    # Misc
    dnsutils iputils-ping net-tools supervisor logrotate \
    && rm -rf /var/lib/apt/lists/*

# Install Caddy
RUN curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg && \
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list && \
    apt-get update && apt-get install -y caddy && \
    rm -rf /var/lib/apt/lists/*

# Install Go (for lossless-claw TUI and tooling)
RUN curl -fsSL https://go.dev/dl/go1.23.6.linux-amd64.tar.gz | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:${PATH}"

# Python venv for Opik, Composio, Hyperspell SDKs
RUN python3 -m venv /opt/openclaw-py && \
    /opt/openclaw-py/bin/pip install --no-cache-dir --upgrade pip setuptools wheel
ENV PATH="/opt/openclaw-py/bin:${PATH}"

# =============================================================================
# Stage: OpenClaw (use pre-built community image)
# =============================================================================
FROM alpine/openclaw:latest AS openclaw-prebuilt

# =============================================================================
# Stage: Final Image
# =============================================================================
FROM base AS final

LABEL maintainer="openclaw-image"
LABEL description="OpenClaw AI Assistant with plugins, Telegram, SSH, hardware security"

# Copy OpenClaw from pre-built image (Node.js app, entrypoint is openclaw.mjs)
COPY --from=openclaw-prebuilt /app /opt/openclaw

# Create CLI wrapper so /opt/openclaw/bin/openclaw works everywhere
RUN mkdir -p /opt/openclaw/bin && \
    printf '#!/bin/sh\nexec node /opt/openclaw/openclaw.mjs "$@"\n' > /opt/openclaw/bin/openclaw && \
    chmod +x /opt/openclaw/bin/openclaw

ENV PATH="/opt/openclaw-py/bin:/opt/openclaw/bin:${PATH}"

# Install external integrations (Python SDKs)
# These MUST succeed — no || true
RUN /opt/openclaw-py/bin/pip install --no-cache-dir \
    composio-core \
    opik

# Note: hyperspell and foundry are installed at runtime via OpenClaw's
# plugin system or MCP config, not as standalone packages.

# Create openclaw user
RUN useradd -m -s /bin/bash openclaw && \
    mkdir -p /home/openclaw/.openclaw \
             /home/openclaw/.openclaw/memory \
             /home/openclaw/.openclaw/plugins \
             /home/openclaw/.openclaw/cron \
             /home/openclaw/.openclaw/sessions \
             /home/openclaw/.openclaw/traces \
             /home/openclaw/.ssh \
             /data/memory \
             /data/sessions \
             /data/traces \
             /data/sqlite \
             /data/backups \
             /var/log/caddy && \
    chown -R openclaw:openclaw /home/openclaw /data /var/log/caddy && \
    echo "openclaw ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/openclaw && \
    chmod 0440 /etc/sudoers.d/openclaw

# =============================================================================
# SSH Configuration
# =============================================================================
RUN mkdir -p /run/sshd && \
    ssh-keygen -A && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    echo "AuthenticationMethods publickey" >> /etc/ssh/sshd_config && \
    echo "AllowUsers openclaw" >> /etc/ssh/sshd_config && \
    # FIDO2/hardware key support
    echo "PubkeyAcceptedKeyTypes sk-ssh-ed25519@openssh.com,sk-ecdsa-sha2-nistp256@openssh.com,ssh-ed25519,ecdsa-sha2-nistp256" >> /etc/ssh/sshd_config

# =============================================================================
# Configuration files
# =============================================================================
WORKDIR /opt/openclaw

# Copy configuration
COPY config/openclaw.json /home/openclaw/.openclaw/config.json
COPY config/plugins.json /home/openclaw/.openclaw/plugins.json
COPY config/telegram.json /home/openclaw/.openclaw/telegram.json
COPY config/mcp-servers.json /home/openclaw/.openclaw/mcp-servers.json
COPY config/Caddyfile /etc/caddy/Caddyfile
COPY scripts/crontab /etc/cron.d/openclaw-cron
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/healthcheck.sh /healthcheck.sh
COPY scripts/watchdog.sh /watchdog.sh
COPY scripts/backup.sh /backup.sh
COPY scripts/security-audit.sh /security-audit.sh
COPY scripts/proactive/ /opt/openclaw/proactive/
COPY config/supervisord.conf /etc/supervisor/conf.d/openclaw.conf
COPY config/logrotate.conf /etc/logrotate.d/openclaw
COPY workspace/ /home/openclaw/.openclaw/workspace/

RUN chmod +x /entrypoint.sh /healthcheck.sh /watchdog.sh /backup.sh /security-audit.sh && \
    chmod +x /opt/openclaw/proactive/*.sh && \
    chmod 0644 /etc/cron.d/openclaw-cron && \
    chown -R openclaw:openclaw /home/openclaw/.openclaw

# =============================================================================
# Pre-install plugins at build time (cached in image layer)
# =============================================================================
RUN mkdir -p /home/openclaw/.openclaw/agents/main/sessions && \
    chown -R openclaw:openclaw /home/openclaw/.openclaw && \
    su -s /bin/bash -c "PATH=/opt/openclaw/bin:\$PATH openclaw plugins install @martian-engineering/lossless-claw" openclaw && \
    echo "[build] Lossless-Claw plugin pre-installed"

# Pre-configure default model (Haiku) and model aliases
RUN su -s /bin/bash -c "PATH=/opt/openclaw/bin:\$PATH \
    openclaw models set claude-haiku-4-5-20251001 && \
    openclaw models aliases add light claude-haiku-4-5-20251001 && \
    openclaw models aliases add mid claude-sonnet-4-6 && \
    openclaw models aliases add heavy claude-opus-4-6 && \
    openclaw models fallbacks add claude-opus-4-6" openclaw && \
    echo "[build] Models: default=haiku, mid=sonnet, heavy=opus, fallback=opus"

# Volumes for persistent data
RUN mkdir -p /data/tailscale /data/sessions/archive /var/log/openclaw /var/log/supervisor

VOLUME ["/data/memory", "/data/sessions", "/data/traces", "/data/sqlite", "/data/backups", "/data/tailscale", "/home/openclaw/.ssh"]

# =============================================================================
# Tailscale (zero-trust VPN - no exposed ports)
# =============================================================================
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Ports: HTTPS (Caddy), HTTP (redirect), SSH, OpenClaw API, Opik UI
EXPOSE 443 80 22 3000 5173

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]
