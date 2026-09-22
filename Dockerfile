# SWARM explorer — production release image.
#
# Two stages: a builder with Elixir, Node and the full source, and a runtime
# that carries only the OTP release. Nothing is configured at build time; every
# knob is an environment variable, documented in README-SWARM.md.
#
#   docker build -t swarm-explorer .
#   docker run --rm -p 4000:4000 \
#     -e SECRET_KEY_BASE=... -e SESSION_SIGNING_SALT=... \
#     -e LIVE_VIEW_SIGNING_SALT=... -e EXPLORER_HOSTNAME=explore.swarm.green \
#     -e ZEBRA_RPC_URL=http://zebra:18232 -e ZEBRA_COOKIE_PATH=/zebra/.cookie \
#     -v zebra-cookie:/zebra:ro swarm-explorer

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
FROM elixir:1.18.3-otp-27-alpine AS build

# build-base and git are needed for native deps and the git-sourced zcashex;
# nodejs/npm build the CSS and JS bundle.
RUN apk add --update --no-cache build-base git nodejs npm

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
COPY config config
RUN mix do deps.get --only prod, deps.compile

COPY assets/package.json assets/package-lock.json* ./assets/
RUN npm install --prefix=assets --no-audit --no-fund

COPY lib lib
COPY rel rel
COPY priv priv
COPY assets assets

RUN npm run deploy --prefix=assets
RUN mix phx.digest
RUN mix release

# ---------------------------------------------------------------------------
# Runtime
# ---------------------------------------------------------------------------
FROM alpine:3.21.3 AS app

# UID 10001 matches the official zfnd/zebra image, so the explorer can read the
# RPC cookie file Zebra writes with mode 0600 from a shared volume without that
# file being world-readable. Override with --build-arg UID=... if the node runs
# as someone else.
ARG UID=10001
ARG GID=10001
ARG USER=swarm

# openssl/ncurses/libstdc++/libgcc are the OTP runtime's shared libraries;
# wget (busybox) serves the HEALTHCHECK below.
RUN apk add --no-cache openssl ncurses-libs libstdc++ libgcc ca-certificates && \
    addgroup -g ${GID} ${USER} && \
    adduser -D -u ${UID} -G ${USER} -h /app ${USER}

WORKDIR /app

COPY --from=build --chown=${UID}:${GID} /app/_build/prod/rel/zcash_explorer ./

ENV HOME=/app PORT=4000 LANG=C.UTF-8

# Conservative defaults for a 2 vCPU / 4 GB server; see README-SWARM.md.
ENV SWARM_CACHE_LIMIT=1500 SWARM_CACHE_TTL_MINUTES=15 SWARM_WARMER_WINDOW=21

USER ${UID}:${GID}

EXPOSE 4000

# Liveness only: /healthz makes no RPC call, so a node restart does not kill
# the container. Readiness is the "node" field in its JSON body.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -q -O /dev/null "http://127.0.0.1:${PORT}/healthz" || exit 1

CMD ["bin/zcash_explorer", "start"]
