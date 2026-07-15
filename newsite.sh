#!/bin/bash
# Skapar en ny WordPress-kampanjsite på servern.
#
#   sudo bash ./newsite.sh <domän> [e-post]
#
# - Klonar mallen till /home/WP/<domän>
# - Väljer nästa lediga port automatiskt
# - Genererar alla lösenord och WordPress-salter
# - Sätter upp nginx-vhost + Lets Encrypt-certifikat (setup.sh)
# - Om e-post anges: installerar WordPress direkt (svenska) och skapar admin
# - Skriver ut ett kontoblad och sparar det i <sitemapp>/site-info.txt
#
# Kräver: root, docker compose, nginx, certbot, openssl, git

set -euo pipefail

DOMAIN="${1:-}"
CERT_EMAIL="${2:-}"
BASE_DIR="${WP_BASE_DIR:-/home/WP}"
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$DOMAIN" ]]; then
    echo "Användning: $0 <domän> [e-post för certbot/wp-admin]" >&2
    exit 1
fi

if ! [[ "$DOMAIN" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; then
    echo "Ogiltig domän: $DOMAIN (använd gemener, t.ex. kampanj.abf.se)" >&2
    exit 1
fi

SITE_DIR="$BASE_DIR/$DOMAIN"
if [[ -e "$SITE_DIR" ]]; then
    echo "$SITE_DIR finns redan – ta bort siten först eller välj annan domän." >&2
    exit 1
fi

# Finns en nyare version av mallen på GitHub? Erbjud uppdatering innan
# siten skapas, så att den byggs från senaste versionen.
source "$TEMPLATE_DIR/checkversion.sh"
check_version "$TEMPLATE_DIR" "$@"

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

# ------------------------------------------------------------------
# Nästa lediga portpar: webb 8001+ (endast loopback) och
# sftp = webbport + 12000 (öppen utåt, t.ex. 8001 -> 20001).
# Portar tagna av andra siter (enligt deras .env) eller upptagna på
# värden hoppas över.
# ------------------------------------------------------------------
TAKEN_PORTS=$(grep -hsE '^(SFTP_)?PORT=' "$BASE_DIR"/*/.env 2>/dev/null | cut -d= -f2 || true)
LISTENING=$(ss -ltnH 2>/dev/null | awk '{print $4}' | grep -o '[0-9]*$' || true)

port_free() {
    ! grep -qx "$1" <<<"$TAKEN_PORTS" && ! grep -qx "$1" <<<"$LISTENING"
}

PORT=8001
while ! port_free "$PORT" || ! port_free "$((PORT + 12000))"; do
    PORT=$((PORT + 1))
    if [[ "$PORT" -gt 8999 ]]; then
        echo "Ingen ledig port i intervallet 8001-8999." >&2
        exit 1
    fi
done
SFTP_PORT=$((PORT + 12000))

rand() { openssl rand -base64 96 | tr -dc 'a-zA-Z0-9' | head -c "$1"; }

SFTP_PASSWORD=$(rand 20)

echo "Skapar $DOMAIN (webbport $PORT, sftp-port $SFTP_PORT) i $SITE_DIR ..."
git clone --quiet "$TEMPLATE_DIR" "$SITE_DIR"

cat > "$SITE_DIR/.env" <<EOF
DOMAIN=$DOMAIN
PORT=$PORT
SFTP_PORT=$SFTP_PORT
SFTP_USER=upload
SFTP_PASSWORD=$SFTP_PASSWORD
CERT_EMAIL=$CERT_EMAIL
MYSQL_ROOT_PASSWORD=$(rand 24)
MYSQL_PASSWORD=$(rand 24)
WP_AUTH_KEY=$(rand 64)
WP_SECURE_AUTH_KEY=$(rand 64)
WP_LOGGED_IN_KEY=$(rand 64)
WP_NONCE_KEY=$(rand 64)
WP_AUTH_SALT=$(rand 64)
WP_SECURE_AUTH_SALT=$(rand 64)
WP_LOGGED_IN_SALT=$(rand 64)
WP_NONCE_SALT=$(rand 64)
EOF
chmod 600 "$SITE_DIR/.env"

cd "$SITE_DIR"
bash ./setup.sh

# ------------------------------------------------------------------
# Installera WordPress med wp-cli om e-post angavs, annars får man
# köra installationsguiden i webbläsaren vid första besöket.
# ------------------------------------------------------------------
WP_ADMIN_INFO="WordPress-installationen görs i webbläsaren vid första besöket."
if [[ -n "$CERT_EMAIL" ]]; then
    echo "Väntar på att WordPress-filerna ska finnas på plats ..."
    for i in $(seq 1 30); do
        if $DC --profile cli run --rm wpcli wp core version >/dev/null 2>&1; then
            break
        fi
        sleep 2
    done

    WP_ADMIN_PASS=$(rand 16)
    $DC --profile cli run --rm wpcli wp core install \
        --url="https://$DOMAIN" \
        --title="$DOMAIN" \
        --admin_user=admin \
        --admin_password="$WP_ADMIN_PASS" \
        --admin_email="$CERT_EMAIL" \
        --skip-email
    $DC --profile cli run --rm wpcli wp language core install sv_SE --activate || true
    WP_ADMIN_INFO="WP-admin:   https://$DOMAIN/wp-admin
Användare:  admin
Lösenord:   $WP_ADMIN_PASS"
fi

cat > "$SITE_DIR/site-info.txt" <<EOF
==========================================================
 $DOMAIN
==========================================================
Webbplats:  https://$DOMAIN

$WP_ADMIN_INFO

SFTP (för filer: teman, plugins, uppladdningar):
  Server:     abf000webu2.abf.se
  Port:       $SFTP_PORT
  Användare:  upload
  Lösenord:   $SFTP_PASSWORD
  Mappen "www" är sitens wp-content.

Skapad: $(date '+%Y-%m-%d %H:%M')
==========================================================
EOF
chmod 600 "$SITE_DIR/site-info.txt"

echo
cat "$SITE_DIR/site-info.txt"
echo "Kontobladet är sparat i $SITE_DIR/site-info.txt"
