#!/bin/sh

# OpenWRT Backup Script - for direct router execution
# ===================== CONFIGURATION =====================
# Configure for your router and Yandex disk

# rclone settings
RCLONE_SERVICE=""                    # Your rclone service name
YANDEX_PATH=""                # Path on Yandex Disk

# Telegram settings (optional)
TELEGRAM_BOT_TOKEN=""                      # Bot token (leave empty to disable)
TELEGRAM_CHAT_ID=""                        # Chat ID

# ===================== FUNCTIONS =====================

send_telegram_success() {
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        MESSAGE="✅ *OpenWRT Backup Completed*

📁 *File:* $(basename "$BACKUP_FILE")
📍 *Location:* $RCLONE_SERVICE:$YANDEX_PATH/$(basename "$BACKUP_FILE")
🕐 *Time:* $(date '+%Y-%m-%d %H:%M:%S')"

        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            -d chat_id="$TELEGRAM_CHAT_ID" \
            -d text="$MESSAGE" \
            -d parse_mode="Markdown" >/dev/null
    fi
}

send_telegram_error() {
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        ERROR_MESSAGE="❌ *OpenWRT Backup Failed*

🚫 *Error:* $1
🕐 *Time:* $(date '+%Y-%m-%d %H:%M:%S')"

        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            -d chat_id="$TELEGRAM_CHAT_ID" \
            -d text="$ERROR_MESSAGE" \
            -d parse_mode="Markdown" >/dev/null
    fi
}

# ===================== SCRIPT =====================

# Check if rclone is installed

if ! command -v rclone >/dev/null 2>&1; then
    exit 1
fi

# Check rclone settings
if [ -z "$RCLONE_SERVICE" ] || [ -z "$YANDEX_PATH" ]; then
    exit 1
fi

# Create directory for temporary files
TEMP_DIR="/tmp/openwrt_backup"
mkdir -p "$TEMP_DIR"

# Create backup
umask go=
sysupgrade -b "$TEMP_DIR/router-backup-$(date +%F-%H%M).tar.gz"

if [ $? -ne 0 ]; then
    send_telegram_error "Failed to create backup"
    exit 1
fi

# Get filename
BACKUP_FILE=$(ls -t "$TEMP_DIR"/router-backup-*.tar.gz 2>/dev/null | head -n 1)

if [ -z "$BACKUP_FILE" ]; then
    send_telegram_error "Backup file not found"
    exit 1
fi

# Upload to Yandex disk first
if rclone copy "$BACKUP_FILE" "$RCLONE_SERVICE:$YANDEX_PATH/" 2>/dev/null; then
    # Then delete old backups (keep only last 3)
    # Get file list, sort by time and delete old ones
    rclone ls "$RCLONE_SERVICE:$YANDEX_PATH/" 2>/dev/null | \
        awk '{print $2}' | sort -r | tail -n +4 | \
        while read -r old_file; do
            [ -n "$old_file" ] && rclone delete "$RCLONE_SERVICE:$YANDEX_PATH/$old_file" 2>/dev/null || true
        done
fi

# Upload to Yandex disk
if rclone copy "$BACKUP_FILE" "$RCLONE_SERVICE:$YANDEX_PATH/" 2>/dev/null; then
    # Delete old backups (keep only last 3)
    # Get file list, sort by time and delete old ones
    rclone ls "$RCLONE_SERVICE:$YANDEX_PATH/" 2>/dev/null |
        awk '{print $2}' | sort -r | tail -n +4 |
        while read -r old_file; do
            [ -n "$old_file" ] && rclone delete "$RCLONE_SERVICE:$YANDEX_PATH/$old_file" 2>/dev/null || true
        done

    # Remove local file
    rm -f "$BACKUP_FILE"

    # Clean up temporary folder
    rm -rf "$TEMP_DIR"

    # Send success notification
    send_telegram_success

    exit 0
else
    # Remove file even on error to prevent /tmp clutter
    rm -f "$BACKUP_FILE"
    rm -rf "$TEMP_DIR"

    send_telegram_error "Failed to upload backup"
    exit 1
fi
