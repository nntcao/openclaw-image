# Heartbeat

<!-- This file is read every 30 minutes. Use it for periodic maintenance tasks. -->

## Every Heartbeat
1. Check if there are any pending reminders or time-sensitive tasks.
2. If there are unread urgent emails (from the last triage), re-alert if no response.
3. Check system health — if any service is down, note it in today's daily log.

## Quiet Hours
- Between 22:00 and 07:00 (operator timezone), do NOT send proactive messages.
- Queue any non-urgent alerts for the morning briefing instead.
- Urgent alerts (service down, security issue) bypass quiet hours.
