#!/bin/bash
set -euo pipefail

HOSTNAME="${1:-}"
DATE_FILTER="${2:-}"

if [[ -z "$HOSTNAME" ]]; then
    echo "Usage: $0 <hostname> [date-filter]"
    echo "  date-filter: optional, e.g., '2025-01-02' to restore from specific date"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_BASE="$PROJECT_ROOT/backups/$HOSTNAME"

if [[ ! -d "$BACKUP_BASE" ]]; then
    echo "No backups found for $HOSTNAME at $BACKUP_BASE"
    exit 1
fi

# Find the backup directory to use
if [[ -n "$DATE_FILTER" ]]; then
    BACKUP_DIR="$BACKUP_BASE/$DATE_FILTER"
    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo "No backups found for date $DATE_FILTER"
        echo "Available dates:"
        ls -1 "$BACKUP_BASE"
        exit 1
    fi
else
    # Use most recent backup
    BACKUP_DIR=$(ls -1d "$BACKUP_BASE"/*/ 2>/dev/null | sort -r | head -1)
    if [[ -z "$BACKUP_DIR" ]]; then
        echo "No backup directories found in $BACKUP_BASE"
        exit 1
    fi
fi

# Get SSH host and user from Ansible inventory (JSON format)
SSH_HOST=$(ansible-inventory --host "$HOSTNAME" 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('ansible_ssh_host', ''))")
if [[ -z "$SSH_HOST" ]]; then
    SSH_HOST="$HOSTNAME"
fi

SSH_USER=$(ansible-inventory --host "$HOSTNAME" 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('ansible_user', 'njl'))")

echo "Restoring backups from $BACKUP_DIR to $HOSTNAME ($SSH_USER@$SSH_HOST)..."

# Copy each backup file to remote /tmp
for backup_file in "$BACKUP_DIR"/*.tar.gz; do
    if [[ -f "$backup_file" ]]; then
        filename=$(basename "$backup_file")
        echo "  Restoring $filename..."
        scp "$backup_file" "$SSH_USER@$SSH_HOST:/tmp/"
    fi
done

echo "Backups restored to /tmp on $HOSTNAME"
ssh "$SSH_USER@$SSH_HOST" "ls -lh /tmp/*_backup_*.tar.gz 2>/dev/null | tail -5" || echo "No backup files found"
