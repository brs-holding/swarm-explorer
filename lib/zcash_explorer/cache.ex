defmodule ZcashExplorer.Cache do
  @moduledoc """
  Thin wrapper over the `:app_cache` warmers' output.

  `Cachex.get/2` answers `{:ok, nil}` for a key that was never warmed, so every
  `{:ok, value} = Cachex.get(...)` in this app succeeded with `nil` and blew up
  downstream — `length(nil)`, `nil["blocks"]`. The cache is cold on boot and
  stays cold while zebrad is syncing (the mempool warmer refuses to run until
  the node reaches the tip), so a resyncing node took the whole site down.
  """

  @default_cache :app_cache

  @doc """
  Like `Cachex.get/2` but reports a missing key as `{:error, :missing}`, which
  the existing `{:error, _reason}` branches already handle.
  """
  def fetch(key, cache \\ @default_cache) do
    case Cachex.get(cache, key) do
      {:ok, nil} -> {:error, :missing}
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "The cached value, or `default` when the key has not been warmed yet."
  def get(key, default \\ nil, cache \\ @default_cache) do
    case fetch(key, cache) do
      {:ok, value} -> value
      {:error, _reason} -> default
    end
  end

  @doc "One field of a cached map, or nil when either is missing."
  def field(key, field, cache \\ @default_cache) do
    case fetch(key, cache) do
      {:ok, %{} = map} -> Map.get(map, field)
      _ -> nil
    end
  end
end
