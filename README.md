# OpenClaw Personal AI Assistant - Docker Image

A fully configured Docker image that turns [OpenClaw](https://github.com/openclaw/openclaw) into a 24/7 personal AI assistant you talk to via Telegram. It handles your email, calendar, news, habits, and tasks — proactively, on a schedule, without you asking.

Runs on a cheap VPS ($4.50/mo) with smart model routing that keeps API costs around $5-15/mo.

## What's Included

### Model Routing (4 tiers)

Requests are automatically classified and sent to the cheapest model that can handle them:

| Tier | Provider | Model | Cost | Handles |
|------|----------|-------|------|---------|
| Free | OpenRouter | DeepSeek R1 | $0 | Greetings, simple Q&A, lookups, formatting |
| Cheap | Groq | Llama 4 Scout | $0.11/M tokens | Tool dispatch, classification, extraction |
| Standard | Anthropic | Claude Sonnet | $3/M tokens | Code, analysis, planning, multi-step |
| Heavy | Anthropic | Claude Opus | $15/M tokens | Complex reasoning, architecture, research |

### Plugins

- **[Lossless-Claw](https://github.com/Martian-Engineering/lossless-claw)** — Context management via DAG summarization. Never loses conversation history, even across long sessions.
- **Composio** — Managed integrations (Gmail, Calendar, GitHub, Slack, Notion). One OAuth click per app — Composio handles token refresh and rate limits.
- **Hyperspell** — Knowledge graph memory. Injects only relevant context before each step instead of loading everything.
- **Foundry** — Watches your workflows and generates persistent tool definitions from repeated patterns.
- **Opik** — Structured tracing. Captures LLM calls, tool I/O, latency, and token usage as spans.

### Proactive Assistant

Scheduled jobs pushed to Telegram automatically:

| Time | Job |
|------|-----|
| 7:00 AM | Morning briefing (calendar, email digest, weather, tasks, news) |
| 9:30 AM | Personalized news digest |
| Every 30 min | Email triage (alerts only on urgent — stays silent otherwise) |
| Every 15 min | Calendar reminders (15 min before meetings, with prep notes) |
| 6:30 PM | Evening recap (day summary, unfinished items, tomorrow preview) |
| 8:00 PM | Habit check-in |
| Sunday 10 AM | Weekly review |

All times respect your `TZ` environment variable.

### Security

- **Tailscale** — Zero-trust VPN. SSH via private mesh network, no public ports exposed.
- **Fail2Ban** — Auto-bans brute force attempts (SSH, API, Telegram webhook).
- **SSH hardening** — Key-only auth, no root, no passwords, FIDO2/YubiKey support.
- **Caddy** — Reverse proxy with automatic HTTPS via Let's Encrypt (optional).
- **Daily security audits** — Checks file permissions, failed SSH attempts, running processes, package updates. Alerts to Telegram on findings.
- **Container hardening** — Dropped capabilities, no-new-privileges, non-root user.

### Infrastructure

- **Automated backups** — Daily at 2 AM. SQLite-safe dumps, config (secrets redacted), memory. 30-day rotation. Optional rclone sync to S3/GCS.
- **Watchdog** — Checks all services every 5 min. Auto-restarts on failure, alerts to Telegram with 30-min cooldown. Monitors disk and memory usage.
- **Log rotation** — Proper logrotate with 14-day retention.
- **Supervisor** — Process manager for all services with auto-restart.

### Workspace Files

OpenClaw reads these Markdown files to shape its personality and behavior:

| File | Purpose |
|------|---------|
| `AGENTS.md` | Core rules: security, memory management, communication, task execution |
| `SOUL.md` | Personality: warm but direct, action-oriented, anti-sycophantic |
| `MEMORY.md` | Long-term memory (starts empty, builds through conversations) |
| `TOOLS.md` | Environment reference: integrations, routing tiers, scheduled jobs |
| `IDENTITY.md` | Name and role |
| `HEARTBEAT.md` | What to check every 30 min (pending reminders, quiet hours) |
| `BOOT.md` | What to do on gateway restart |
| `BOOTSTRAP.md` | First-run onboarding (asks who you are, then self-deletes) |

## Setup

### 1. Get Your API Keys

| Service | What | Link |
|---------|------|------|
| Anthropic | API key + set $25/mo spend limit | [console.anthropic.com](https://console.anthropic.com) |
| OpenRouter | API key (free tier: 200 req/day) | [openrouter.ai](https://openrouter.ai) |
| Groq | API key (free tier available) | [console.groq.com](https://console.groq.com) |
| Telegram | Bot token via @BotFather, user ID via @userinfobot | [telegram.org](https://telegram.org) |
| Composio | API key (one key for all integrations) | [app.composio.dev](https://app.composio.dev) |
| Tailscale | Auth key (reusable) | [tailscale.com](https://tailscale.com) |

### 2. Get a VPS

Any Linux VPS with 2GB+ RAM works. Recommended:

| Provider | Specs | Price |
|----------|-------|-------|
| Hetzner | 2 vCPU, 4GB RAM, 40GB | $4.50/mo |
| Contabo | 4 vCPU, 8GB RAM, 200GB | $7/mo |
| DigitalOcean | 1 vCPU, 2GB RAM, 50GB | $12/mo |

Create with Ubuntu 24.04 LTS and your SSH key.

### 3. Deploy

```bash
# SSH into your VPS
ssh root@YOUR_IP

# Install Docker
curl -fsSL https://get.docker.com | sh
systemctl enable docker

# Firewall (temporary — Tailscale replaces this)
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw enable

# Clone and configure
cd /opt
git clone https://github.com/nntcao/openclaw-image.git
cd openclaw-image
cp .env.example .env
nano .env
```

Fill in your keys in `.env`:

```bash
ANTHROPIC_API_KEY=sk-ant-xxxxx
OPENROUTER_API_KEY=sk-or-xxxxx
GROQ_API_KEY=gsk_xxxxx
TELEGRAM_BOT_TOKEN=7123456789:AAFxxxxx
TELEGRAM_ALLOWED_USERS=123456789
COMPOSIO_API_KEY=xxxxx
TAILSCALE_AUTHKEY=tskey-auth-xxxxx
TZ=America/New_York
```

Set up SSH keys for the container:

```bash
mkdir -p ssh
cp ~/.ssh/authorized_keys ssh/authorized_keys
```

Build and launch:

```bash
docker compose build
docker compose up -d
docker compose logs -f
```

### 4. Verify

1. **Telegram** — Message your bot. It should respond with the first-run onboarding.
2. **Tailscale** — On your laptop: `ssh openclaw@openclaw`
3. **Lock down** — Once Tailscale works: `ufw delete allow 22/tcp`

### 5. Connect Apps

Go to [app.composio.dev](https://app.composio.dev) and connect Gmail, Google Calendar, GitHub, Slack, etc. via OAuth. The assistant picks these up automatically.

## Cheat Sheet

```bash
# SSH in via Tailscale
ssh openclaw@openclaw

# Logs
docker compose logs -f
docker compose logs -f telegram

# Restart
docker compose restart

# Run a proactive job manually
docker compose exec openclaw /opt/openclaw/proactive/morning-briefing.sh

# Check backups
docker compose exec openclaw ls -lh /data/backups/

# Security audit
docker compose exec openclaw /security-audit.sh

# Update
cd /opt/openclaw-image
git pull
docker compose build
docker compose up -d
```

## Monthly Cost

| Item | Cost |
|------|------|
| Hetzner VPS | $4.50 |
| Anthropic API (with routing) | ~$5-15 |
| OpenRouter | Free |
| Groq | Free |
| Tailscale | Free |
| Telegram | Free |
| Composio | Free tier |
| **Total** | **~$10-20/mo** |

## Project Structure

```
openclaw-image/
├── Dockerfile                          # Multi-stage build
├── docker-compose.yml                  # Service orchestration
├── .env.example                        # All configurable env vars
├── config/
│   ├── openclaw.json                   # Core config (routing, memory, security)
│   ├── plugins.json                    # Plugin registry
│   ├── telegram.json                   # Telegram bot config
│   ├── mcp-servers.json                # MCP server definitions (Composio, Foundry)
│   ├── supervisord.conf                # Process management
│   ├── Caddyfile                       # Reverse proxy (optional)
│   ├── logrotate.conf                  # Log rotation
│   └── fail2ban/                       # Brute-force protection
│       ├── jail.local
│       └── filter.d/
├── scripts/
│   ├── entrypoint.sh                   # Container init
│   ├── healthcheck.sh                  # Container health
│   ├── watchdog.sh                     # Service monitor + Telegram alerts
│   ├── backup.sh                       # Automated backups
│   ├── security-audit.sh              # Daily security checks
│   ├── crontab                         # All scheduled jobs
│   └── proactive/                      # Proactive assistant scripts
│       ├── morning-briefing.sh
│       ├── email-triage.sh
│       ├── calendar-reminders.sh
│       ├── news-digest.sh
│       ├── evening-recap.sh
│       ├── habit-checkin.sh
│       └── weekly-review.sh
└── workspace/                          # OpenClaw personality & config
    ├── AGENTS.md                       # Core rules
    ├── SOUL.md                         # Personality
    ├── MEMORY.md                       # Long-term memory
    ├── TOOLS.md                        # Environment reference
    ├── IDENTITY.md                     # Name and role
    ├── HEARTBEAT.md                    # Periodic checks
    ├── BOOT.md                         # Restart behavior
    └── BOOTSTRAP.md                    # First-run onboarding
```
