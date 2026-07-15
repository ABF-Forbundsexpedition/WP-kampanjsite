#!/bin/bash
# Kör backup för alla siter under /home/WP. Lägg i root:s crontab:
#   30 3 * * * /home/WP/WP-kampanjsite/backup-all.sh >> /var/log/wp-backup.log 2>&1

set -uo pipefail
BASE_DIR="${WP_BASE_DIR:-/home/WP}"
FAIL=0

for DIR in "$BASE_DIR"/*/; do
    [[ -f "$DIR/.env" && -f "$DIR/backup.sh" ]] || continue
    echo "=== $(date '+%Y-%m-%d %H:%M') $DIR"
    if ! bash "$DIR/backup.sh"; then
        echo "FEL: backup misslyckades för $DIR"
        FAIL=1
    fi
done

exit $FAIL
