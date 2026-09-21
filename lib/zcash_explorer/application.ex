defmodule ZcashExplorer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  import Cachex.Spec

  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      ZcashExplorerWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: ZcashExplorer.PubSub},
      # Start the Endpoint (http/https)
      ZcashExplorerWeb.Endpoint,
      # SWARM change: the Zcashex GenServer used to be supervised here purely to
      # hold the RPC host, port, username and password. Zebra rotates its
      # cookie secret on every restart, so credentials cannot be held for the
      # life of a process; `ZcashExplorer.Rpc` is a plain module that reads the
      # cookie when it sends a request. Nothing to supervise.
      {
        Cachex,
        # Raw transactions are cached here by transaction_controller; their `hex`
        # field runs to tens of KB, so without a bound the cache grew until the
        # OOM killer took the node down.
        #
        # SWARM change: upstream's bound was 10,000 entries, which still allows
        # a few hundred MB of raw transaction hex. The deployment target is a
        # 2 vCPU / 4 GB server shared with the node and the indexer, so the
        # default is 1,500 entries (SWARM_CACHE_LIMIT) with a 15-minute default
        # expiry (SWARM_CACHE_TTL_MINUTES) and a 1-minute janitor. The warmers
        # rewrite their own keys every interval, so LRW never evicts them.
        name: :app_cache,
        limit: limit(size: cache_limit(), policy: Cachex.Policy.LRW, reclaim: 0.25),
        expiration:
          expiration(
            default: :timer.minutes(cache_ttl_minutes()),
            interval: :timer.minutes(1)
          ),
        warmers: [
          warmer(module: ZcashExplorer.Metrics.MetricsWarmer, state: {}),
          warmer(module: ZcashExplorer.Metrics.MempoolInfoWarmer, state: {}),
          warmer(module: ZcashExplorer.Metrics.NetworkSolpsWarmer, state: {}),
          warmer(module: ZcashExplorer.Blocks.BlockWarmer, state: {}),
          warmer(module: ZcashExplorer.Transactions.TransactionWarmer, state: {}),
          warmer(module: ZcashExplorer.Mempool.MempoolWarmer, state: {}),
          warmer(module: ZcashExplorer.Nodes.NodeWarmer, state: {}),
          warmer(module: ZcashExplorer.Metrics.InfoWarmer, state: {})
        ]
      }
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ZcashExplorer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp cache_limit, do: env_int("SWARM_CACHE_LIMIT", 1_500)
  defp cache_ttl_minutes, do: env_int("SWARM_CACHE_TTL_MINUTES", 15)

  defp env_int(name, default) do
    case System.get_env(name) do
      nil -> default
      "" -> default
      value -> String.to_integer(value)
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    ZcashExplorerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
