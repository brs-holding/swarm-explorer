defmodule ZcashExplorerWeb.ConnCase do
  @moduledoc """
  The test case for tests that need a connection.

  SWARM change: the Ecto SQL sandbox setup was removed along with the unused
  repository, so the suite runs with no database.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import ZcashExplorerWeb.ConnCase

      alias ZcashExplorerWeb.Router.Helpers, as: Routes

      # The default endpoint for testing
      @endpoint ZcashExplorerWeb.Endpoint
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
