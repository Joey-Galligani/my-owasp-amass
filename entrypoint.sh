#!/bin/bash
# Copy the read-only config mount into the location Amass actually reads
# ($HOME/.config/amass), expanding the database placeholders on the way so the
# Postgres credentials live in .env instead of being hardcoded in config.yaml.
set -euo pipefail

CONFIG_SRC="${AMASS_CONFIG_SRC:-/config}"
CONFIG_DIR="/.config/amass"

: "${AMASS_DB_USER:=amass}"
: "${AMASS_DB_PASSWORD:=}"
: "${AMASS_DB_HOST:=assetdb}"
: "${AMASS_DB_PORT:=5432}"
: "${AMASS_DB_NAME:=assetdb}"
export AMASS_DB_USER AMASS_DB_PASSWORD AMASS_DB_HOST AMASS_DB_PORT AMASS_DB_NAME

if [ -d "$CONFIG_SRC" ]; then
    mkdir -p "$CONFIG_DIR"
    # Bring across everything (wordlists, extra lists) so the relative paths
    # inside config.yaml keep resolving.
    cp -R "$CONFIG_SRC"/. "$CONFIG_DIR"/
    chmod -R u+w "$CONFIG_DIR"

    for f in config.yaml datasources.yaml; do
        if [ -f "$CONFIG_SRC/$f" ]; then
            envsubst '${AMASS_DB_USER} ${AMASS_DB_PASSWORD} ${AMASS_DB_HOST} ${AMASS_DB_PORT} ${AMASS_DB_NAME}' \
                <"$CONFIG_SRC/$f" >"$CONFIG_DIR/$f"
        fi
    done
fi

exec /bin/amass "$@"
