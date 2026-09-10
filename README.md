# OWASP Amass v5 — Dockerised

Attack surface mapping / asset discovery, running as a persistent collection
engine backed by Postgres (the OAM asset database).

## Why a custom image

Upstream publishes no v5 container image. `caffix/amass:latest` on Docker Hub is
still **v4.2.0 from September 2023**, and v4's single-binary `amass enum` model
no longer matches v5, which splits into an engine and clients. The `Dockerfile`
here builds the pinned release tag (`AMASS_VERSION` in `.env`, default
`v5.1.1`) from source.

## Layout

| Path | Purpose |
| --- | --- |
| `docker-compose.yml` | `assetdb` (Postgres) + `engine` (long-running) + `cli` (one-shot, profile `cli`) |
| `Dockerfile` | Builds Amass from the pinned upstream tag |
| `entrypoint.sh` | Renders `config/` into `$HOME/.config/amass`, expanding the DB placeholders |
| `postgres/` | Postgres image + `initdb-assetdb.sh` (creates the DB, role and required extensions) |
| `config/config.yaml` | Scope, transformation TTLs, wordlist and DB wiring |
| `config/datasources.yaml` | **API keys go here** (all entries commented out by default) |
| `config/wordlists/` | `namelist.txt`, `alterations.txt` (upstream defaults) |
| `amass.sh` | Wrapper — runs any subcommand in the stack |
| `output/` | Mounted at `/data`; `viz` report files land here |

## Setup

```bash
cp .env.example .env      # then set the two passwords
docker compose build
docker compose up -d      # assetdb + engine
docker compose ps         # both should read (healthy)
```

The engine API is published on `127.0.0.1:${ENGINE_HOST_PORT}` (default
`14000`, mapped to `4000` in the container). It has **no authentication**, so
keep it on loopback.

## Usage

```bash
# Collect. Results go into the database, not to a file.
./amass.sh enum -d example.com -v
./amass.sh enum -d example.com -active -brute      # active + brute forcing

# Read back what was collected.
./amass.sh subs -names -d example.com              # names to stdout
./amass.sh subs -show -ip -d example.com           # everything, with addresses
./amass.sh viz -d3 -d example.com                  # -> output/amass.html
./amass.sh track -d example.com -since "01/01 00:00:00 2026 UTC"
./amass.sh assoc -d example.com                    # walk org/contact associations

./amass.sh enum -h                                 # full flag list
```

`amass.sh` injects `-engine http://engine:4000` for `enum` unless you pass
`-engine` yourself. `subs`, `viz`, `track` and `assoc` read the asset database
directly and need no engine.

Gotchas found while testing v5.1.1:

- **`enum` writes no output files.** `-oA` is still accepted by the flag parser
  but is never used — everything lands in the asset database, and you read it
  back with `subs` / `viz` / `track`. Watch the progress bar, then query.
- `viz` writes into `/data`, i.e. `output/amass.html` (`-d3`), `amass.dot`
  (`-dot`), `amass.gexf` (`-gexf`). `-oA myprefix` renames them.
- `track -since` wants Go's reference layout `01/02 15:04:05 2006 MST`, so
  `"01/01 00:00:00 2026 UTC"`, not `01/01/2026`.
- `enum -list` still requires a domain (`-d`) — scope validation runs first.

## API keys

Uncomment the sources you have credentials for in `config/datasources.yaml`:

```yaml
datasources:
  - name: SecurityTrails
    ttl: 1440
    creds:
      account:
        apikey: your-key-here
```

Then `docker compose restart engine` — the config is copied in at container
start, so a restart is required for changes to take effect. `ttl` is in minutes
and controls how long a source's answers are reused before re-querying.

## Scope

Per-run scope goes on the command line (`-d`, `-cidr`, `-asn`, `-addr`, `-bl`).
For a standing engagement scope, fill in the `scope:` block in
`config/config.yaml` and restart the engine.

## Persistence

Collected assets live in the `assetdb-data` volume and accumulate across runs —
that is what makes `track` and repeat scans worthwhile.

```bash
docker compose down          # stop, keep the data
docker compose down -v       # stop and DESTROY all collected assets
```

The DB credentials are baked into the volume on first boot. Changing
`AMASS_DB_*` in `.env` afterwards requires `down -v` (data loss) or altering the
role by hand.

Inspect the database directly:

```bash
docker compose exec assetdb psql -U amass -d assetdb -c '\dt'

# what has been collected, by asset type
docker compose exec assetdb psql -U amass -d assetdb -c \
  "select t.name, count(*) from entity e
     join entity_type_lu t on t.id = e.etype_id
   group by 1 order by 2 desc;"
```

Assets are stored as a graph: `entity` / `edge` are the generic rows, with the
per-type detail in `fqdn`, `ipaddress`, `organization`, `contactrecord`, and so
on. `entity_type_lu` maps `etype_id` to a type name.

## Notes

- Amass v5 has no `-passive` flag any more: passive is the default. `-active`
  opts into zone transfers and certificate grabs; `-brute` into DNS brute
  forcing (wordlist from `config/config.yaml`).
- The Postgres schema is created by the engine at startup, from migrations
  embedded in the `asset-db` library — `initdb-assetdb.sh` only sets up the
  database, role and `citext` / `pg_trgm` / `btree_gin` extensions.
- Street addresses found in WHOIS/RDAP records are only parsed if a libpostal
  server is reachable (`POSTAL_SERVER_HOST` / `POSTAL_SERVER_PORT`). Without
  one, that enrichment is skipped silently.
- Only enumerate targets you are authorised to test. `-active` and `-brute`
  send traffic to the target.

## Upgrading

```bash
# bump AMASS_VERSION in .env, then:
docker compose build --no-cache engine
docker compose up -d
```

## Verified

Built and run end to end on this machine (OrbStack, darwin/arm64):

| Check | Result |
| --- | --- |
| `docker compose build` | `exposure-rh/amass:v5.1.1`, `exposure-rh/amass-assetdb:17-alpine` |
| `docker compose up -d` | `assetdb` healthy, `engine` healthy |
| Schema migrations | 27 tables created by the engine in `assetdb` |
| `./amass.sh enum -d example.com -v` | exit 0, 907 entities stored (168 FQDN, 144 IP, 65 org, …) |
| `./amass.sh subs -names -d example.com` | `example.com`, `www.example.com` |
| `./amass.sh viz -d3 -d example.com` | `output/amass.html` |
| `./amass.sh track -d example.com -since "01/01 00:00:00 2026 UTC"` | both names returned |
