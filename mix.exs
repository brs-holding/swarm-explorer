defmodule ZcashExplorer.MixProject do
  use Mix.Project

  # SWARM fork of nighthawk-apps/zcash → matiasurbieta/zcash-explorer.
  # The OTP application keeps the upstream name `:zcash_explorer` and the
  # `ZcashExplorer*` module namespace on purpose: renaming 120 files would bury
  # the adaptation in churn and make the diff against upstream unreadable.
  def project do
    [
      app: :zcash_explorer,
      version: "0.2.0-swarm",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {ZcashExplorer.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon, :cachex]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # SWARM changes:
  #   * removed `ecto_sql`, `postgrex`, `phoenix_ecto` and `ecto_psql_extras`.
  #     The repository was already commented out of the supervision tree
  #     upstream and nothing queried it, but its presence meant `mix test`
  #     tried to create a Postgres database before running. The explorer is
  #     stateless: everything it shows comes from the node.
  #   * removed `muontrap`, which only existed to shell out to
  #     `docker create nighthawkapps/vkrunner` for the Viewing Key page.
  #   * removed `contex`, which was only used by the deleted price chart.
  #   * `zcashex` stays for its Block/Transaction/VInTX decoders; the transport
  #     is `ZcashExplorer.Rpc` (cookie auth), not its GenServer.
  defp deps do
    [
      {:phoenix, "~> 1.6"},
      {:phoenix_html, "~> 3.2"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_dashboard, "~> 0.6.5"},
      {:telemetry_metrics, "~> 0.6.1"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.11"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.7"},
      {:httpoison, "~> 1.8"},
      {:poison, "~> 3.1"},
      {:observer_cli, "~> 1.6"},
      {:cachex, "~> 3.3"},
      {:phoenix_live_view, "~> 0.17.9"},
      {:floki, ">= 0.27.0", only: :test},
      {:zcashex, github: "matiasurbieta/zcashex", branch: "main"},
      {:timex, "~> 3.0"},
      {:sizeable, "~> 1.0"},
      {:eqrcode, "~> 0.1.8"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  defp aliases do
    [
      setup: ["deps.get", "cmd npm install --prefix assets"]
    ]
  end
end
