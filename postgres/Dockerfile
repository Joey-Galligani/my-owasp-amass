ARG POSTGRES_VERSION=17-alpine
FROM postgres:${POSTGRES_VERSION}

COPY initdb-assetdb.sh /docker-entrypoint-initdb.d/1_assetdb.sh
RUN chmod +x /docker-entrypoint-initdb.d/1_assetdb.sh

STOPSIGNAL SIGINT
EXPOSE 5432
