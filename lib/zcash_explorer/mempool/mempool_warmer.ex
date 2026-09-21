defmodule ZcashExplorer.Mempool.MempoolWarmer do
  alias ZcashExplorer.Rpc
  use Cachex.Warmer
  require Logger

  @doc """
  Returns the interval for this warmer.
  """
  def interval,
    do: :timer.seconds(5)

  @doc """
  Executes this cache warmer.
  """
  def execute(_state) do
    Rpc.getrawmempool(true) |> handle_result()
  end

  # ignores the warmer result in case of error
  defp handle_result({:error, reason}) do
    Logger.error("Error while warming the mempool cache: #{inspect(reason)}")
    :ignore
  end

  defp handle_result({:ok, raw_mempool}) do
    mempool_info = Enum.map(raw_mempool, fn {k, v} -> %{"txid" => k, "info" => v} end)
    {:ok, [{"raw_mempool", mempool_info}]}
  end
end
