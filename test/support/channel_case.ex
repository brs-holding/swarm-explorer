defmodule ZcashExplorerWeb.ChannelCase do
  @moduledoc """
  The test case for channel tests.

  SWARM change: the Ecto SQL sandbox setup was removed along with the unused
  repository.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      import ZcashExplorerWeb.ChannelCase

      # The default endpoint for testing
      @endpoint ZcashExplorerWeb.Endpoint
    end
  end

  setup _tags do
    :ok
  end
end
