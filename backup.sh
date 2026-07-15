#!/bin/bash
# Backup av den här siten: databas-dump + wp-content.
# Sparas i /home/WP/backups/<domän>/ (ändra med BACKUP_ROOT).
# Backuper äldre än 14 dagar rensas (ändra med BACKUP_KEEP_DAYS).

set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source .env

BACKUP_ROOT="${BACKUP_ROOT:-/home/WP/backups}"
KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"
DEST="$BACKUP_ROOT/$DOMAIN"
STAMP=$(date +%Y%m%d-%H%M%S)

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

mkdir -p "$DEST"

$DC exec -T db sh -c 'exec mariadb-dump --single-transaction -uroot -p"$MARIADB_ROOT_PASSWORD" wordpress' \
    | gzip > "$DEST/db-$STAMP.sql.gz"

tar -czf "$DEST/wp-content-$STAMP.tar.gz" wp-content

find "$DEST" -type f -name '*.gz' -mtime "+$KEEP_DAYS" -delete

echo "Backup klar: $DEST (db-$STAMP.sql.gz, wp-content-$STAMP.tar.gz)"
