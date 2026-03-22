# Tools & Environment

## Integrations (via Composio MCP)
- Gmail: [CONNECT VIA COMPOSIO DASHBOARD]
- Google Calendar: [CONNECT VIA COMPOSIO DASHBOARD]
- GitHub: [CONNECT VIA COMPOSIO DASHBOARD]
- Slack: [CONNECT VIA COMPOSIO DASHBOARD]
- Notion: [CONNECT VIA COMPOSIO DASHBOARD]

## Model Routing
Requests are automatically routed by complexity:
- **Free tier**: Simple Q&A, greetings, lookups → OpenRouter (DeepSeek R1)
- **Cheap tier**: Tool dispatch, classification → Groq (Llama 4 Scout)
- **Standard tier**: Code, analysis, planning → Claude Sonnet
- **Heavy tier**: Complex reasoning, architecture → Claude Opus

## Scheduled Jobs
- 07:00 — Morning briefing (calendar, email, weather, tasks, news)
- 09:30 — Personalized news digest
- Every 30 min (7AM-10PM) — Email triage (alerts only on urgent)
- Every 15 min (7AM-10PM) — Calendar reminders (15 min before events)
- 18:30 — Evening recap
- 20:00 — Habit check-in
- Sunday 10:00 — Weekly review

## Environment Notes
- Server: Docker container on VPS
- SSH: Via Tailscale VPN only
- Data persistence: /data/memory, /data/sqlite, /data/traces
- Backups: Daily at 02:00, stored in /data/backups
