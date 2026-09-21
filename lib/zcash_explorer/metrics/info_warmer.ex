defmodule ZcashExplorer.Metrics.InfoWarmer do
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
    Rpc.getinfo() |> handle_result()
  end

  # ignores the warmer result in case of error
  defp handle_result({:error, reason}) do
    Logger.error("Error while warming the info cache: #{inspect(reason)}")
    :ignore
  end

  defp handle_result({:ok, info}) do
    {:ok, [{"info", info}]}
  end
end
