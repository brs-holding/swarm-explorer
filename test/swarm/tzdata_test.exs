defmodule ZcashExplorer.TzdataTest do
  @moduledoc """
  tzdata must not poll for a new timezone database.

  Left at its default, `Tzdata.ReleaseUpdater` asks IANA for a newer release and
  writes a marker into its own `priv` directory inside the release. The
  deployment runs the container with a read-only root filesystem, so the write
  can never succeed: the updater crashed, its supervisor restarted it, and it
  tried again three seconds later — 722 crashes in the first 36 minutes on
  image `brs-swarm-explorer:761d69298633`, roughly 1,200 log lines an hour,
  which evicted the rest of the log within days (workstream F, 2026-09-22).

  The setting is compile-time, so it is frozen into the release's `sys.config`;
  the first test is the one that reads this repository's configuration exactly
  as `mix release` resolves it for `:prod`. CI additionally boots the built
  image on a read-only filesystem and asserts that it logs no updater error at
  all in 25 seconds, which is eight polls at the old interval.
  """
  use ExUnit.Case, async: true

  test "the running application has the updater disabled" do
    assert Application.get_env(:tzdata, :autoupdate) == :disabled
  end

  for env <- [:prod, :dev, :test] do
    test "#{env} disables it in configuration a release would freeze" do
      config = Config.Reader.read!("config/config.exs", env: unquote(env))

      assert config[:tzdata][:autoupdate] == :disabled,
             "config/config.exs must set config :tzdata, :autoupdate, :disabled"
    end
  end

  test "block timestamps still format, which is all tzdata is used for" do
    # Timex reads the database compiled into the release; disabling the updater
    # must not take the database away with it.
    assert ZcashExplorerWeb.BlockView.mined_time(1_600_000_000) =~ "2020-09-13"
  end
end
