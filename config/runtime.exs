# Runtime configuration, read on every boot of the release.
#
# SWARM change: this replaces upstream's `config/releases.exs`, which used the
# pre-Elixir-1.11 release config file and demanded ZCASHD_USERNAME and
# ZCASHD_PASSWORD. Zebra authenticates with a rotating cookie file instead, and
# a private network needs its own labels, so every knob is an environment
# variable documented in README-SWARM.md.
import Config

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      Generate one with: mix phx.gen.secret
      """

  # Phoenix wants a bare host here; EXPLORER_SCHEME supplies the scheme.
  explorer_hostname =
    System.get_env("EXPLORER_HOSTNAME", "localhost")
    |> String.replace(~r{^[a-z]+://}, "")
    |> String.trim_trailing("/")

  log_level = System.get_env("LOG_LEVEL", "info")

  # :debug wrote a full stack trace plus every request's params to the container
  # log; it reached 7.2 GB with no rotation upstream. Override with LOG_LEVEL.
  config :logger, level: String.to_existing_atom(log_level)

  config :zcash_explorer, ZcashExplorerWeb.Endpoint,
    url: [
      host: explorer_hostname,
      port: String.to_integer(System.get_env("EXPLORER_PORT") || "443"),
      scheme: System.get_env("EXPLORER_SCHEME") || "https"
    ],
    http: [
      # 0.0.0.0 so the container is reachable from the reverse proxy.
      ip: {0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "4000"),
      transport_options: [socket_opts: [:inet], compress: true]
    ],
    secret_key_base: secret_key_base,
    # Derived from EXPLORER_HOSTNAME so the websocket allowlist follows the
    # domain this instance is actually served under. Upstream hardcoded
    # zcashblockexplorer.com.
    check_origin: [
      "//" <> explorer_hostname,
      "//localhost",
      "http://127.0.0.1:" <> (System.get_env("PORT") || "4000")
    ],
    server: true

  # ---------------------------------------------------------------------------
  # Zebra JSON-RPC
  # ---------------------------------------------------------------------------
  rpc_url =
    System.get_env("ZEBRA_RPC_URL") ||
      "http://#{System.get_env("ZEBRA_RPC_HOST", "127.0.0.1")}:#{System.get_env("ZEBRA_RPC_PORT", "18232")}"

  config :zcash_explorer, ZcashExplorer.Rpc,
    url: rpc_url,
    # Read at request time and re-read after an auth failure: Zebra writes a new
    # secret into this file on every start.
    cookie_path: System.get_env("ZEBRA_COOKIE_PATH"),
    # Only for a node running with `enable_cookie_auth = false` behind its own
    # proxy. Leave unset when a cookie path is given.
    username: System.get_env("ZEBRA_RPC_USER"),
    password: System.get_env("ZEBRA_RPC_PASSWORD"),
    timeout: String.to_integer(System.get_env("ZEBRA_RPC_TIMEOUT_MS") || "120000")

  # ---------------------------------------------------------------------------
  # Network identity and the block-reward allocation
  # ---------------------------------------------------------------------------
  # Either SWARM_RECIPIENTS_FILE (path to a JSON array) or SWARM_RECIPIENTS
  # (the JSON array inline). Each entry:
  #   {"slot":"ECC","label":"Core Development","address":"t2…","percent":8}
  # `slot` is the upstream Zebra receiver name: ECC, MajorGrants,
  # ZcashFoundation. Nothing is hard-coded in the source.
  recipients =
    case {System.get_env("SWARM_RECIPIENTS_FILE"), System.get_env("SWARM_RECIPIENTS")} do
      {path, _} when is_binary(path) and path != "" ->
        path |> File.read!() |> Jason.decode!()

      {_, json} when is_binary(json) and json != "" ->
        Jason.decode!(json)

      _ ->
        []
    end

  config :zcash_explorer, ZcashExplorer.Swarm,
    project_name: System.get_env("SWARM_PROJECT_NAME", "SWARM"),
    network_name: System.get_env("SWARM_NETWORK_NAME", "SwarmTestnet"),
    ticker: System.get_env("SWARM_TICKER", "SWARM"),
    max_supply: String.to_float(System.get_env("SWARM_MAX_SUPPLY") || "20999987.3152"),
    halving_interval: String.to_integer(System.get_env("SWARM_HALVING_INTERVAL") || "1680000"),
    block_target_seconds:
      String.to_integer(System.get_env("SWARM_BLOCK_TARGET_SECONDS") || "75"),
    recipients: recipients

  config :zcash_explorer, ZcashExplorer.WarmerWindow,
    window: String.to_integer(System.get_env("SWARM_WARMER_WINDOW") || "21"),
    interval_ms:
      case System.get_env("SWARM_WARMER_INTERVAL_MS") do
        nil -> nil
        "" -> nil
        value -> String.to_integer(value)
      end

  IO.puts(
    "SWARM explorer configured for #{System.get_env("SWARM_NETWORK_NAME", "SwarmTestnet")} " <>
      "at #{explorer_hostname}, node #{rpc_url}, " <>
      "cookie #{System.get_env("ZEBRA_COOKIE_PATH") || "(none)"}, " <>
      "#{length(recipients)} reward destinations"
  )
end
