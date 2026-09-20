defmodule ZcashExplorerWeb.PageView do
  use ZcashExplorerWeb, :view

  # price/0 lived here reading a :price_cache that is never started, so it
  # raised on every call. Nothing referenced it.
end
