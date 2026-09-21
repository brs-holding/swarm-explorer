# SWARM Explorer

A block explorer for the private **SwarmTestnet** network, forked from the
Apache-2.0 Zcash block explorer (`matiasurbieta/zcash-explorer`, lineage
`nighthawk-apps` → `zcash` → `matiasurbieta`). It is stateless: it has no
database and reads everything from one Zebra node over JSON-RPC.

**SWARM is not affiliated with the Electric Coin Company, the Zcash Foundation,
Zcash Community Grants, any other Zcash project, or Nighthawk Apps.** Test
coins have no value. See `NOTICE` for the full list of changes to the upstream
work, which Apache-2.0 §4(b) requires.

The internal OTP application is still called `zcash_explorer` and the modules
are still `ZcashExplorer*`. That is deliberate: renaming 120 files would bury
the adaptation in churn and make the diff against upstream unreadable.

---

## What it needs

* One **Zebra 6.3.0** node with its JSON-RPC port reachable. Cookie
  authentication can be left on (Zebra's default).
* Nothing else. No database, no Docker socket, no external service.

## Running it

```sh
docker build -t brs-swarm-explorer .
docker run --rm -p 4000:4000 \
  -e SECRET_KEY_BASE="$(openssl rand -base64 48)" \
  -e EXPLORER_HOSTNAME=explore.swarm.green \
  -e ZEBRA_RPC_URL=http://zebra:18232 \
  -e ZEBRA_COOKIE_PATH=/zebra-cookie/.cookie \
  -e SWARM_RECIPIENTS_FILE=/etc/swarm/recipients.json \
  -v zebra-cookie:/zebra-cookie:ro \
  -v ./recipients.json:/etc/swarm/recipients.json:ro \
  brs-swarm-explorer
```

The image runs as **uid 10001**, the same uid as the official `zfnd/zebra`
image, so it can read Zebra's `.cookie` (mode 0600) from a shared volume
without that file being world-readable. If your node runs as a different user,
rebuild with `--build-arg UID=<that uid>` or make the cookie directory
group-readable.

---

## Environment variables

Everything is configuration. Nothing in this list is hard-coded in the source.

### Web

| Variable | Required | Default | What it does |
| --- | --- | --- | --- |
| `SECRET_KEY_BASE` | **yes** | — | Phoenix session/LiveView signing key, at least 64 bytes. Generate with `mix phx.gen.secret` or `openssl rand -base64 48`. The container refuses to start without it. |
| `EXPLORER_HOSTNAME` | no | `localhost` | Public hostname. Drives the generated URLs **and** the LiveView `check_origin` allowlist. A scheme prefix and a trailing slash are stripped, so `https://explore.swarm.green/` and `explore.swarm.green` both work. |
| `EXPLORER_SCHEME` | no | `https` | Scheme in generated URLs. |
| `EXPLORER_PORT` | no | `443` | Port in generated URLs (the public one, behind the proxy). |
| `PORT` | no | `4000` | Port the container actually listens on, bound to `0.0.0.0`. |
| `LOG_LEVEL` | no | `info` | `debug` writes a stack trace and every request's params; upstream left it there and the log reached 7.2 GB. |

### Node

| Variable | Required | Default | What it does |
| --- | --- | --- | --- |
| `ZEBRA_RPC_URL` | no | built from the two below | Full RPC URL, e.g. `http://zebra:18232`. |
| `ZEBRA_RPC_HOST` | no | `127.0.0.1` | Used only when `ZEBRA_RPC_URL` is unset. |
| `ZEBRA_RPC_PORT` | no | `18232` | Used only when `ZEBRA_RPC_URL` is unset. |
| `ZEBRA_COOKIE_PATH` | no | unset | Path to Zebra's `.cookie`. **Read at request time**, and re-read once after an authentication failure, because Zebra generates a new secret on every start. Never logged. |
| `ZEBRA_RPC_USER` | no | unset | Static username, only for a node running with `enable_cookie_auth = false`. Leave unset when a cookie path is given. |
| `ZEBRA_RPC_PASSWORD` | no | unset | As above. |
| `ZEBRA_RPC_TIMEOUT_MS` | no | `120000` | Per-request receive timeout. |

### Network identity and the block reward

| Variable | Required | Default | What it does |
| --- | --- | --- | --- |
| `SWARM_PROJECT_NAME` | no | `SWARM` | Shown in page titles and headings. |
| `SWARM_NETWORK_NAME` | no | `SwarmTestnet` | Shown next to the logo and in `/healthz`. |
| `SWARM_TICKER` | no | `SWM` | Coin ticker appended to every public amount. The project is SWARM; the coin is SWM. |
| `SWARM_MAX_SUPPLY` | no | `20999987.3152` | Denominator of the "supply issued" figure (`specs/ECONOMICS.md` §3). Must parse as a float, so write `21000000.0`, not `21000000`. |
| `SWARM_HALVING_INTERVAL` | no | `1680000` | Blocks per era. The first halving lands at `interval - 1` = 1,679,999, matching upstream's `floor((height + 1) / interval)`. |
| `SWARM_BLOCK_TARGET_SECONDS` | no | `75` | Target block spacing. Also the default for the warmer interval. |
| `SWARM_RECIPIENTS_FILE` | no | unset | Path to a JSON array describing the three reward destinations (below). Takes precedence over `SWARM_RECIPIENTS`. |
| `SWARM_RECIPIENTS` | no | unset | The same JSON array, inline. |

With neither set, the explorer still renders a correct breakdown using the
labels and percentages of `specs/ECONOMICS.md`, but cannot link the
destination addresses or badge them on the address page.

`recipients.json`:

```json
[
  {"slot": "ECC",             "label": "Core Development",                "address": "t2...", "percent": 8},
  {"slot": "MajorGrants",     "label": "Grants & Ecosystem",              "address": "t2...", "percent": 4},
  {"slot": "ZcashFoundation", "label": "Community & Development Reserve", "address": "t2...", "percent": 8}
]
```

`slot` is the **upstream Zebra receiver name**, exactly as it appears in the
node's `funding_streams` TOML. Zebra's `getblocksubsidy` reports these slots
under their Zcash display names; the explorer maps them back:

| `slot` | What `getblocksubsidy` says | What the explorer shows |
| --- | --- | --- |
| `ECC` | `Electric Coin Company` | Core Development |
| `MajorGrants` | `Zcash Community Grants NU6` (post-NU6) or `Major Grants` | Grants & Ecosystem |
| `ZcashFoundation` | `Zcash Foundation` | Community & Development Reserve |

Both spellings of `MajorGrants` are accepted. Every upgrade through NU6.3 is
active from height 1 on SwarmTestnet, so the post-NU6 spelling is the one that
appears in practice.

### Resource limits

Defaults are sized for a 2 vCPU / 4 GB server shared with the node.

| Variable | Required | Default | What it does |
| --- | --- | --- | --- |
| `SWARM_CACHE_LIMIT` | no | `1500` | Maximum entries in the single Cachex table. Raw transaction hex runs to tens of KB per entry; upstream's 10,000 allowed a few hundred MB. |
| `SWARM_CACHE_TTL_MINUTES` | no | `15` | Default entry expiry. The janitor runs every minute. |
| `SWARM_WARMER_WINDOW` | no | `21` | How many recent blocks the "latest blocks" and "latest transactions" warmers refetch. |
| `SWARM_WARMER_INTERVAL_MS` | no | `block target / 3`, i.e. 25000 | How often they do it. Upstream refetched 21 blocks plus 20 transactions every 15 s, which at 75-second blocks is about 55 RPC calls per block produced. |
| `ERL_FLAGS` | no | unset | Extra BEAM flags. `rel/vm.args.eex` already pins `+S 2:2` because the BEAM otherwise sizes its scheduler pool from the **host's** core count, not the container's CPU quota. |

---

## Design

The interface follows **Swarm Style Guide v2**. Three rules matter when
changing it:

1. **Colour is a claim about the data, not decoration.** Hive Orange `#FF8A1F`
   means brand or *shielded*. Honey `#FFB020` means a mining reward. Clear Blue
   `#6FB6FF` means *this data is public* and must never be used as a neutral
   accent. Green `#3DD68C` means confirmed.
2. **Never print a number the chain does not contain.** A shielded transaction
   shows the masked glyphs; its transparent total is not what was sent. A
   figure the node cannot supply shows an em dash, never a placeholder.
3. **No third-party request, ever.** Sora, Manrope and JetBrains Mono are
   bundled from npm and served from this origin. There is no analytics, no
   tracker, no external script or stylesheet, and no browser storage beyond the
   session cookie Phoenix needs.

Two figures deserve their definitions:

* **Shielded share** (per block, in the block list) is the share of that
  block's **non-coinbase** transactions carrying at least one shielded
  component — a Sapling spend or output, an Orchard action, an Ironwood action
  or a legacy joinsplit. The coinbase is excluded because it is produced by the
  protocol rather than by a user's privacy choice. A block holding nothing but
  its coinbase has no honest share and shows an em dash.
* **Network Sol/s** is `getnetworksolps`, in Equihash *solutions* per second.
  On a minimum-difficulty chain Zebra has been observed returning 0; that is
  "not measurable yet", not a rate, so it renders as an em dash.

---

## Endpoints

| Path | What it is |
| --- | --- |
| `/` | Height, difficulty, network solution rate, mempool size, supply issued vs the maximum, next halving height, every value pool, chain size, latest blocks, latest transactions |
| `/blocks`, `/blocks/:height-or-hash` | Block list and detail, including the four-way **Block reward** breakdown |
| `/transactions/:txid`, `/transactions/:txid/raw` | Transaction detail; raw JSON |
| `/address/:address`, `/ua/:address` | Transparent, shielded and unified addresses. A reward destination is badged |
| `/search?qs=` | Height, block hash, txid or address |
| `/mempool`, `/nodes`, `/blockchain-info`, `/broadcast` | |
| `/healthz` | **Liveness.** Always 200 while the web process answers, and makes no RPC call, so a node restart does not kill the container. Readiness is the `node` field: `"ok"` or `"unreachable"` |
| `/api/v1/blockchain-info`, `/api/v1/supply` | JSON |

Removed because Zebra cannot serve them: `/payment-disclosure`, `/vk`,
`/price`. They return 404.

---

## Developing without Docker

```sh
mix deps.get
npm install --prefix assets
ZEBRA_RPC_URL=http://127.0.0.1:18232 \
ZEBRA_COOKIE_PATH=$HOME/.cache/zebra/.cookie \
  mix phx.server
```

`mix test` needs no database and no node.

## What CI proves

`.github/workflows/swarm-ci.yml` runs on every push to `swarm-testnet`:

1. `mix compile --warnings-as-errors` and `mix test`.
2. `docker build --platform linux/amd64`.
3. A real `zfnd/zebra:6.3.0` node in **Regtest** mode with cookie auth on, a
   few dozen blocks mined through the `generate` RPC to
   `t27eWDgjFYJGVXmzrXeVjnb5J3uXDM9xH9v` (Zebra's own documented test address).
4. curl assertions on the home page, block 1, the tip, a coinbase transaction,
   an address page, and search by height.
5. The Zebra container is **restarted**, which rotates the cookie, and the
   explorer — not restarted — must follow the node to a new height.
6. The image is saved as a tarball artifact for workstream F. See `deploy/`.

Regtest cannot carry funding streams, so the reward breakdown is covered by
`test/swarm/block_reward_test.exs` against a recorded `getblocksubsidy` reply
with three funding-stream outputs.
