defmodule ZcashExplorerWeb.PageController do
  alias ZcashExplorer.Rpc
  alias ZcashExplorer.Swarm
  use ZcashExplorerWeb, :controller

  @moduledoc """
  SWARM changes in this controller:

  * `disclosure/2` and `do_disclosure/2` are gone. They called
    `z_validatepaymentdisclosure`, which is a zcashd wallet RPC; Zebra has no
    such method, so the page could only ever error.
  * `vk/2`, `do_import_vk/2` and `vk_from_zecwalletcli/2` are gone. They shelled
    out to `docker create nighthawkapps/vkrunner …` through MuonTrap, which
    requires a Docker socket inside the web container and a third-party image.
  * `health/2` is new: a liveness endpoint that touches no RPC, for the
    container healthcheck and the reverse proxy.
  """

  def index(conn, _params) do
    render(conn, "index.html",
      page_title: "#{Swarm.project_name()} Explorer - search the #{Swarm.network_name()} chain"
    )
  end

  def broadcast(conn, _params) do
    render(conn, "broadcast.html",
      csrf_token: get_csrf_token(),
      page_title: "Broadcast a raw #{Swarm.project_name()} transaction"
    )
  end

  def do_broadcast(conn, params) do
    tx_hex = params["tx-hex"]

    case Rpc.sendrawtransaction(tx_hex) do
      {:ok, resp} ->
        conn
        |> put_flash(:info, resp)
        |> render("broadcast.html",
          csrf_token: get_csrf_token(),
          page_title: "Broadcast a raw #{Swarm.project_name()} transaction"
        )

      {:error, reason} ->
        conn
        |> put_flash(:error, reason)
        |> render("broadcast.html",
          csrf_token: get_csrf_token(),
          page_title: "Broadcast a raw #{Swarm.project_name()} transaction"
        )
    end
  end

  def mempool(conn, _params) do
    render(conn, "mempool.html", page_title: "#{Swarm.project_name()} mempool")
  end

  def nodes(conn, _params) do
    render(conn, "nodes.html", page_title: "#{Swarm.project_name()} nodes")
  end

  def blockchain_info(conn, _params) do
    render(conn, "blockchain_info.html", page_title: "#{Swarm.project_name()} chain info")
  end

  def blockchain_info_api(conn, _params) do
    info = ZcashExplorer.Cache.get("metrics", %{})
    build = ZcashExplorer.Cache.field("info", "build")
    info = Map.put(info, "build", build)
    json(conn, info)
  end

  @doc """
  GET /healthz

  Liveness only: it reports that the web process is answering, and deliberately
  makes no RPC call, so a node restart does not take the container down. The
  `node` field says whether the last warmer run reached the node, which a
  monitor can use for readiness.
  """
  def health(conn, _params) do
    height = ZcashExplorer.Cache.field("metrics", "blocks")

    conn
    |> put_status(200)
    |> json(%{
      status: "ok",
      network: Swarm.network_name(),
      ticker: Swarm.ticker(),
      node: if(is_nil(height), do: "unreachable", else: "ok"),
      height: height
    })
  end

  @doc """
  GET /api/v1/supply

  - If no query params: returns valuePools array as JSON.
  - If `q=totalSupply`: returns the total chain supply as plain text.
  - If `q=circulatingSupply`: returns circulating supply (total minus lockbox) as plain text.
  - If invalid query, returns 404.
  """
  def supply(conn, params) do
    info = ZcashExplorer.Cache.get("metrics", %{})

    if params == %{} do
      json(conn, info["valuePools"] || [])
    else
      case params["q"] do
        "totalSupply" ->
          send_resp(conn, 200, to_string(get_in(info, ["chainSupply", "chainValue"])))

        "circulatingSupply" ->
          total = get_in(info, ["chainSupply", "chainValue"]) || 0

          # SWARM uses no deferred (lockbox) pool, so this normally equals the
          # total; the subtraction is kept so a chain that does use one still
          # reports correctly.
          lockbox =
            (info["valuePools"] || [])
            |> Enum.find(fn pool -> pool["id"] == "lockbox" end)
            |> case do
              %{"chainValue" => value} when is_number(value) -> value
              _ -> 0
            end

          send_resp(conn, 200, to_string(total - lockbox))

        _ ->
          send_resp(conn, 404, "valid query keys are 'totalSupply' and 'circulatingSupply'")
      end
    end
  end
end
