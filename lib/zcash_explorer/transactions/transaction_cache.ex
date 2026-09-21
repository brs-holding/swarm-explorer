defmodule ZcashExplorer.Transactions.TransactionWarmer do
  alias ZcashExplorer.Rpc
  alias ZcashExplorer.WarmerWindow
  use Cachex.Warmer
  require Logger

  @doc """
  Returns the interval for this warmer.

  SWARM change: was a hardcoded 15 s; see `ZcashExplorer.WarmerWindow`.
  """
  def interval, do: WarmerWindow.interval_ms()

  @doc """
  Executes this cache warmer.
  """
  def execute(_state) do
    case Rpc.getblockcount() do
      {:ok, n} ->
        # SWARM change: clamped window, so a short chain never asks for a
        # negative height.
        blocks =
          WarmerWindow.heights(n)
          |> Enum.map(fn x ->
            case Rpc.getblock(x, 2) do
              {:ok, block} -> block
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        blocks =
          blocks
          |> Enum.sort(&(&1["height"] >= &2["height"]))
          |> Enum.map(fn x ->
            x["tx"]
          end)
          |> List.flatten()

        blocks
        |> Enum.take(20)
        |> Enum.map(fn y ->
          case Rpc.getrawtransaction(y["txid"], 1) do
            {:ok, tx} -> Zcashex.Transaction.from_map(tx)
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn z ->
          %{
            "txid" => Map.get(z, :txid),
            "block_height" => Map.get(z, :height),
            "time" => ZcashExplorerWeb.BlockView.mined_time(Map.get(z, :time)),
            "tx_out_total" => ZcashExplorerWeb.BlockView.tx_out_total(z),
            "size" => Map.get(z, :size),
            "type" => ZcashExplorerWeb.BlockView.tx_type(z)
          }
        end)
        |> handle_result()

      {:error, reason} ->
        {:error, reason} |> handle_result()
    end
  end

  # ignores the warmer result in case of error
  defp handle_result({:error, reason}) do
    Logger.error("Error while warming the transaction cache. #{inspect(reason)}")
    :ignore
  end

  defp handle_result(info) do
    {:ok, [{"transaction_cache", info}]}
  end
end
