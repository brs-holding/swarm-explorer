defmodule ZcashExplorerWeb.SearchTest do
  @moduledoc """
  Searching a transparent address used to return HTTP 500.

  `/search?qs=t2DGVURG5tAyXXSkj85JV5xbvTobYv7H99n` redirected to
  `/blocks/t2DGVURG5tAyXXSkj85JV5xbvTobYv7H99n`, which cannot parse an address
  as a height or a hash and crashed rendering it, while `/address/<the same>`
  worked (workstream F, 2026-09-21, against the live SwarmTestnet). The address
  in that report is Core Development, one of the three published allocation
  destinations, paid in every block — the likeliest thing a visitor searches.

  No node is reachable in the test environment (`config/test.exs` points the
  RPC at a closed port with a 200 ms timeout), which is the point: everything a
  visitor is likely to type must be classified without asking one, and anything
  that does need the node must degrade to a page, never to a 500. The cases
  that genuinely need a node — a real hash, a real txid — are asserted against
  a live Zebra in the end-to-end CI job.
  """
  use ZcashExplorerWeb.ConnCase, async: true

  alias ZcashExplorer.Rpc
  alias ZcashExplorerWeb.SearchController

  # The address from the defect report, and one of each other kind.
  @taddr "t2DGVURG5tAyXXSkj85JV5xbvTobYv7H99n"
  @tm_addr "tmFPcPUjvLNtgqnVgUVCbRJnhuxtMvKrDkV"
  @zaddr "ztestsapling1ttkqqqqpqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
  @uaddr "utest1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
  @swarm_addr "swarm1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
  @hash "045993f5a9c1cc80e1f0e1b9e0d5f2ae9d4b3c2a1908f7e6d5c4b3a291807f6e"

  describe "classification, which needs no node" do
    test "both unified prefix forms reach their address detail route" do
      for address <- [@uaddr, @swarm_addr] do
        assert SearchController.classify(address) == {:redirect, "/ua/#{address}"}
      end
    end

    test "a transparent address goes to the address page, not the block page" do
      assert SearchController.classify(@taddr) == {:redirect, "/address/#{@taddr}"}
      assert SearchController.classify(@tm_addr) == {:redirect, "/address/#{@tm_addr}"}
    end

    test "a shielded address goes to the address page" do
      assert SearchController.classify(@zaddr) == {:redirect, "/address/#{@zaddr}"}
    end

    test "a unified address goes to the unified page" do
      assert SearchController.classify(@uaddr) == {:redirect, "/ua/#{@uaddr}"}
    end

    test "a height goes to the block page" do
      assert SearchController.classify("0") == {:redirect, "/blocks/0"}
      assert SearchController.classify("12") == {:redirect, "/blocks/12"}
      assert SearchController.classify("1680000") == {:redirect, "/blocks/1680000"}
    end

    test "64 hex characters are ambiguous and left to the node" do
      assert SearchController.classify(@hash) == {:hash, @hash}
      assert SearchController.classify(String.upcase(@hash)) == {:hash, @hash}
    end

    test "64 digits are a hash, not an impossible height" do
      digits = String.duplicate("1", 64)
      assert SearchController.classify(digits) == {:hash, digits}
    end

    test "nothing else is classified" do
      for query <- [
            "",
            "   ",
            "hello",
            "t2",
            "tt1abcdefghijklmnopqrstuvwxyz012345",
            # 63 and 65 hex characters
            String.slice(@hash, 0..62),
            @hash <> "a",
            # a height no chain will ever reach
            String.duplicate("9", 40),
            # anything that could reach a Location header
            "t2abc/../../etc/passwd",
            "t2abc\nSet-Cookie: x=1",
            "t2abc?x=1",
            "<script>alert(1)</script>"
          ] do
        assert SearchController.classify(String.trim(query)) == :unknown,
               "#{inspect(query)} was classified as something"
      end
    end
  end

  describe "GET /search" do
    test "the address from the defect report redirects to /address", %{conn: conn} do
      conn = get(conn, "/search", qs: @taddr)

      assert redirected_to(conn, 302) == "/address/#{@taddr}"
    end

    test "whitespace around a pasted address is ignored", %{conn: conn} do
      conn = get(conn, "/search", qs: "  #{@taddr}\n")

      assert redirected_to(conn, 302) == "/address/#{@taddr}"
    end

    test "a height still redirects to the block page", %{conn: conn} do
      conn = get(conn, "/search", qs: "12")

      assert redirected_to(conn, 302) == "/blocks/12"
    end

    test "a unified address redirects to the unified page", %{conn: conn} do
      conn = get(conn, "/search", qs: @uaddr)

      assert redirected_to(conn, 302) == "/ua/#{@uaddr}"
    end

    test "a hash the node cannot confirm is a page, not a redirect", %{conn: conn} do
      conn = get(conn, "/search", qs: @hash)

      assert html_response(conn, 404) =~ "That does not look like anything on this chain."
    end

    test "an unrecognised query renders the not-found page and echoes it", %{conn: conn} do
      conn = get(conn, "/search", qs: "not a thing")

      body = html_response(conn, 404)
      assert body =~ "That does not look like anything on this chain."
      assert body =~ "not a thing"
    end

    test "the not-found page offers the search box again", %{conn: conn} do
      body = conn |> get("/search", qs: "nope") |> html_response(404)

      assert body =~ ~s(action="/search")
      assert body =~ "a block height"
    end

    test "an empty or missing query is a page, not a crash", %{conn: conn} do
      assert conn |> get("/search", qs: "") |> html_response(404) =~ "NOTHING FOUND"
      assert conn |> get("/search") |> html_response(404) =~ "NOTHING FOUND"
    end

    test "a query that is not a string is a page, not a crash", %{conn: conn} do
      assert conn |> get("/search?qs[]=1") |> html_response(404) =~ "NOTHING FOUND"
    end
  end

  describe "the routes a search leads to" do
    test "/blocks/<transparent address> is 404, never 500", %{conn: conn} do
      assert conn |> get("/blocks/#{@taddr}") |> html_response(404) =~ "NOTHING FOUND"
    end

    test "/blocks/<garbage> is 404, never 500", %{conn: conn} do
      assert conn |> get("/blocks/not-a-block") |> html_response(404) =~ "NOTHING FOUND"
    end

    test "/address/<transparent address> with no node is 404, never 500", %{conn: conn} do
      body = conn |> get("/address/#{@taddr}") |> html_response(404)

      assert body =~ "NOTHING FOUND"
      assert body =~ @taddr
    end

    test "both unified forms fail gracefully when the node is unavailable", %{conn: conn} do
      for address <- [@uaddr, @swarm_addr], route <- ["ua", "address"] do
        assert conn |> get("/#{route}/#{address}") |> html_response(404) =~ "NOTHING FOUND"
      end
    end

    test "/transactions/<64 hex> with no node is 404, never 500", %{conn: conn} do
      assert conn |> get("/transactions/#{@hash}") |> html_response(404) =~ "Transaction Not Found"
    end
  end

  describe "ZcashExplorer.Rpc.decode/1, the root cause" do
    test "Zebra's error reply is an error, not a successful nil" do
      body = ~s({"result":null,"error":{"code":-8,"message":"parse error"},"id":"swarm-explorer"})

      assert Rpc.decode(body) == {:error, "parse error"}
    end

    test "an error object with no message is still an error" do
      assert {:error, message} = Rpc.decode(~s({"result":null,"error":{"code":-8}}))
      assert is_binary(message)
    end

    test "an error reply with no result key is an error" do
      body = ~s({"jsonrpc":"2.0","error":{"code":-32601,"message":"method not found"},"id":1})

      assert Rpc.decode(body) == {:error, "method not found"}
    end

    test "a success is still a success" do
      assert Rpc.decode(~s({"result":42,"error":null,"id":1})) == {:ok, 42}
      assert Rpc.decode(~s({"result":{"height":7},"error":{}})) == {:ok, %{"height" => 7}}
      assert Rpc.decode(~s({"result":"deadbeef"})) == {:ok, "deadbeef"}
    end

    test "a body that is not JSON is an error" do
      assert {:error, _} = Rpc.decode("<html>502 Bad Gateway</html>")
    end

    test "the shape that used to reach the block page is rejected there too" do
      refute SearchController.is_valid_block?({:ok, nil})
      refute SearchController.is_valid_tx?({:ok, nil})
    end
  end
end
