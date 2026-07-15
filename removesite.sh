#!/bin/bash
# Tar bort en site: sista backup, containrar + volymer, nginx-vhost
# och TLS-certifikat. Sitemappen lämnas kvar tills du själv raderar
# den, så att du hinner kontrollera backupen.
#
#   sudo bash ./removesite.sh        (frågar om bekräftelse)
#   sudo bash ./removesite.sh -f     (ingen fråga, för skript)

set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source .env

if [[ "${1:-}" != "-f" ]]; then
    read -rp "Ta bort $DOMAIN permanent? Skriv domännamnet för att bekräfta: " SVAR
    if [[ "$SVAR" != "$DOMAIN" ]]; then
        echo "Avbrutet."
        exit 1
    fi
fi

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

echo "Tar en sista backup ..."
bash ./backup.sh || echo "VARNING: backupen misslyckades – fortsätter ändå."

# Endast den här sitens containrar och volymer – aldrig docker prune,
# det raderar data som tillhör andra siter på servern!
$DC --profile cli down --volumes --remove-orphans

rm -f "/etc/nginx/sites-enabled/$DOMAIN.conf" "/etc/nginx/sites-available/$DOMAIN.conf"
nginx -t && nginx -s reload

certbot delete --cert-name "$DOMAIN" --non-interactive || \
    echo "VARNING: kunde inte ta bort certifikatet för $DOMAIN."

echo
echo "Siten $DOMAIN är borttagen."
echo "Backup finns i ${BACKUP_ROOT:-/home/WP/backups}/$DOMAIN"
echo "Radera mappen när du kontrollerat backupen:  rm -rf $(pwd)"
