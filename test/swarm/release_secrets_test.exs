defmodule ZcashExplorer.ReleaseSecretsTest do
  @moduledoc """
  The built image must carry no Phoenix secret.

  Upstream set `secret_key_base` and the LiveView `signing_salt` in
  `config/config.exs`, and the session `signing_salt` in a module attribute of
  the endpoint. All three are compile-time, so a release froze published
  development values into `sys.config` and into the beam, and whoever ran the
  image could not replace them (workstream F, image
  `brs-swarm-explorer:7834a2232fd6`).

  `mix release` builds `sys.config` by reading `config/config.exs` with
  `env: :prod`, which is exactly what the first group below does — so these
  assertions are about the artifact, not about a copy of it. CI then repeats
  the check byte by byte against the `sys.config` inside the image that is
  actually shipped; see `ci/check-release-secrets.py`.
  """
  use ExUnit.Case, async: false

  @secret_env ~w(SECRET_KEY_BASE SESSION_SIGNING_SALT LIVE_VIEW_SIGNING_SALT)

  setup do
    saved = Map.new(@secret_env, fn name -> {name, System.get_env(name)} end)

    on_exit(fn ->
      Enum.each(saved, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # What a release freezes
  # ---------------------------------------------------------------------------

  describe "compile-time configuration" do
    test ":prod carries no secret at all" do
      config = read!("config/config.exs", :prod)
      endpoint = config[:zcash_explorer][ZcashExplorerWeb.Endpoint]

      refute Keyword.has_key?(endpoint, :secret_key_base),
             "config/config.exs still sets secret_key_base for a release"

      refute endpoint[:live_view][:signing_salt],
             "config/config.exs still sets the LiveView signing_salt for a release"

      refute config[:zcash_explorer][:session_options],
             "the session options still carry a build-time value"
    end

    test ":prod still configures everything that is not a secret" do
      endpoint = read!("config/config.exs", :prod)[:zcash_explorer][ZcashExplorerWeb.Endpoint]

      assert endpoint[:pubsub_server] == ZcashExplorer.PubSub
      assert endpoint[:render_errors][:view] == ZcashExplorerWeb.ErrorView
      assert endpoint[:cache_static_manifest] == "priv/static/cache_manifest.json"
    end

    for env <- [:dev, :test] do
      test "#{env} keeps its own throwaway values, so a local run still works" do
        config = read!("config/config.exs", unquote(env))
        endpoint = config[:zcash_explorer][ZcashExplorerWeb.Endpoint]

        assert byte_size(endpoint[:secret_key_base]) >= 64
        assert is_binary(endpoint[:live_view][:signing_salt])
        assert is_binary(config[:zcash_explorer][:session_options][:signing_salt])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # What the release reads at boot
  # ---------------------------------------------------------------------------

  describe "config/runtime.exs in :prod" do
    test "supplies all three from the environment" do
      System.put_env("SECRET_KEY_BASE", String.duplicate("s", 64))
      System.put_env("SESSION_SIGNING_SALT", "session-salt-from-the-environment")
      System.put_env("LIVE_VIEW_SIGNING_SALT", "live-view-salt-from-the-environment")

      config = read_runtime!()
      endpoint = config[:zcash_explorer][ZcashExplorerWeb.Endpoint]

      assert endpoint[:secret_key_base] == String.duplicate("s", 64)
      assert endpoint[:live_view][:signing_salt] == "live-view-salt-from-the-environment"

      assert config[:zcash_explorer][:session_options][:signing_salt] ==
               "session-salt-from-the-environment"
    end

    for name <- @secret_env do
      test "refuses to boot without #{name}" do
        set_all()
        System.delete_env(unquote(name))

        assert boot_failure() =~ unquote(name)
      end

      test "refuses to boot when #{name} is empty" do
        set_all()
        System.put_env(unquote(name), "")

        assert boot_failure() =~ unquote(name)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # What the running endpoint uses
  # ---------------------------------------------------------------------------

  describe "ZcashExplorerWeb.Endpoint.session_options/0" do
    test "is read at runtime and is complete" do
      options = ZcashExplorerWeb.Endpoint.session_options()

      assert options[:store] == :cookie
      assert options[:key] == "_swarm_explorer_key"
      assert is_binary(options[:signing_salt]) and options[:signing_salt] != ""
    end

    test "builds a session plug, which is what the LiveView socket also resolves" do
      assert %{store: Plug.Session.COOKIE} =
               Plug.Session.init(ZcashExplorerWeb.Endpoint.session_options())
    end
  end

  # ---------------------------------------------------------------------------
  # The checker CI runs against the image
  # ---------------------------------------------------------------------------

  describe "ci/check-release-secrets.py" do
    test "proves its own byte comparison" do
      {output, status} = checker(["--self-test"])

      assert status == 0, output
      assert output =~ "self-test passed"
      # The false negative that made this defect look fixed when it was not.
      assert output =~ "defeat a literal grep"
    end

    test "finds none of upstream's values anywhere in lib/ or config/" do
      {output, status} = checker(["lib", "config"])

      assert status == 0, output
    end
  end

  # ---------------------------------------------------------------------------

  defp read!(file, env), do: Config.Reader.read!(file, env: env)

  # runtime.exs prints a summary line on every boot; the test only wants the
  # configuration it produced.
  defp read_runtime! do
    parent = self()

    ExUnit.CaptureIO.capture_io(fn ->
      send(parent, {:runtime_config, read!("config/runtime.exs", :prod)})
    end)

    receive do
      {:runtime_config, config} -> config
    after
      0 -> flunk("config/runtime.exs produced nothing")
    end
  end

  # The exception type is not the point — the message naming the variable is.
  # The flunk is outside the rescue so it cannot be caught by it.
  defp boot_failure do
    outcome =
      try do
        read_runtime!()
        :booted
      rescue
        error -> {:raised, Exception.message(error)}
      end

    case outcome do
      {:raised, message} -> message
      :booted -> flunk("config/runtime.exs booted with a secret missing")
    end
  end

  defp set_all do
    System.put_env("SECRET_KEY_BASE", String.duplicate("s", 64))
    System.put_env("SESSION_SIGNING_SALT", "session-salt")
    System.put_env("LIVE_VIEW_SIGNING_SALT", "live-view-salt")
  end

  defp checker(args) do
    python =
      System.find_executable("python3") || System.find_executable("python") ||
        flunk("no python3 on PATH; ci/check-release-secrets.py cannot be exercised")

    System.cmd(python, ["ci/check-release-secrets.py" | args], stderr_to_stdout: true)
  end
end
