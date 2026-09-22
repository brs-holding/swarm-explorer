import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
#
# SWARM change: as in config/dev.exs, the Phoenix secrets are set per
# environment rather than in config/config.exs, so nothing reaches a release.
# Throwaway values; the suite only needs them to be present and well formed.
config :zcash_explorer, :session_options, signing_salt: "GPQxst0hy0qIgLjM"

config :zcash_explorer, ZcashExplorerWeb.Endpoint,
  secret_key_base: "jdLWvMdkp8qJW68Wt0QQ3pdGQo+xYJayOqLt5nUG+UbiGD6W3vZvcrx/1iEsAy0K",
  live_view: [signing_salt: "PdFWfbOrGbEPVkEK"],
  http: [port: 4002],
  server: false

# No node is reachable during tests; every RPC call is expected to fail fast
# rather than hang for two minutes.
config :zcash_explorer, ZcashExplorer.Rpc,
  url: "http://127.0.0.1:1",
  timeout: 200

# The three destinations under test. These are the upstream slot names mapped
# to the SWARM labels of specs/ECONOMICS.md; the addresses are fixtures, not
# the real destinations, which come from configuration at deploy time.
config :zcash_explorer, ZcashExplorer.Swarm,
  project_name: "SWARM",
  network_name: "SwarmTestnet",
  ticker: "SWM",
  max_supply: 20_999_987.3152,
  halving_interval: 1_680_000,
  block_target_seconds: 75,
  recipients: [
    %{
      "slot" => "ECC",
      "label" => "Core Development",
      "address" => "t2CoreDevelopmentFixtureAddress0001",
      "percent" => 8
    },
    %{
      "slot" => "MajorGrants",
      "label" => "Grants & Ecosystem",
      "address" => "t2GrantsEcosystemFixtureAddress0002",
      "percent" => 4
    },
    %{
      "slot" => "ZcashFoundation",
      "label" => "Community & Development Reserve",
      "address" => "t2CommunityReserveFixtureAddress003",
      "percent" => 8
    }
  ]

# Print only warnings and errors during test
config :logger, level: :warning
