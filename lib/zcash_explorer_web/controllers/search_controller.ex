defmodule ZcashExplorerWeb.SearchController do
  alias ZcashExplorer.Rpc
  use ZcashExplorerWeb, :controller

  @moduledoc """
  The one search box, in the header of every page and in the hero.

  ## SWARM change

  Upstream asked the node four questions in parallel — `getblock`,
  `getrawtransaction`, `validateaddress`, `z_validateaddress` — and redirected
  to whichever answered first in a fixed order, block first. Two things were
  wrong with that:

    * Zebra reports a failed call as `{"result": null, "error": {...}}`, which
      `ZcashExplorer.Rpc` decoded as a *successful* `nil` (fixed there too), so
      `getblock` "succeeded" for anything at all and every query was sent to
      `/blocks/<query>`. A transparent address landed on the block page, which
      cannot parse one, and the visitor got HTTP 500 — and the three published
      allocation addresses are the most likely thing anyone searches for.
    * even with that fixed, the classification depended on a node round trip
      for input whose kind is obvious from its shape, so it failed differently
      whenever the node was slow or down.

  A query is now classified by shape first, which needs no node and is
  deterministic, and the node is consulted only for the one genuinely ambiguous
  case: 64 hex characters, which is both a block hash and a transaction id.
  Anything unrecognised renders a not-found page; nothing is redirected into a
  route that cannot parse it.
  """

  # Both networks' human-readable prefixes. SwarmTestnet uses testnet HRPs, so a
  # transparent address is "tm" (P2PKH) or "t2" (P2SH); the mainnet "t1"/"t3"
  # and the Sprout/Sapling forms are accepted too rather than 404ing a visitor
  # who pasted something from elsewhere — the address page says so if the node
  # does not know it.
  @transparent_prefixes ~w(t1 t2 t3 tm)
  @shielded_prefixes ~w(ztestsapling zs zc zt)
  @unified_prefixes ~w(utest1 u1)

  # A block hash and a transaction id are both this long, in hex.
  @hash_length 64

  # Long enough to exclude a stray word, short enough to exclude a paste of a
  # whole transaction. A unified address is the long end of this range.
  @address_lengths 20..512

  # No real height is longer than this; the guard keeps a digit string that is
  # obviously not a height out of the block route.
  @max_height_digits 12

  def search(conn, %{"qs" => qs}) when is_binary(qs) do
    query = String.trim(qs)

    case classify(query) do
      {:redirect, path} -> redirect(conn, to: path)
      {:hash, hash} -> resolve_hash(conn, hash)
      :unknown -> not_found(conn, query)
    end
  end

  def search(conn, _params), do: not_found(conn, "")

  @doc """
  What kind of thing a query looks like, from its shape alone.

  Returns `{:redirect, path}`, `{:hash, hash}` for the block-hash/transaction-id
  ambiguity, or `:unknown`. Public so the whole table of cases can be tested
  without a node.
  """
  def classify(qs) when is_binary(qs) do
    cond do
      # Before the height test: a hash of 64 digits is a hash, not a height.
      hash?(qs) -> {:hash, String.downcase(qs)}
      height?(qs) -> {:redirect, "/blocks/#{qs}"}
      address_like?(qs, @unified_prefixes) -> {:redirect, "/ua/#{qs}"}
      address_like?(qs, @shielded_prefixes) -> {:redirect, "/address/#{qs}"}
      address_like?(qs, @transparent_prefixes) -> {:redirect, "/address/#{qs}"}
      true -> :unknown
    end
  end

  def classify(_qs), do: :unknown

  # Only the node can tell a block hash from a transaction id. Asked in
  # parallel, as upstream did; if neither answers — or the node is unreachable
  # — the visitor gets the not-found page rather than a redirect into a page
  # that would fail.
  #
  # `getblockheader` and `getrawtransaction` at verbosity 1 are the two calls
  # the block listing and the transaction page already make, so they are known
  # to work against this node. Upstream asked `getblock`/`getrawtransaction` at
  # verbosity 0; whether Zebra serves those was never actually established,
  # because the decoder reported their failure as success.
  defp resolve_hash(conn, hash) do
    [block_resp, tx_resp] =
      [
        Task.async(fn -> Rpc.getblockheader(hash) end),
        Task.async(fn -> Rpc.getrawtransaction(hash, 1) end)
      ]
      |> Task.yield_many(5000)
      |> Enum.map(fn {task, res} ->
        case res || Task.shutdown(task, :brutal_kill) do
          {:ok, value} -> value
          _ -> {:error, :timeout}
        end
      end)

    cond do
      is_valid_block?(block_resp) -> redirect(conn, to: "/blocks/#{hash}")
      is_valid_tx?(tx_resp) -> redirect(conn, to: "/transactions/#{hash}")
      true -> not_found(conn, hash)
    end
  end

  defp not_found(conn, query) do
    conn
    |> put_status(:not_found)
    |> put_view(ZcashExplorerWeb.ErrorView)
    |> render(:invalid_input, query: query, page_title: "Nothing found")
  end

  defp height?(qs),
    do: String.length(qs) in 1..@max_height_digits and String.match?(qs, ~r/\A[0-9]+\z/)

  defp hash?(qs),
    do: String.length(qs) == @hash_length and String.match?(qs, ~r/\A[0-9a-fA-F]+\z/)

  # The charset test is not cosmetic: the query reaches a Location header, and
  # an address is base58 or bech32, so anything outside [0-9A-Za-z] is not one.
  defp address_like?(qs, prefixes) do
    String.length(qs) in @address_lengths and
      String.match?(qs, ~r/\A[0-9A-Za-z]+\z/) and
      Enum.any?(prefixes, &String.starts_with?(qs, &1))
  end

  # A node that answered with a result, rather than an error or nothing at all.
  # `{:ok, nil}` is what a failed call used to look like; it is excluded
  # explicitly so this cannot regress if a decoder ever does that again.
  def is_valid_block?({:ok, nil}), do: false
  def is_valid_block?({:ok, {:error, _reason}}), do: false
  def is_valid_block?({:ok, _hex}), do: true
  def is_valid_block?(_resp), do: false

  def is_valid_tx?({:ok, nil}), do: false
  def is_valid_tx?({:ok, {:error, _reason}}), do: false
  def is_valid_tx?({:ok, _hex}), do: true
  def is_valid_tx?(_resp), do: false

  # The search box no longer asks the node to validate an address — the shape
  # decides, and the address page reports what the node knows. These stay as
  # the tested reading of `validateaddress` / `z_validateaddress`, which differ
  # between zcashd and zebrad, for any caller that does ask.
  def is_valid_taddr?({:ok, %{"isvalid" => true}}), do: true
  def is_valid_taddr?(_resp), do: false

  # zcashd reported the address kind under "type"; zebrad uses "address_type".
  def is_valid_zaddr?({:ok, %{"isvalid" => true} = resp}),
    do: address_type(resp) in ["sprout", "sapling"]

  def is_valid_zaddr?(_resp), do: false

  def is_valid_unified_address?({:ok, %{"isvalid" => true} = resp}),
    do: address_type(resp) == "unified"

  def is_valid_unified_address?(_resp), do: false

  defp address_type(resp), do: resp["address_type"] || resp["type"]
end
