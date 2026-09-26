# Runtime configuration, read on every boot of the release.
#
# SWARM change: this replaces upstream's `config/releases.exs`, which used the
# pre-Elixir-1.11 release config file and demanded ZCASHD_USERNAME and
# ZCASHD_PASSWORD. Zebra authenticates with a rotating cookie file instead, and
# a private network needs its own labels, so every knob is an environment
# variable documented in README-SWARM.md.
import Config

if config_env() == :prod do
  # ---------------------------------------------------------------------------
  # Phoenix secrets
  # ---------------------------------------------------------------------------
  # All three are compile-time values in a stock Phoenix application, which
  # means a built image carries whatever the source tree happened to hold —
  # upstream's published development values, in this fork's case. They are read
  # here instead, and a missing one stops the boot rather than falling back to
  # something a reader of the repository already knows.
  #
  #   SECRET_KEY_BASE          signs and encrypts the session cookie
  #   SESSION_SIGNING_SALT     salts that signature (Plug.Session)
  #   LIVE_VIEW_SIGNING_SALT   salts the LiveView session token
  #
  # Generate each one separately:  openssl rand -base64 48
  require_env = fn name ->
    case System.get_env(name) do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        raise """
        environment variable #{name} is missing.
        Generate one with: openssl rand -base64 48
        """
    end
  end

  secret_key_base = require_env.("SECRET_KEY_BASE")
  session_signing_salt = require_env.("SESSION_SIGNING_SALT")
  live_view_signing_salt = require_env.("LIVE_VIEW_SIGNING_SALT")

  # Read by ZcashExplorerWeb.Endpoint.session_options/0, which both the session
  # plug and the LiveView socket go through, so the two can never drift apart.
  config :zcash_explorer, :session_options, signing_salt: session_signing_salt

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
    live_view: [signing_salt: live_view_signing_salt],
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
  # Either SWARM_RECIPIENTS_FILE (path to a JSON file) or SWARM_RECIPIENTS (the
  # same JSON inline). Two shapes are read, so that the file the node's own
  # configuration is rendered from can be handed straight to the explorer:
  #
  #   [{"slot":"ECC","label":"Core Development","address":"s3…","percent":8}]
  #   {"recipients":[{"label":"Core Development","address":"s3…","numerator":8}]}
  #
  # `slot` is the upstream Zebra receiver name (ECC, MajorGrants,
  # ZcashFoundation); when an entry has none it is looked up from its label.
  # `numerator` is the renderer's name for `percent`. Nothing is hard-coded in
  # the source. ZcashExplorer.Swarm normalises both again at read time, so
  # neither layer alone can let the two files drift apart.
  decoded =
    case {System.get_env("SWARM_RECIPIENTS_FILE"), System.get_env("SWARM_RECIPIENTS")} do
      {path, _} when is_binary(path) and path != "" ->
        path |> File.read!() |> Jason.decode!()

      {_, json} when is_binary(json) and json != "" ->
        Jason.decode!(json)

      _ ->
        []
    end

  recipients =
    case decoded do
      %{"recipients" => list} when is_list(list) -> list
      list when is_list(list) -> list
      _ -> []
    end

  config :zcash_explorer, ZcashExplorer.Swarm,
    project_name: System.get_env("SWARM_PROJECT_NAME", "SWARM"),
    network_name: System.get_env("SWARM_NETWORK_NAME", "SwarmTestnet"),
    # "mainnet" or "testnet". Unset means "read it off the network name", which
    # is what every deployment does; an unrecognisable name stays a test
    # network, so the "no value" warning is never dropped by accident.
    network_kind: System.get_env("SWARM_NETWORK_KIND"),
    ticker: System.get_env("SWARM_TICKER", "SWM"),
    max_supply: String.to_float(System.get_env("SWARM_MAX_SUPPLY") || "20999987.3152"),
    halving_interval: String.to_integer(System.get_env("SWARM_HALVING_INTERVAL") || "1680000"),
    block_target_seconds:
      String.to_integer(System.get_env("SWARM_BLOCK_TARGET_SECONDS") || "75"),
    recipients: recipients

  # Unset means "derive it from the block target"; see
  # ZcashExplorer.WarmerWindow. Computed into a variable because a multi-line
  # `case` cannot be the value of a keyword in a parenthesis-less call.
  warmer_interval_ms =
    case System.get_env("SWARM_WARMER_INTERVAL_MS") do
      nil -> nil
      "" -> nil
      value -> String.to_integer(value)
    end

  config :zcash_explorer, ZcashExplorer.WarmerWindow,
    window: String.to_integer(System.get_env("SWARM_WARMER_WINDOW") || "21"),
    interval_ms: warmer_interval_ms

  IO.puts(
    "SWARM explorer configured for #{System.get_env("SWARM_NETWORK_NAME", "SwarmTestnet")} " <>
      "at #{explorer_hostname}, node #{rpc_url}, " <>
      "cookie #{System.get_env("ZEBRA_COOKIE_PATH") || "(none)"}, " <>
      "#{length(recipients)} reward destinations"
  )
end
