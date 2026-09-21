# SWARM Explorer

Block explorer for the private **SwarmTestnet** network. A fork of the
Apache-2.0 Zcash block explorer; it talks only to a Zebra node over JSON-RPC
and keeps no database.

* **How to configure and run it:** [`README-SWARM.md`](README-SWARM.md)
* **How to deploy it behind Caddy:** [`deploy/README.md`](deploy/README.md)
* **What was changed from upstream, and why:** [`NOTICE`](NOTICE)

```sh
docker build -t brs-swarm-explorer .
docker run --rm -p 4000:4000   -e SECRET_KEY_BASE="$(openssl rand -base64 48)"   -e ZEBRA_RPC_URL=http://127.0.0.1:18232   -e ZEBRA_COOKIE_PATH=/zebra-cookie/.cookie   -v zebra-cookie:/zebra-cookie:ro   brs-swarm-explorer
```

SWARM testnet coins have no value. SWARM is not affiliated with the Electric
Coin Company, the Zcash Foundation, Zcash Community Grants, any other Zcash
project, or Nighthawk Apps.

Licensed under the Apache License 2.0 — see [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE).

Official channels: <https://swarm.green> · <https://github.com/brs-holding> ·
[@swarm_coin](https://x.com/swarm_coin) · swarmofficial@atomicmail.io
