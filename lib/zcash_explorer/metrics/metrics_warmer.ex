defmodule ZcashExplorer.Metrics.MetricsWarmer do
  alias ZcashExplorer.Rpc
  use Cachex.Warmer
  require Logger

  @doc """
  Returns the interval for this warmer.
  """
  def interval,
    do: :timer.seconds(15)

  @doc """
  Executes this cache warmer.
  """
  def execute(_state) do
    Rpc.getblockchaininfo() |> handle_result()
  end

  # ignores the warmer result in case of error
  defp handle_result({:error, reason}) do
    Logger.error("Error while warming the metrics cache: #{inspect(reason)}")
    :ignore
  end

  defp handle_result({:ok, info}) do
    {:ok, [{"metrics", info}]}
  end
end
