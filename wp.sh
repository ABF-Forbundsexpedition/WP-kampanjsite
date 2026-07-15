#!/bin/bash
# Kör wp-cli mot den här siten, t.ex:
#   bash ./wp.sh plugin list
#   bash ./wp.sh user update admin --user_pass=nyttlösenord
#   bash ./wp.sh core update

set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

$DC --profile cli run --rm wpcli wp "$@"
