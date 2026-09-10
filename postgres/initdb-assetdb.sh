#!/bin/bash
# Provision the OAM asset database and its role. Runs once, on first start of
# an empty data volume. Adapted from owasp-amass/asset-db.
#
# The schema itself is not created here: the Amass engine applies the migrations
# embedded in the asset-db library on startup, which is why the role needs
# CREATE on the public schema.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'EOSQL'
\getenv dbname AMASS_DB
\getenv username AMASS_USER
\getenv password AMASS_PASSWORD

CREATE DATABASE :"dbname";
ALTER DATABASE :"dbname" SET timezone TO 'UTC';

CREATE USER :"username" WITH PASSWORD :'password';
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$AMASS_DB" <<'EOSQL'
\getenv username AMASS_USER

CREATE EXTENSION IF NOT EXISTS citext    WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pg_trgm   WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS btree_gin WITH SCHEMA public;

GRANT USAGE, CREATE ON SCHEMA public TO :"username";
GRANT ALL ON ALL TABLES IN SCHEMA public TO :"username";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO :"username";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO :"username";
EOSQL
