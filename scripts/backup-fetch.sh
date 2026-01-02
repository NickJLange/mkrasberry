#!/bin/bash
set -euo pipefail

HOSTNAME="${1:-}"

if [[ -z "$HOSTNAME" ]]; then
    echo "Usage: $0 <hostname>"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DATE_DIR="$(date +%Y-%m-%d)"
BACKUP_DIR="$PROJECT_ROOT/backups/$HOSTNAME/$DATE_DIR"

# Get SSH host from Ansible inventory (JSON format)
SSH_HOST=$(ansible-inventory --host "$HOSTNAME" 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('ansible_ssh_host', ''))")
if [[ -z "$SSH_HOST" ]]; then
    SSH_HOST="$HOSTNAME"
fi

SSH_USER=$(ansible-inventory --host "$HOSTNAME" 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('ansible_user', 'njl'))")

echo "Fetching backups from $HOSTNAME ($SSH_USER@$SSH_HOST)..."

# List available backup files (now looking for .tar instead of .tar.gz)
BACKUP_FILES=$(ssh "$SSH_USER@$SSH_HOST" "ls -1 /tmp/*_backup_${HOSTNAME}_*.tar 2>/dev/null" || true)

if [[ -z "$BACKUP_FILES" ]]; then
    echo "No backup files found in /tmp on $HOSTNAME"
    exit 0
fi

# Create local backup directory
mkdir -p "$BACKUP_DIR"

# Fetch each backup file and gzip locally
echo "$BACKUP_FILES" | while read -r remote_file; do
    filename=$(basename "$remote_file")
    echo "  Fetching $filename..."
    scp "$SSH_USER@$SSH_HOST:$remote_file" "$BACKUP_DIR/"
    
    # Gzip the file locally (faster compression on local machine)
    echo "  Compressing $filename..."
    gzip "$BACKUP_DIR/$filename"
done

echo "Backups saved to: $BACKUP_DIR"
ls -lh "$BACKUP_DIR"
