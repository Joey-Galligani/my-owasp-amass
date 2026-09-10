#!/usr/bin/env bash
# Run any Amass v5 subcommand inside the compose stack.
#
#   ./amass.sh enum -d example.com -v
#   ./amass.sh subs -names -d example.com
#   ./amass.sh viz -d3 -d example.com
#   ./amass.sh track -d example.com -since 01/01/2026
#
# Output files land in ./output (mounted at /data inside the container), so
# pass relative paths: -oA report -> ./output/report.*
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [ ! -f .env ]; then
    echo "error: .env is missing. Run: cp .env.example .env  (then set the passwords)" >&2
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "usage: $(basename "$0") <assoc|enum|subs|track|viz> [options]" >&2
    exit 2
fi

ENGINE_URL="${AMASS_ENGINE_URL:-http://engine:4000}"
args=("$@")

# enum talks to the engine over HTTP and defaults to 127.0.0.1, which is wrong
# from inside the cli container. Point it at the engine service unless the
# caller already did.
if [ "$1" = "enum" ] && [[ " ${args[*]} " != *" -engine "* ]]; then
    args=("enum" "-engine" "$ENGINE_URL" "${@:2}")
fi

# --rm: the cli container is one-shot. depends_on brings up assetdb + engine
# and waits for their healthchecks.
exec docker compose run --rm cli "${args[@]}"
