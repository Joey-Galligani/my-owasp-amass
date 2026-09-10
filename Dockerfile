# OWASP Amass v5 - multi-stage build from source.
#
# Upstream publishes no v5 container image (caffix/amass:latest is still v4.2.0
# from 2023), so we build the release tag ourselves.
ARG GO_VERSION=1.26.0
ARG ALPINE_VERSION=3.22

FROM golang:${GO_VERSION}-alpine AS build
ARG AMASS_VERSION=v5.1.1
RUN apk --no-cache add git
WORKDIR /src
RUN git clone --depth 1 --branch "${AMASS_VERSION}" \
        https://github.com/owasp-amass/amass.git .
# CGO off: the sqlite driver in use (modernc.org/sqlite) is pure Go.
RUN CGO_ENABLED=0 go install -v ./...

FROM alpine:${ALPINE_VERSION}
ARG AMASS_VERSION=v5.1.1
LABEL org.opencontainers.image.title="amass" \
      org.opencontainers.image.description="OWASP Amass - attack surface mapping and asset discovery" \
      org.opencontainers.image.source="https://github.com/owasp-amass/amass" \
      org.opencontainers.image.version="${AMASS_VERSION}"

# gettext provides envsubst, used by the entrypoint to render the config files.
RUN apk --no-cache add bash ca-certificates gettext tzdata \
    && apk --no-cache --update upgrade

COPY --from=build /go/bin/amass        /bin/amass
COPY --from=build /go/bin/amass_engine /bin/engine
COPY --from=build /go/bin/ae_isready   /bin/ae_isready
COPY --from=build /go/bin/oam_enum     /bin/enum
COPY --from=build /go/bin/oam_subs     /bin/subs
COPY --from=build /go/bin/oam_assoc    /bin/assoc
COPY --from=build /go/bin/oam_viz      /bin/viz
COPY --from=build /go/bin/oam_track    /bin/track
COPY --from=build /go/bin/oam_i2y      /bin/i2y
COPY entrypoint.sh /bin/amass-entrypoint

# Amass resolves its config through os.UserConfigDir() -> $HOME/.config/amass.
ENV HOME=/
RUN chmod +x /bin/amass-entrypoint \
    && addgroup amass \
    && adduser amass -D -G amass \
    && mkdir -p /.config/amass /data \
    && chown -R amass:amass /.config /data

USER amass
WORKDIR /data
EXPOSE 4000
STOPSIGNAL SIGINT
ENTRYPOINT ["/bin/amass-entrypoint"]
CMD ["engine"]
