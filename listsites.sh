#!/bin/bash
# Visar alla siter under /home/WP med port och status.

set -uo pipefail
BASE_DIR="${WP_BASE_DIR:-/home/WP}"

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

printf '%-40s %-6s %-6s %-8s %s\n' 'DOMÄN' 'PORT' 'SFTP' 'VERSION' 'STATUS'
for DIR in "$BASE_DIR"/*/; do
    [[ -f "$DIR/.env" ]] || continue
    DOMAIN=$(grep '^DOMAIN=' "$DIR/.env" | cut -d= -f2)
    PORT=$(grep '^PORT=' "$DIR/.env" | cut -d= -f2)
    SFTP_PORT=$(grep '^SFTP_PORT=' "$DIR/.env" | cut -d= -f2)
    VERSION=$(cat "$DIR/VERSION" 2>/dev/null || echo '-')
    RUNNING=$(cd "$DIR" && $DC ps --services --status running 2>/dev/null | wc -l)
    if [[ "$RUNNING" -ge 3 ]]; then STATUS="kör ($RUNNING tjänster)"; else STATUS="NERE ($RUNNING tjänster)"; fi
    printf '%-40s %-6s %-6s %-8s %s\n' "$DOMAIN" "$PORT" "${SFTP_PORT:--}" "$VERSION" "$STATUS"
done
