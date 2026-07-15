#!/bin/bash
# Genererar och startar den delade SFTP-tjänsten (/home/WP/sftp) utifrån
# alla siters .env. En chrootad användare per site, allt på en port (2222).
# Körs automatiskt av newsite.sh och removesite.sh – kan även köras manuellt.
# Idempotent: innehållet byggs alltid om från nuvarande siter.

set -euo pipefail
BASE_DIR="${WP_BASE_DIR:-/home/WP}"
SFTP_DIR="$BASE_DIR/sftp"
SFTP_PORT="${SFTP_PORT:-2222}"

mkdir -p "$SFTP_DIR/ssh"

# Delade värdnycklar – genereras en gång och behålls så att användarnas
# sftp-klienter aldrig varnar om ny nyckel.
[[ -f "$SFTP_DIR/ssh/ssh_host_ed25519_key" ]] || ssh-keygen -t ed25519 -N '' -q -f "$SFTP_DIR/ssh/ssh_host_ed25519_key"
[[ -f "$SFTP_DIR/ssh/ssh_host_rsa_key" ]] || ssh-keygen -t rsa -b 4096 -N '' -q -f "$SFTP_DIR/ssh/ssh_host_rsa_key"
chmod 600 "$SFTP_DIR/ssh/ssh_host_ed25519_key" "$SFTP_DIR/ssh/ssh_host_rsa_key"

# users.conf + volymmontering per site, byggs om från siternas .env
USERS_TMP=$(mktemp)
COMPOSE_TMP=$(mktemp)

cat > "$COMPOSE_TMP" <<EOF
# Genereras av sftp-sync.sh - redigera inte för hand.
services:
  sftp:
    image: atmoz/sftp:alpine
    restart: unless-stopped
    ports:
      - '${SFTP_PORT}:22'
    volumes:
      - ./users.conf:/etc/sftp/users.conf:ro
      - ./ssh/ssh_host_ed25519_key:/etc/ssh/ssh_host_ed25519_key:ro
      - ./ssh/ssh_host_rsa_key:/etc/ssh/ssh_host_rsa_key:ro
EOF

ANTAL=0
for ENV_FILE in "$BASE_DIR"/*/.env; do
    [[ -f "$ENV_FILE" ]] || continue
    SITE_DIR=$(dirname "$ENV_FILE")
    # || true: siter utan SFTP-uppgifter (t.ex. äldre siter) hoppas över
    SFTP_USER=$(grep -s '^SFTP_USER=' "$ENV_FILE" | cut -d= -f2 || true)
    SFTP_PASSWORD=$(grep -s '^SFTP_PASSWORD=' "$ENV_FILE" | cut -d= -f2 || true)
    [[ -n "$SFTP_USER" && -n "$SFTP_PASSWORD" ]] || continue
    # Vilken katalog användaren ser som "www". Standard är wp-content i
    # sitemappen; siter med annan struktur (t.ex. Bedrock) kan sätta
    # SFTP_CONTENT_DIR i .env - absolut sökväg eller relativt sitemappen.
    SFTP_CONTENT_DIR=$(grep -s '^SFTP_CONTENT_DIR=' "$ENV_FILE" | cut -d= -f2- || true)
    SFTP_CONTENT_DIR="${SFTP_CONTENT_DIR:-wp-content}"
    case "$SFTP_CONTENT_DIR" in
        /*) CONTENT_PATH="$SFTP_CONTENT_DIR" ;;
        *)  CONTENT_PATH="$SITE_DIR/$SFTP_CONTENT_DIR" ;;
    esac
    echo "$SFTP_USER:$SFTP_PASSWORD:33:33" >> "$USERS_TMP"
    echo "      - $CONTENT_PATH:/home/$SFTP_USER/www" >> "$COMPOSE_TMP"
    ANTAL=$((ANTAL + 1))
done

install -m 600 "$USERS_TMP" "$SFTP_DIR/users.conf"
install -m 644 "$COMPOSE_TMP" "$SFTP_DIR/docker-compose.yml"
rm -f "$USERS_TMP" "$COMPOSE_TMP"

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

cd "$SFTP_DIR"
if [[ "$ANTAL" -eq 0 ]]; then
    echo "Inga sftp-användare – stoppar delade sftp-tjänsten."
    $DC down 2>/dev/null || true
else
    # up -d startar bara om containern om konfigurationen ändrats
    $DC up -d
    echo "SFTP synkad: $ANTAL användare på port $SFTP_PORT."
fi
