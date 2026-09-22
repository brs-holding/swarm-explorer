defmodule ZcashExplorer.Rpc do
  @moduledoc """
  JSON-RPC transport for a Zebra node, with cookie authentication.

  ## Why this exists (SWARM change)

  Upstream calls the node through the `Zcashex` GenServer, which captures the
  RPC username and password once in `start_link/4` and keeps them for the life
  of the process. Zebra does not use a static username and password: with
  `rpc.enable_cookie_auth = true` (its default) it writes a file `.cookie`
  containing `__cookie__:<secret>` and **generates a new secret on every
  start**. A captured credential therefore stops working the moment the node
  restarts, and the explorer would 401 until it was restarted too.

  This module keeps the `Zcashex` function names the application already calls,
  but reads the credential from disk at request time and, on an authentication
  failure, re-reads it once and retries. The secret is never logged and never
  rendered.

  `Zcashex` is still a dependency: its `Zcashex.Block`, `Zcashex.Transaction`
  and `Zcashex.VInTX` structs decode node replies and are used unchanged.

  ## Configuration

      config :zcash_explorer, ZcashExplorer.Rpc,
        url: "http://127.0.0.1:18232",
        cookie_path: "/zebra/.cookie",   # optional
        username: nil,                   # fallback when no cookie file
        password: nil,
        timeout: 120_000
  """

  require Logger

  @cache_key {__MODULE__, :credentials}

  # Zebra answers an unauthenticated request by failing the connection rather
  # than returning a clean 401 body (see the TODO in its
  # `HttpRequestMiddleware::call`), so a transport error is also treated as a
  # possible cookie rotation and triggers exactly one reload-and-retry.
  @auth_statuses [401, 403]

  @doc "Calls an RPC method with no parameters."
  def call(method), do: call(method, [])

  @doc """
  Calls an RPC method. Returns `{:ok, result}` or `{:error, reason}`.

  Retries once with a freshly read cookie when the first attempt looks like an
  authentication failure.
  """
  def call(method, params, timeout \\ nil) do
    case request(method, params, timeout, credentials()) do
      {:retry_auth, _reason} ->
        case refreshed_credentials() do
          {:ok, credentials} ->
            case request(method, params, timeout, credentials) do
              {:retry_auth, reason} -> {:error, reason}
              result -> result
            end

          :error ->
            {:error, "RPC authentication failed and no credential is available."}
        end

      result ->
        result
    end
  end

  defp request(method, params, timeout, credentials) do
    body =
      Poison.encode!(%{
        "jsonrpc" => "1.0",
        "id" => "swarm-explorer",
        "method" => method,
        "params" => params
      })

    options =
      [recv_timeout: timeout || config(:timeout, 120_000)]
      |> put_auth(credentials)

    case HTTPoison.post(url(), body, [{"Content-Type", "application/json"}], options) do
      {:ok, %HTTPoison.Response{status_code: status}} when status in @auth_statuses ->
        {:retry_auth, "RPC authentication rejected (HTTP #{status})."}

      {:ok, %HTTPoison.Response{body: response_body}} ->
        decode(response_body)

      {:error, %HTTPoison.Error{reason: reason}} ->
        # A rotated cookie surfaces here, not as a 401, so this is retried once.
        {:retry_auth, "RPC transport error: #{inspect(reason)}"}
    end
  end

  defp put_auth(options, {username, password})
       when is_binary(username) and is_binary(password) do
    Keyword.put(options, :hackney, basic_auth: {username, password})
  end

  defp put_auth(options, _), do: options

  @doc """
  Turns a JSON-RPC response body into `{:ok, result}` or `{:error, message}`.

  Public so the shapes below can be tested without a node; not part of the API
  this module offers the rest of the application.

  ## SWARM change

  The clause `{:ok, %{"result" => result, "error" => %{}}}` looked like "a
  result, and an empty error object". `%{}` in a *pattern* matches **any** map,
  so it also matched the shape Zebra returns for a failed call —
  `{"result": null, "error": {"code": -8, "message": "..."}}` — and every such
  error was reported to the caller as `{:ok, nil}`. That is why searching a
  transparent address ended at `/blocks/<address>`: `getblock` "succeeded".
  `map_size/1` in a guard says what was meant.
  """
  def decode(body) do
    case Poison.decode(body) do
      {:ok, %{"error" => nil, "result" => result}} ->
        {:ok, result}

      {:ok, %{"error" => error}} when is_map(error) and map_size(error) > 0 ->
        {:error, error_message(error)}

      {:ok, %{"error" => error}} when is_binary(error) and error != "" ->
        {:error, error}

      {:ok, %{"result" => result}} ->
        {:ok, result}

      _ ->
        {:error, "Unknown error."}
    end
  end

  defp error_message(%{"message" => message}) when is_binary(message) and message != "",
    do: message

  defp error_message(error), do: "RPC error: #{inspect(error)}"

  # --------------------------------------------------------------------------
  # Credentials
  # --------------------------------------------------------------------------

  @doc """
  The credential to present on the next request.

  Reads the cookie file whenever its size or mtime has changed since the last
  read, so a node restart is picked up without restarting the explorer and
  without a file read on every single RPC call.
  """
  def credentials do
    case cookie_path() do
      nil ->
        static_credentials()

      path ->
        stamp = stamp(path)

        case :persistent_term.get(@cache_key, nil) do
          {^stamp, credentials} ->
            credentials

          _ ->
            case read_cookie(path) do
              {:ok, credentials} ->
                :persistent_term.put(@cache_key, {stamp, credentials})
                credentials

              :error ->
                static_credentials()
            end
        end
    end
  end

  @doc "Forces a re-read of the cookie file, ignoring the cached stamp."
  def refreshed_credentials do
    with path when is_binary(path) <- cookie_path(),
         {:ok, credentials} <- read_cookie(path) do
      :persistent_term.put(@cache_key, {stamp(path), credentials})
      Logger.info("Reloaded the Zebra RPC cookie from #{path}")
      {:ok, credentials}
    else
      _ ->
        case static_credentials() do
          {username, password} when is_binary(username) and is_binary(password) ->
            {:ok, {username, password}}

          _ ->
            :error
        end
    end
  end

  # The cookie file holds exactly `__cookie__:<secret>`. Zebra checks the part
  # after the first colon, and its base64 secret never contains one.
  defp read_cookie(path) do
    case File.read(path) do
      {:ok, contents} ->
        case String.split(String.trim(contents), ":", parts: 2) do
          [username, password] when password != "" -> {:ok, {username, password}}
          _ -> :error
        end

      {:error, reason} ->
        # The path, never the contents.
        Logger.warning("Could not read the RPC cookie at #{path}: #{inspect(reason)}")
        :error
    end
  end

  defp stamp(path) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime, size: size}} -> {mtime, size}
      _ -> :missing
    end
  end

  defp static_credentials do
    case {config(:username, nil), config(:password, nil)} do
      {username, password} when is_binary(username) and is_binary(password) and username != "" ->
        {username, password}

      _ ->
        :none
    end
  end

  defp cookie_path do
    case config(:cookie_path, nil) do
      path when is_binary(path) and path != "" -> path
      _ -> nil
    end
  end

  defp url do
    config(:url, nil) ||
      "http://#{config(:hostname, "127.0.0.1")}:#{config(:port, 18_232)}"
  end

  defp config(key, default) do
    Application.get_env(:zcash_explorer, __MODULE__, [])
    |> Keyword.get(key, default)
  end

  # --------------------------------------------------------------------------
  # Methods used by this application.
  #
  # Names and arities match the `Zcashex` functions they replace, so the call
  # sites elsewhere in the app only changed module. Method coverage is the
  # subset Zebra serves; `z_validatepaymentdisclosure` is deliberately absent
  # because Zebra has no such RPC.
  # --------------------------------------------------------------------------

  def getinfo, do: call("getinfo")
  def getblockchaininfo, do: call("getblockchaininfo")
  def getblockcount, do: call("getblockcount")
  def getpeerinfo, do: call("getpeerinfo")
  def getmempoolinfo, do: call("getmempoolinfo")
  def getdifficulty, do: call("getdifficulty")
  def getbestblockhash, do: call("getbestblockhash")

  def getblock(hash, verbosity) when is_binary(hash) and verbosity in 0..2,
    do: call("getblock", [hash, verbosity])

  def getblock(height, verbosity) when is_integer(height) and verbosity in 0..2,
    do: call("getblock", [Integer.to_string(height), verbosity])

  def getblockheader(hash), do: call("getblockheader", [hash])

  def getblocksubsidy, do: call("getblocksubsidy")
  def getblocksubsidy(height) when is_integer(height), do: call("getblocksubsidy", [height])

  def getnetworksolps(blocks \\ 120, height \\ -1),
    do: call("getnetworksolps", [blocks, height])

  def getrawmempool(verbose \\ true), do: call("getrawmempool", [verbose])

  def getrawtransaction(txid, verbosity \\ 1),
    do: call("getrawtransaction", [txid, verbosity])

  def sendrawtransaction(hex), do: call("sendrawtransaction", [hex])

  def validateaddress(address), do: call("validateaddress", [address])
  def z_validateaddress(address), do: call("z_validateaddress", [address])
  def z_listunifiedreceivers(unified_address), do: call("z_listunifiedreceivers", [unified_address])

  def getaddressbalance(address) when is_binary(address),
    do: getaddressbalance([address])

  def getaddressbalance(addresses) when is_list(addresses),
    do: call("getaddressbalance", [%{"addresses" => addresses}])

  def getaddresstxids(address, start_block \\ nil, end_block \\ nil) do
    call("getaddresstxids", [
      %{"addresses" => [address], "start" => start_block, "end" => end_block}
    ])
  end
end
