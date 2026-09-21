defmodule ZcashExplorer.Blocks.BlockWarmer do
  alias ZcashExplorer.Rpc
  alias ZcashExplorer.WarmerWindow
  use Cachex.Warmer
  require Logger

  @doc """
  Returns the interval for this warmer.

  SWARM change: was a hardcoded 15 s. At 75-second blocks that refetched the
  same 21 blocks five times per block produced; see `ZcashExplorer.WarmerWindow`.
  """
  def interval, do: WarmerWindow.interval_ms()

  @doc """
  Executes this cache warmer.
  """
  def execute(_state) do
    # get the blocks mined in that duration
    case Rpc.getblockcount() do
      {:ok, n} ->
        # SWARM change: the window is clamped at height 0, so a chain shorter
        # than the window (including heights 0-10) does not ask the node for
        # negative heights.
        blocks =
          WarmerWindow.heights(n)
          |> Enum.map(fn x ->
            case Rpc.getblock(x, 2) do
              {:ok, block} -> block
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        blocks
        |> Enum.map(fn x ->
          block_struct = Zcashex.Block.from_map(x)

          %{
            "height" => block_struct.height,
            "size" => block_struct.size,
            "hash" => block_struct.hash,
            "time" => ZcashExplorerWeb.BlockView.mined_time(block_struct.time),
            "tx_count" => ZcashExplorerWeb.BlockView.transaction_count(block_struct.tx),
            "output_total" => ZcashExplorerWeb.BlockView.output_total(block_struct.tx)
          }
        end)
        |> Enum.sort(&(&1["height"] >= &2["height"]))
        |> handle_result()

      {:error, reason} ->
        {:error, reason} |> handle_result()
    end
  end

  # ignores the warmer result in case of error
  defp handle_result({:error, reason}) do
    Logger.error("Error while warming the block cache.#{inspect(reason)}")
    :ignore
  end

  defp handle_result(info) do
    {:ok, [{"block_cache", info}]}
  end
end
