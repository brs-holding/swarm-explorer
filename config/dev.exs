import Config

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with webpack to recompile .js and .css sources.
# SWARM change: the Phoenix secrets live here rather than in config/config.exs,
# so they apply to a `mix phx.server` on a laptop and to nothing else. A release
# is built with MIX_ENV=prod and never reads this file; config/runtime.exs
# demands SECRET_KEY_BASE, LIVE_VIEW_SIGNING_SALT and SESSION_SIGNING_SALT from
# the environment instead. These three are throwaway local values, not secrets:
# regenerate them whenever you like with `openssl rand -base64 48`.
config :zcash_explorer, :session_options, signing_salt: "AgJLMhGlGRlsJAAl"

config :zcash_explorer, ZcashExplorerWeb.Endpoint,
  secret_key_base: "tJcIqKpTAteAH/hCQ9D8jMNK0iznCCJVs06YwWU1fQB17s7YNwBogyQUFRjal/Rs",
  live_view: [signing_salt: "CTEbudJDktbxrUTH"],
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [
    node: [
      "node_modules/webpack/bin/webpack.js",
      "--mode",
      "development",
      "--watch-stdin",
      cd: Path.expand("../assets", __DIR__),
      env: [{"NODE_OPTIONS", "--openssl-legacy-provider"}]
    ],
    npm: [
      "run",
      "watch:css",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]

# Point this at a local Zebra node. With cookie auth left on (Zebra's default)
# set cookie_path to the node's `.cookie`; with `enable_cookie_auth = false` in
# zebrad.toml leave both unset.
config :zcash_explorer, ZcashExplorer.Rpc,
  url: System.get_env("ZEBRA_RPC_URL") || "http://127.0.0.1:18232",
  cookie_path: System.get_env("ZEBRA_COOKIE_PATH")

# Watch static and templates for browser reloading.
config :zcash_explorer, ZcashExplorerWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/zcash_explorer_web/(live|views)/.*(ex)$",
      ~r"lib/zcash_explorer_web/templates/.*(eex)$"
    ]
  ]

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
