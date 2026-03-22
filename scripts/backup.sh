#!/usr/bin/env bash
# Automated Backup - snapshots memory, config, and state
# Supports local rotation and optional remote sync (rclone)

set -euo pipefail

LOG="/var/log/openclaw/backup.log"
BACKUP_DIR="/data/backups"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="openclaw-backup-${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

echo "[$(date -Iseconds)] Starting backup: $BACKUP_NAME" >> "$LOG"

mkdir -p "$BACKUP_PATH"

# Backup memory
cp -r /data/memory "$BACKUP_PATH/memory" 2>/dev/null || true

# Backup SQLite databases (with proper locking)
mkdir -p "$BACKUP_PATH/sqlite"
for db in /data/sqlite/*.db; do
    if [ -f "$db" ]; then
        sqlite3 "$db" ".backup '$BACKUP_PATH/sqlite/$(basename "$db")'" 2>> "$LOG" || \
            cp "$db" "$BACKUP_PATH/sqlite/" 2>> "$LOG" || true
    fi
done

# Backup config
cp -r /home/openclaw/.openclaw "$BACKUP_PATH/config" 2>/dev/null || true
# Remove any secrets from the backup config
find "$BACKUP_PATH/config" -name "*.json" -exec sed -i \
    -e 's/"sk-[^"]*"/"REDACTED"/g' \
    -e 's/"ghp_[^"]*"/"REDACTED"/g' \
    -e 's/"xoxb-[^"]*"/"REDACTED"/g' \
    -e 's/"xoxp-[^"]*"/"REDACTED"/g' \
    -e 's/"gho_[^"]*"/"REDACTED"/g' \
    -e 's/"[0-9]\{6,\}:[A-Za-z0-9_-]\{35\}"/"REDACTED"/g' \
    {} \; 2>/dev/null || true

# Backup cron jobs
cp /etc/cron.d/openclaw-cron "$BACKUP_PATH/crontab" 2>/dev/null || true

# Backup Foundry-generated tools
if [ -d /data/memory/foundry-tools ]; then
    cp -r /data/memory/foundry-tools "$BACKUP_PATH/foundry-tools" 2>/dev/null || true
fi

# Create tarball
cd "$BACKUP_DIR"
tar czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME" 2>> "$LOG"
rm -rf "$BACKUP_PATH"

BACKUP_SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" | cut -f1)
echo "[$(date -Iseconds)] Backup complete: ${BACKUP_NAME}.tar.gz ($BACKUP_SIZE)" >> "$LOG"

# Rotate old backups
DELETED=0
find "$BACKUP_DIR" -name "openclaw-backup-*.tar.gz" -mtime +${RETENTION_DAYS} -exec rm -f {} \; -exec echo "Deleted: {}" >> "$LOG" \;
REMAINING=$(find "$BACKUP_DIR" -name "openclaw-backup-*.tar.gz" | wc -l)
echo "[$(date -Iseconds)] Backups retained: $REMAINING (${RETENTION_DAYS}-day retention)" >> "$LOG"

# Optional: sync to remote via rclone
if [ -n "${BACKUP_REMOTE:-}" ] && command -v rclone &> /dev/null; then
    echo "[$(date -Iseconds)] Syncing to remote: $BACKUP_REMOTE" >> "$LOG"
    rclone copy "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" "$BACKUP_REMOTE" >> "$LOG" 2>&1 || \
        echo "[$(date -Iseconds)] WARNING: Remote sync failed" >> "$LOG"
fi

# Notify via Telegram
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_ALLOWED_USERS:-}" ] && [ "${BACKUP_NOTIFY:-false}" = "true" ]; then
    IFS=',' read -ra USERS <<< "$TELEGRAM_ALLOWED_USERS"
    for user_id in "${USERS[@]}"; do
        user_id=$(echo "$user_id" | xargs)
        curl -sf -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="$user_id" \
            -d text="✅ Backup complete: ${BACKUP_NAME}.tar.gz ($BACKUP_SIZE) — $REMAINING backups retained" \
            > /dev/null 2>&1 || true
    done
fi
