defmodule ZcashExplorer.NetworkProfileTest do
  @moduledoc """
  One image serves SwarmTestnet and the SWARM mainnet.

  The mainnet explorer went live on 2026-09-26 still printing "TEST COINS, NO
  VALUE" in the hero and "SWARM TESTNET — TEST COINS HAVE NO VALUE" in the
  footer, because both strings were literals in the templates with no switch
  reaching them. These tests pin the switch: which network the configuration
  describes, and what each template prints for it.

  `async: false` and the configuration is restored after each test: the
  network profile is application environment, which every other test reads.
  """
  use ExUnit.Case, async: false

  import Phoenix.View, only: [render_to_string: 3]

  alias ZcashExplorer.Swarm

  @key ZcashExplorer.Swarm

  setup do
    original = Application.get_env(:zcash_explorer, @key, [])
    on_exit(fn -> Application.put_env(:zcash_explorer, @key, original) end)
    {:ok, original: original}
  end

  defp configure(%{original: original}, overrides) do
    Application.put_env(:zcash_explorer, @key, Keyword.merge(original, overrides))
  end

  defp footer do
    render_to_string(ZcashExplorerWeb.LayoutView, "footer.html",
      project_name: Swarm.project_name(),
      network_name: Swarm.network_name()
    )
  end

  describe "network_kind/0" do
    test "the deployed names decide", ctx do
      configure(ctx, network_name: "SwarmMainnet")
      assert Swarm.network_kind() == :mainnet
      assert Swarm.mainnet?()

      configure(ctx, network_name: "SwarmTestnet")
      assert Swarm.network_kind() == :testnet
      refute Swarm.mainnet?()
    end

    test "a name that says neither stays a test network", ctx do
      # The warning is dropped only on a positive statement, so a missing or
      # misspelt SWARM_NETWORK_NAME cannot silently promise value.
      for name <- ["", "Swarm", "Regtest", "SwarmMian"] do
        configure(ctx, network_name: name)
        assert Swarm.network_kind() == :testnet, "#{inspect(name)} must not be mainnet"
      end
    end

    test "SWARM_NETWORK_KIND overrides the name", ctx do
      configure(ctx, network_name: "SwarmTestnet", network_kind: "mainnet")
      assert Swarm.mainnet?()

      configure(ctx, network_name: "SwarmMainnet", network_kind: "testnet")
      refute Swarm.mainnet?()
    end
  end

  describe "the footer" do
    test "a test network keeps today's wording exactly", ctx do
      configure(ctx, network_name: "SwarmTestnet")
      assert footer() =~ "SWARM TESTNET &mdash; TEST COINS HAVE NO VALUE"
    end

    test "the mainnet says Mainnet and promises nothing about value", ctx do
      configure(ctx, network_name: "SwarmMainnet")
      html = footer()

      assert html =~ "SWARM Mainnet"
      refute html =~ ~r/test coins/i
      refute html =~ ~r/testnet/i
      refute html =~ "NO VALUE"
    end

    test "the source link points at the organisation that owns the repository", ctx do
      configure(ctx, network_name: "SwarmMainnet")
      html = footer()

      assert html =~ "https://github.com/Swarm-Official"
      refute html =~ "brs-holding"
    end
  end
end
