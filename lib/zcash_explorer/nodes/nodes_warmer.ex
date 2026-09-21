defmodule ZcashExplorer.Nodes.NodeWarmer do
  alias ZcashExplorer.Rpc
  use Cachex.Warmer
  require Logger

  @doc """
  Returns the interval for this warmer.
  """
  def interval,
    do: :timer.seconds(60)

  @doc """
  Executes this cache warmer.
  """
  def execute(_state) do
    Rpc.getpeerinfo() |> handle_result()
  end

  # ignores the warmer result in case of error
  defp handle_result({:error, reason}) do
    Logger.error("Error while warming the nodes cache: #{inspect(reason)}")
    :ignore
  end

  defp handle_result({:ok, nodes}) do
    {:ok, [{"zcash_nodes", nodes}]}
  end
end
