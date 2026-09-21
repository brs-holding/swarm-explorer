import Config

# The real host, port and scheme come from the environment at boot; see
# config/runtime.exs. This file only carries what must be known at build time.
config :zcash_explorer, ZcashExplorerWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

# Do not print debug messages in production
config :logger, level: :info
