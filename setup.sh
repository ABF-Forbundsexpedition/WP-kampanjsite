#!/bin/bash
# Sätter upp nginx-vhost, TLS-certifikat och startar sitens containrar.
# Körs normalt av newsite.sh men kan köras igen manuellt – idempotent.
# Kräver: root, en ifylld .env i samma mapp.

set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f .env ]]; then
    echo ".env saknas – skapa siten med newsite.sh." >&2
    exit 1
fi
source .env

# Finns en nyare version av mallen? Erbjud uppdatering innan setup körs
# (vid körning direkt efter newsite.sh är versionerna alltid lika).
source ./checkversion.sh
check_version "$(pwd)" "$@"

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

# wp-content måste ägas av www-data (uid 33) i containern
mkdir -p wp-content
chown 33:33 wp-content

# ------------------------------------------------------------------
# Delade nginx-filer (samma för alla siter, skrivs om vid behov)
# ------------------------------------------------------------------
if [[ ! -f /etc/nginx/conf.d/wp-kampanjsite-ratelimit.conf ]]; then
    cat > /etc/nginx/conf.d/wp-kampanjsite-ratelimit.conf <<'EOF'
# Bromsar lösenordsgissning mot wp-login.php (delas av alla kampanjsiter)
limit_req_zone $binary_remote_addr zone=wplogin:10m rate=10r/m;
limit_req_status 429;
EOF
fi

mkdir -p /etc/nginx/snippets
cat > /etc/nginx/snippets/wp-kampanjsite-proxy.conf <<'EOF'
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Host $server_name;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header Host $host;
proxy_redirect off;
proxy_read_timeout 300s;
EOF

# ------------------------------------------------------------------
# Vhost för den här siten
# ------------------------------------------------------------------
sed -e "s/<sitename>/$DOMAIN/g" -e "s/<port>/$PORT/g" nginx.conf \
    > "/etc/nginx/sites-available/$DOMAIN.conf"
ln -sf "../sites-available/$DOMAIN.conf" "/etc/nginx/sites-enabled/$DOMAIN.conf"
nginx -t
nginx -s reload

# ------------------------------------------------------------------
# TLS-certifikat. --redirect ger automatisk http->https.
# Utan CERT_EMAIL återanvänds befintligt certbot-konto på servern.
# ------------------------------------------------------------------
CERTBOT_ARGS=(--nginx -d "$DOMAIN" --non-interactive --agree-tos --redirect)
if [[ -n "${CERT_EMAIL:-}" ]]; then
    CERTBOT_ARGS+=(-m "$CERT_EMAIL")
fi
certbot "${CERTBOT_ARGS[@]}"
nginx -s reload

$DC up -d
echo "Klart: https://$DOMAIN (lokal port $PORT)"
