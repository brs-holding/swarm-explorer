# Deploying the SWARM explorer (notes for workstream F)

The target is one small Linux server (2 shared vCPUs, 4 GB RAM) running the
whole stack behind Caddy. **The server does not build the explorer.** CI builds
the image and publishes it as a workflow artifact; the server loads that
tarball.

## 1. Get the image onto the server

Every green run of `SWARM explorer CI` on the `swarm-testnet` branch uploads an
artifact named `swarm-explorer-image-<git-sha>` containing:

| File | What it is |
| --- | --- |
| `swarm-explorer-<short-sha>.tar.gz` | `docker save` of the image, gzipped, `linux/amd64` |
| `SHA256SUMS` | checksum of that tarball |
| `image-manifest.json` | git sha and ref, image id, image and tarball size, build time, platform, the workflow run URL, and the measured steady-state memory |

Download it from the run page (or `gh run download <run-id> -R
brs-holding/swarm-explorer -n swarm-explorer-image-<git-sha>`), copy it to the
server, then:

```sh
sha256sum -c SHA256SUMS
gunzip -c swarm-explorer-<short-sha>.tar.gz | docker load
```

`docker load` prints the loaded tag. It is

```
brs-swarm-explorer:<short-sha>
```

and it is also the `image` field of `image-manifest.json`. Put it in the stack's
`.env`:

```dotenv
SWARM_EXPLORER_IMAGE=brs-swarm-explorer:<short-sha>
```

Nothing is pushed to a registry and no GitHub Release is created, so this load
step is the only way the image reaches the server. Keep the previous tarball
on the box: rolling back is editing `.env` and `docker compose up -d explorer`.

## 2. Compose service

Slot this into the stack next to `zebra`. It assumes the node writes its RPC
cookie into a named volume, which is the only thing the two containers share.

```yaml
services:
  explorer:
    image: ${SWARM_EXPLORER_IMAGE:?set it to the tag docker load printed}
    container_name: swarm-explorer
    restart: unless-stopped
    depends_on:
      zebra:
        condition: service_started
    # Same uid as the official zfnd/zebra image, so the 0600 cookie is
    # readable without being world-readable. The image already defaults to
    # this; it is repeated here so a mismatch is visible in the stack file.
    user: "10001:10001"
    networks: [swarm]
    expose:
      - "4000"            # internal only; Caddy is the only thing that talks to it
    volumes:
      # Read-only: the explorer must never be able to rewrite the node's cookie.
      - zebra-cookie:/zebra-cookie:ro
      - ./explorer/recipients.json:/etc/swarm/recipients.json:ro
    environment:
      SECRET_KEY_BASE: ${EXPLORER_SECRET_KEY_BASE:?generate with openssl rand -base64 48}
      EXPLORER_HOSTNAME: explore.swarm.green
      EXPLORER_SCHEME: https
      EXPLORER_PORT: "443"
      PORT: "4000"
      LOG_LEVEL: info

      ZEBRA_RPC_URL: http://zebra:18232
      ZEBRA_COOKIE_PATH: /zebra-cookie/.cookie

      SWARM_PROJECT_NAME: SWARM
      SWARM_NETWORK_NAME: SwarmTestnet
      SWARM_TICKER: SWM
      SWARM_MAX_SUPPLY: "20999987.3152"
      SWARM_HALVING_INTERVAL: "1680000"
      SWARM_BLOCK_TARGET_SECONDS: "75"
      SWARM_RECIPIENTS_FILE: /etc/swarm/recipients.json

      # Sized for 2 shared vCPUs / 4 GB shared with the node and the indexer.
      SWARM_CACHE_LIMIT: "1500"
      SWARM_CACHE_TTL_MINUTES: "15"
      SWARM_WARMER_WINDOW: "21"
      SWARM_WARMER_INTERVAL_MS: "25000"
    healthcheck:
      # Liveness. /healthz makes no RPC call, so restarting the node does not
      # restart the explorer. Readiness is the "node" field of its JSON body.
      test: ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1:4000/healthz || exit 1"]
      interval: 30s
      timeout: 5s
      start_period: 20s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 768M
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    read_only: true
    tmpfs:
      - /tmp

volumes:
  zebra-cookie:

networks:
  swarm:
```

Notes on that snippet:

* **Internal port 4000, never published.** Only Caddy reaches it. The node's
  RPC port must not be published either.
* **`read_only: true` works** because an Elixir release writes nothing at
  runtime except to `/tmp`. If a future change needs a writable path, add a
  named volume rather than dropping the flag.
* **`user: "10001:10001"`** must match whatever uid the Zebra container writes
  the cookie as. The official image uses 10001. If workstream F builds its own
  Zebra image with a different uid, either rebuild the explorer image with
  `--build-arg UID=<that uid>` or make the cookie directory group-readable.
* **`depends_on` is `service_started`, not `service_healthy`.** The explorer is
  designed to come up before the node and to keep answering while the node is
  down; `/healthz` reports the node separately.

## 3. Caddy

```caddyfile
explore.swarm.green {
    encode zstd gzip
    reverse_proxy swarm-explorer:4000
}
```

Caddy must pass the `Host` header through (it does by default). The explorer
derives its LiveView `check_origin` allowlist from `EXPLORER_HOSTNAME`, so that
variable has to equal the hostname Caddy serves, or the websocket that drives
the live tiles will be rejected while ordinary page loads still work.

## 4. Operational notes

* **Cookie rotation.** Zebra writes a new RPC secret every time it starts. The
  explorer reads the cookie file per request and re-reads it after an auth
  failure, so restarting the node needs no explorer restart. CI proves this by
  restarting the Zebra container and checking that the explorer, untouched,
  follows the node to a new height.
* **Memory.** The image pins the BEAM to two schedulers (`+S 2:2`) because the
  BEAM otherwise sizes its pool from the host's core count and not the
  container's CPU quota. The measured steady-state figure from the CI run is in
  `image-manifest.json`.
* **Logs.** `LOG_LEVEL=debug` writes a stack trace and every request's params.
  Upstream shipped with it on and the container log reached 7.2 GB unrotated.
  Leave it at `info` and set a log rotation policy on the daemon.
* **What this explorer will not do.** It has no database, no wallet, no keys
  and no write path to the chain other than `/broadcast`, which forwards a
  hex transaction to `sendrawtransaction`. If you do not want that exposed,
  block `POST /broadcast` at Caddy.
