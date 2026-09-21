defmodule ZcashExplorerWeb.Router do
  use ZcashExplorerWeb, :router
  import Phoenix.LiveView.Router

  @moduledoc """
  SWARM changes: removed `live "/price", PriceLive` (the module does not exist
  in this tree, and test coins have no price), the `/payment-disclosure` routes
  (`z_validatepaymentdisclosure` is a zcashd wallet RPC that Zebra does not
  serve) and the `/vk` routes (they shelled out to a Docker image). Added
  `/healthz` for the container healthcheck.
  """

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :put_root_layout, {ZcashExplorerWeb.LayoutView, :root}
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ZcashExplorerWeb do
    pipe_through :browser

    get "/", PageController, :index
    get "/blocks/:hash", BlockController, :get_block
    get "/transactions/:txid", TransactionController, :get_transaction
    live "/metrics/difficulty", DifficultyLive
    live "/metrics/block_count", BlockCountLive
    live "/metrics/blockchain_size", BlockChainSizeLive
    live "/metrics/mempool_info", MempoolInfoLive
    live "/metrics/networksolps", NetworkSolpsLive
    live "/metrics/supply", SupplyLive
    live "/metrics/halving", HalvingLive
    live "/index/recent_blocks", RecentBlocksLive
    live "/index/recent_transactions", RecentTransactionsLive
    live "/live/raw_mempool", RawMempoolLive
    live "/live/shielded_pools", ShieldedPoolLive
    live "/live/nodes", NodesLive
    live "/blockchain-info-live", BlockChainInfoLive
    get "/broadcast", PageController, :broadcast
    post "/broadcast", PageController, :do_broadcast
    get "/address/:address", AddressController, :get_address
    get "/search", SearchController, :search
    get "/blocks", BlockController, :index
    get "/mempool", PageController, :mempool
    get "/nodes", PageController, :nodes
    get "/blockchain-info", PageController, :blockchain_info
    get "/ua/:address", AddressController, :get_ua
  end

  scope "/", ZcashExplorerWeb do
    pipe_through :api
    get "/healthz", PageController, :health
    get "/api/v1/blockchain-info", PageController, :blockchain_info_api
    get "/api/v1/supply", PageController, :supply
    get "/transactions/:txid/raw", TransactionController, :get_raw_transaction
  end

  # Enables LiveDashboard only for development
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ZcashExplorerWeb.Telemetry
    end
  end
end
