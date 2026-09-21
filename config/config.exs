# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configures the endpoint
config :zcash_explorer, ZcashExplorerWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "rVfb1mphofjIChVV5RIHW32JxP+aNNOGR4TaOrFSmEPhywkGmPjNHHj6QKCnMxDq",
  render_errors: [view: ZcashExplorerWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: ZcashExplorer.PubSub,
  live_view: [signing_salt: "a4lss9+vZQHOxErTzxjNU4IuhAaslE0Z"]

# SWARM defaults. Every one of these is overridden from the environment at
# runtime (see config/runtime.exs and README-SWARM.md); the values here are the
# figures in specs/ECONOMICS.md v0.4 so a development run is already correct.
config :zcash_explorer, ZcashExplorer.Swarm,
  project_name: "SWARM",
  network_name: "SwarmTestnet",
  ticker: "SWM",
  max_supply: 20_999_987.3152,
  halving_interval: 1_680_000,
  block_target_seconds: 75,
  recipients: []

config :zcash_explorer, ZcashExplorer.Rpc,
  url: "http://127.0.0.1:18232",
  cookie_path: nil,
  username: nil,
  password: nil,
  timeout: 120_000

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
