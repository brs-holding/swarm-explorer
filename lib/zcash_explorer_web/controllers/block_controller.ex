defmodule ZcashExplorerWeb.BlockController do
  use ZcashExplorerWeb, :controller

  @default_limit 20

  def get_block(conn, %{"hash" => hash}) do
    case Zcashex.getblock(hash, 1) do
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
         {:ok, block_data} <- Zcashex.getblock(hash, 2) do
      block_data = Zcashex.Block.from_map(block_data)

      render(conn, "index.html",
        block_data: block_data,
        block_subsidy: nil,
        page_title: "Zcash block #{block_data.height}"
      )
    else
      _ ->
        render(conn, "basic_block.html",
          block_data: basic_block_data,
          page_title: "Zcash block #{hash}"
        )
    end
  end

  defp render_index(conn, from_block, limit, disable_previous) do
    to_block = max(from_block - limit, 0)
    max_concurrency = System.schedulers_online() * 2

    blocks_data =
      to_block..from_block
      # Every task funnels into the single Zcashex GenServer, so concurrency here
      # only queues work: 21 blocks routinely exceed async_stream's 5s default.
      # on_timeout: :kill_task is what lets the clause below drop a slow block
      # instead of exiting the request -- :exit, the default, kills the caller.
      |> Task.async_stream(&block_header/1,
        max_concurrency: max_concurrency,
        ordered: false,
        timeout: 20_000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, {:ok, header}} -> [header]
        _ -> []
      end)
      |> Enum.reverse()

    render(conn, "blocks.html",
      blocks_data: blocks_data,
      disable_next: from_block == 0,
      disable_previous: disable_previous,
      date: "",
      previous: from_block + limit,
      next: to_block,
      page_title: "Zcash latest blocks"
    )
  end

  # Verbosity 1 already carries the hash; verbosity 2 pulled every transaction
  # of every listed block just to read it.
  defp block_header(height) do
    with {:ok, %{"hash" => hash}} <- Zcashex.getblock(height, 1) do
      Zcashex.getblockheader(hash)
    end
  end

  # A Zcashex call that exceeds its GenServer timeout exits rather than
  # returning {:error, _}, so the case alone never saw it. The metrics warmer
  # refreshes this every 15s, which beats 404ing the block list over a blip.
  defp tip_height do
    case Zcashex.getblockcount() do
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
