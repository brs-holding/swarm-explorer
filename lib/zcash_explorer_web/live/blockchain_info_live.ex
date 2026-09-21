defmodule ZcashExplorerWeb.BlockChainInfoLive do
  use ZcashExplorerWeb, :live_view
  import Phoenix.LiveView.Helpers
  @impl true
  def render(assigns) do
    ~L"""
    <div>
    <dl class="mt-5 grid grid-cols-1 gap-5 sm:grid-cols-3">
    <div class="px-4 py-5 bg-white shadow rounded-lg overflow-hidden sm:p-6 dark:bg-gray-800">
      <dt class="text-sm font-medium text-gray-500 truncate">
        Blocks
      </dt>
      <dd class="mt-1 text-3xl font-semibold text-gray-900 dark:text-white">
        <%= @blockchain_info["blocks"] %>
      </dd>
    </div>

    <div class="px-4 py-5 bg-white shadow rounded-lg overflow-hidden sm:p-6 dark:bg-gray-800">
      <dt class="text-sm font-medium text-gray-500 truncate">
        Difficulty
      </dt>
      <dd class="mt-1 text-3xl font-semibold text-gray-900 dark:text-white">
        <%= @blockchain_info["difficulty"] %>
      </dd>
    </div>

    <%= for {id, value} <- @pools do %>
      <div class="px-4 py-5 bg-white shadow rounded-lg overflow-hidden sm:p-6 dark:bg-gray-800">
        <dt class="text-sm font-medium text-gray-500 truncate capitalize">
          <%= id %> pool
        </dt>
        <dd class="mt-1 text-3xl font-semibold text-gray-900 dark:text-white">
          <%= value %> <%= @ticker %>
        </dd>
      </div>
    <% end %>

    <div class="px-4 py-5 bg-white shadow rounded-lg overflow-hidden sm:p-6 dark:bg-gray-800">
      <dt class="text-sm font-medium text-gray-500 truncate">
        Total supply issued
      </dt>
      <dd class="mt-1 text-3xl font-semibold text-gray-900 dark:text-white">
        <%= get_in(@blockchain_info, ["chainSupply", "chainValue"]) %> <%= @ticker %>
      </dd>
    </div>

    <div class="px-4 py-5 bg-white shadow rounded-lg overflow-hidden sm:p-6 dark:bg-gray-800">
      <dt class="text-sm font-medium text-gray-500 truncate">
        Server version
      </dt>
      <dd class="mt-1 text-3xl font-semibold text-gray-900 dark:text-white">
      <%= @blockchain_info["subversion"] %> <%= @blockchain_info["version"] %> <%= @blockchain_info["build"] %>
      </dd>
    </div>
    </dl>
    </div>


    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :update, 5000)

    case ZcashExplorer.Cache.fetch("metrics") do
      {:ok, info} ->
        {:ok, assign(socket, assigns_for(info))}

      {:error, _reason} ->
        {:ok, assign(socket, assigns_for(%{}))}
    end
  end

  defp assigns_for(info) do
    info = Map.put(info, "build", ZcashExplorer.Cache.field("info", "build"))

    [
      blockchain_info: info,
      pools: ZcashExplorer.Swarm.shielded_pools(info["valuePools"]),
      ticker: ZcashExplorer.Swarm.ticker()
    ]
  end

  @impl true
  def handle_info(:update, socket) do
    Process.send_after(self(), :update, 15000)
    {:noreply, assign(socket, assigns_for(ZcashExplorer.Cache.get("metrics", %{})))}
  end

end
