#!/bin/bash

SOURCE_DIRS=(
    "$HOME/Documents"
    "$HOME/tech"
    "$HOME/play"
    "$HOME/Pictures"
    "$HOME/.local/bin"      # your custom scripts — likely what you meant
    # "/usr/bin"            # skip — system-managed, not worth backing up
)

REMOTE="megar:backups"
LOG_DIR="$HOME/.local/share/backup"
LOG="$LOG_DIR/backup.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

mkdir -p "$LOG_DIR"

echo "[$DATE] Backup started" >> "$LOG"

for dir in "${SOURCE_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        rclone sync "$dir" "$REMOTE/$(basename $dir)" \
            --exclude '.cache/**' \
            --exclude 'node_modules/**' \
            --exclude '*.tmp' \
            --log-file="$LOG" \
            --log-level INFO
    else
        echo "[$DATE] Skipping $dir (not found)" >> "$LOG"
    fi
done

echo "[$DATE] Backup finished" >> "$LOG"
