# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configures the endpoint
#
# SWARM change: NO SECRET IS SET HERE. This file is compile-time configuration,
# so anything it holds is frozen into the release's sys.config and cannot be
# replaced by whoever runs the image. Upstream shipped its development
# `secret_key_base` and LiveView `signing_salt` here, and the built image
# therefore carried published values on every deployment.
#
#   * in :prod they come from the environment in config/runtime.exs, which
#     refuses to boot when they are missing;
#   * in :dev and :test they come from config/dev.exs and config/test.exs,
#     which never reach a release.
#
# `mix test` asserts that this file, read with env: :prod, carries none of them
# (test/swarm/release_secrets_test.exs) and CI re-checks the built image's
# sys.config byte by byte (ci/check-release-secrets.py).
config :zcash_explorer, ZcashExplorerWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: ZcashExplorerWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: ZcashExplorer.PubSub

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

# SWARM change: tzdata ships a timezone database inside the release and, left
# alone, polls IANA for a newer one every few seconds and writes a marker into
# its own priv directory. A release has no business downloading anything at
# runtime, and this one runs with a read-only root filesystem, so the write
# could never succeed: the updater crashed, its supervisor restarted it, and it
# retried three seconds later, forever — 722 crashes in the first 36 minutes on
# the deployed image, about 1,200 log lines an hour, which rotated the log away
# faster than anything useful could stay in it (workstream F, 2026-09-22).
#
# The database compiled into the image is what serves. Updating it means
# building a new image, which is how everything else here is updated. Set for
# every environment, not just :prod, because nothing should poll in the
# background on a laptop either.
#
# Timex is only used to format block timestamps as UTC (BlockView.mined_time/1
# and friends), so no timezone conversion depends on a newer release.
config :tzdata, :autoupdate, :disabled

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
#
# SWARM change: `config_env()` rather than `Mix.env()`. They agree during a
# build, but only `config_env()` follows the env a reader asks for, which is
# what lets the release-secrets test read this file exactly as `mix release`
# resolves it for :prod.
import_config "#{config_env()}.exs"
