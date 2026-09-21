defmodule ZcashExplorerWeb.SearchController do
  alias ZcashExplorer.Rpc
  use ZcashExplorerWeb, :controller

  def search(conn, %{"qs" => qs}) do
    qs = String.trim(qs)
    # query zcashd to find out if the user has entered a valid resource
    # Valid resources:
    #  Block - height, hash
    #  Transaction - hash
    #  Address - Transparent , Shielded
    # If zcashd responds that a resource is valid, we redirect the user
    # to the appropriate resource view or redirect them to an error view.
    tasks = [
      Task.async(fn -> Rpc.getblock(qs, 0) end),
      Task.async(fn -> Rpc.getrawtransaction(qs, 0) end),
      Task.async(fn -> Rpc.validateaddress(qs) end),
      Task.async(fn -> Rpc.z_validateaddress(qs) end)
    ]

    # order in which the tasks are above defined matters. A task that neither
    # replied nor exited within the timeout yields nil, so unwrap defensively
    # instead of matching {:ok, _} and crashing the request.
    [block_resp, tx_resp, tadd_resp, zadd_resp] =
      tasks
      |> Task.yield_many(5000)
      |> Enum.map(fn {task, res} ->
        case res || Task.shutdown(task, :brutal_kill) do
          {:ok, value} -> value
          _ -> {:error, :timeout}
        end
      end)

    cond do
      is_valid_block?(block_resp) ->
        redirect(conn, to: "/blocks/#{qs}")

      is_valid_tx?(tx_resp) ->
        redirect(conn, to: "/transactions/#{qs}")

      is_valid_taddr?(tadd_resp) ->
        redirect(conn, to: "/address/#{qs}")

      is_valid_zaddr?(zadd_resp) ->
        redirect(conn, to: "/address/#{qs}")

      is_valid_unified_address?(zadd_resp) ->
        redirect(conn, to: "/ua/#{qs}")

      true ->
        conn
        |> put_status(:not_found)
        |> put_view(ZcashExplorerWeb.ErrorView)
        |> render(:invalid_input)
    end
  end

  def is_valid_block?({:ok, {:error, _reason}}), do: false
  def is_valid_block?({:ok, _hex}), do: true
  def is_valid_block?(_resp), do: false

  def is_valid_tx?({:ok, _hex}), do: true
  def is_valid_tx?(_resp), do: false

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
