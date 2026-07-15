#!/bin/bash
# Sourcas av newsite.sh och setup.sh – inte tänkt att köras direkt.
#
# Jämför lokal VERSION med origin och erbjuder uppdatering innan
# skriptet fortsätter. För mallen (/home/WP/WP-kampanjsite) är origin
# GitHub; för en site är origin den lokala mallen.
#
# Anrop: check_version <repokatalog> "$@"   (skriptets originalargument
# skickas med så att skriptet kan startas om efter uppdatering)

check_version() {
    local dir="$1"
    shift
    local local_v remote_v head_ref svar

    local_v=$(cat "$dir/VERSION" 2>/dev/null || echo "okänd")

    if ! git -C "$dir" fetch --quiet origin 2>/dev/null; then
        echo "OBS: kunde inte nå origin för versionskontroll – fortsätter med version $local_v."
        return 0
    fi

    head_ref=$(git -C "$dir" rev-parse --abbrev-ref origin/HEAD 2>/dev/null || echo "origin/main")
    remote_v=$(git -C "$dir" show "$head_ref:VERSION" 2>/dev/null || echo "")

    if [[ -z "$remote_v" || "$remote_v" == "$local_v" ]]; then
        return 0
    fi

    echo "Nyare version finns: $remote_v (installerad här: $local_v)"
    if [[ ! -t 0 ]]; then
        echo "OBS: icke-interaktiv körning – uppdaterar inte automatiskt. Kör 'git pull' manuellt."
        return 0
    fi

    read -rp "Uppdatera till $remote_v innan vi fortsätter? [J/n] " svar
    if [[ "$svar" =~ ^[Nn] ]]; then
        echo "Fortsätter med version $local_v."
        return 0
    fi

    if ! git -C "$dir" pull --ff-only --quiet origin; then
        echo "Uppdateringen misslyckades (lokala ändringar?). Åtgärda i $dir och försök igen." >&2
        exit 1
    fi
    echo "Uppdaterad till $(cat "$dir/VERSION"). Startar om skriptet ..."
    exec bash "$0" "$@"
}
