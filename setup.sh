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

# Standardserver: anrop utan känt Host-header (serverns IP, okända
# domäner) skickas med tillfällig redirect till www.abf.se i stället
# för att hamna på första bästa site. Ersätter Ubuntus default-site.
if [[ ! -f /etc/nginx/sites-available/000-catchall.conf ]]; then
    if [[ ! -f /etc/ssl/certs/nginx-default.pem ]]; then
        # Självsignerat cert enbart för catch-all på 443 (nginx kräver
        # ett cert även för att kunna svara med redirect)
        openssl req -x509 -nodes -newkey rsa:2048 \
            -keyout /etc/ssl/private/nginx-default.key \
            -out /etc/ssl/certs/nginx-default.pem \
            -days 3650 -subj "/CN=default" 2>/dev/null
        chmod 600 /etc/ssl/private/nginx-default.key
    fi
    cat > /etc/nginx/sites-available/000-catchall.conf <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 302 https://www.abf.se;
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;
    ssl_certificate     /etc/ssl/certs/nginx-default.pem;
    ssl_certificate_key /etc/ssl/private/nginx-default.key;
    return 302 https://www.abf.se;
}
EOF
    ln -sf ../sites-available/000-catchall.conf /etc/nginx/sites-enabled/000-catchall.conf
    rm -f /etc/nginx/sites-enabled/default
fi

# Nattlig backup av alla siter (en gång per server)
if [[ ! -f /etc/cron.d/wp-backup ]]; then
    echo '30 3 * * * root bash /home/WP/WP-kampanjsite/backup-all.sh >> /var/log/wp-backup.log 2>&1' \
        > /etc/cron.d/wp-backup
    chmod 644 /etc/cron.d/wp-backup
fi

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
