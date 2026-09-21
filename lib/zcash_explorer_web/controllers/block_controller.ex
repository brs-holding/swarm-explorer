defmodule ZcashExplorerWeb.BlockController do
  alias ZcashExplorer.Rpc
  alias ZcashExplorer.Swarm
  use ZcashExplorerWeb, :controller

  @default_limit 20

  def get_block(conn, %{"hash" => hash}) do
    case Rpc.getblock(hash, 1) do
      {:ok, basic_block_data} -> render_block(conn, hash, basic_block_data)
      {:error, _reason} -> not_found(conn, hash)
    end
  end

  def index(conn, params) do
    limit = parse_int(params["limit"]) || @default_limit

    case parse_int(params["block"]) || tip_height() do
      nil ->
        not_found(conn, "blocks")

      from_block ->
        render_index(conn, from_block, limit, is_nil(params["block"]))
    end
  end

  # Full verbosity (2) is only needed to render a single block's transactions.
  # Anything over 250 txs is rendered from the light listing instead.
  defp render_block(conn, hash, basic_block_data) do
    txs = basic_block_data["tx"] || []

    with true <- length(txs) in 1..250,
         {:ok, block_data} <- Rpc.getblock(hash, 2) do
      block_data = Zcashex.Block.from_map(block_data)

      render(conn, "index.html",
        block_data: block_data,
        # SWARM change: upstream always passed nil here, so the assign existed
        # but never carried anything. The block page now shows the four-way
        # reward split from `getblocksubsidy` at this block's height.
        block_subsidy: block_subsidy(block_data.height),
        reward_breakdown: reward_breakdown(block_data.height),
        page_title: "#{Swarm.project_name()} block #{block_data.height}"
      )
    else
      _ ->
        render(conn, "basic_block.html",
          block_data: basic_block_data,
          reward_breakdown: reward_breakdown(basic_block_data["height"]),
          page_title: "#{Swarm.project_name()} block #{hash}"
        )
    end
  end

  # `getblocksubsidy` is cached for an hour: for a given height it is a pure
  # function of the consensus rules and never changes.
  defp block_subsidy(height) when is_integer(height) do
    case Cachex.fetch(:app_cache, "blocksubsidy:#{height}", fn ->
           case Rpc.getblocksubsidy(height) do
             {:ok, subsidy} -> {:commit, subsidy}
             {:error, _reason} -> {:ignore, nil}
           end
         end) do
      {:ok, subsidy} -> subsidy
      {:commit, subsidy} -> subsidy
      _ -> nil
    end
  catch
    :exit, _ -> nil
  end

  defp block_subsidy(_), do: nil

  defp reward_breakdown(height), do: height |> block_subsidy() |> Swarm.reward_breakdown()

  defp render_index(conn, from_block, limit, disable_previous) do
    to_block = max(from_block - limit, 0)
    blocks_data = cached_block_headers(to_block, from_block)

    render(conn, "blocks.html",
      blocks_data: blocks_data,
      disable_next: from_block == 0,
      disable_previous: disable_previous,
      date: "",
      previous: from_block + limit,
      next: to_block,
      page_title: "#{Swarm.project_name()} latest blocks"
    )
  end

  # Bots poll /blocks continuously and every miss costs 21 getblock plus 21
  # getblockheader calls, which is what pushed responses past nginx's 36s
  # proxy_read_timeout. Cachex.fetch/3 collapses concurrent callers onto one
  # computation instead of stampeding.
  defp cached_block_headers(to_block, from_block) do
    key = "block_headers:#{to_block}:#{from_block}"

    case Cachex.fetch(:app_cache, key, fn -> {:commit, block_headers(to_block, from_block)} end) do
      # Only the run that computed the value sets the TTL. Refreshing it on
      # every hit would slide the expiry forward under steady traffic and the
      # listing would never refresh. This Cachex version ignores a per-commit
      # ttl, so without it the entry would inherit the cache-wide 1h default.
      {:commit, headers} ->
        Cachex.expire(:app_cache, key, ZcashExplorer.WarmerWindow.interval_ms())
        headers

      {:ok, headers} ->
        headers

      _ ->
        []
    end
  end

  defp block_headers(to_block, from_block) do
    to_block..from_block
    |> Task.async_stream(&block_header/1,
      max_concurrency: System.schedulers_online() * 2,
      ordered: false,
      timeout: 20_000,
      on_timeout: :kill_task
    )
    |> Enum.flat_map(fn
      {:ok, {:ok, header}} -> [header]
      _ -> []
    end)
    |> Enum.reverse()
  end

  # Verbosity 1 already carries the hash; verbosity 2 pulled every transaction
  # of every listed block just to read it.
  defp block_header(height) do
    with {:ok, %{"hash" => hash}} <- Rpc.getblock(height, 1) do
      Rpc.getblockheader(hash)
    end
  end

  # An RPC call that exceeds its timeout can exit rather than returning
  # {:error, _}, so the case alone never saw it. The metrics warmer refreshes
  # this key regularly, which beats 404ing the block list over a blip.
  defp tip_height do
    case Rpc.getblockcount() do
      {:ok, n} -> n
      _ -> cached_tip()
    end
  catch
    :exit, _ -> cached_tip()
  end

  defp cached_tip, do: ZcashExplorer.Cache.field("metrics", "blocks")

  defp parse_int(nil), do: nil

  defp parse_int(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 -> n
      _ -> nil
    end
  end

  defp not_found(conn, subject) do
    conn
    |> put_status(:not_found)
    |> put_view(ZcashExplorerWeb.ErrorView)
    |> render(:"404", subject: subject)
  end
end
