defmodule ZcashExplorerWeb.HealthTest do
  @moduledoc """
  The container healthcheck endpoint. It must answer 200 with no node
  reachable, otherwise a node restart would take the container down with it.
  """
  use ZcashExplorerWeb.ConnCase, async: true

  test "GET /healthz is 200 and reports the network even with no node", %{conn: conn} do
    conn = get(conn, "/healthz")
    body = json_response(conn, 200)

    assert body["status"] == "ok"
    assert body["network"] == "SwarmTestnet"
    assert body["ticker"] == "SWARM"
    # No warmer has run in the test environment, so readiness is honest.
    assert body["node"] == "unreachable"
  end

  test "routes for features Zebra cannot serve are gone", %{conn: conn} do
    for path <- ["/payment-disclosure", "/vk", "/price"] do
      assert_raise Phoenix.Router.NoRouteError, fn -> get(conn, path) end
    end
  end
end
