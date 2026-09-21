defmodule ZcashExplorer.RpcTest do
  @moduledoc """
  The cookie handling in `ZcashExplorer.Rpc`.

  The rotation itself is exercised end to end in CI by restarting the Zebra
  container; this covers the parsing and the re-read, which is what breaks
  silently.
  """
  use ExUnit.Case, async: false

  alias ZcashExplorer.Rpc

  setup do
    dir = Path.join(System.tmp_dir!(), "swarm-rpc-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, ".cookie")
    original = Application.get_env(:zcash_explorer, Rpc, [])

    on_exit(fn ->
      Application.put_env(:zcash_explorer, Rpc, original)
      File.rm_rf(dir)
      :persistent_term.erase({Rpc, :credentials})
    end)

    %{dir: dir, path: path, original: original}
  end

  defp configure(original, overrides) do
    Application.put_env(:zcash_explorer, Rpc, Keyword.merge(original, overrides))
    :persistent_term.erase({Rpc, :credentials})
  end

  test "parses Zebra's `__cookie__:<secret>` file", %{path: path, original: original} do
    File.write!(path, "__cookie__:mVQ3oV2pPqf1yZK8kQmY6cS4uJt0bN9d")
    configure(original, cookie_path: path)

    assert Rpc.credentials() == {"__cookie__", "mVQ3oV2pPqf1yZK8kQmY6cS4uJt0bN9d"}
  end

  test "a secret containing base64 padding survives the split", %{path: path, original: original} do
    File.write!(path, "__cookie__:abc+def/ghi=\n")
    configure(original, cookie_path: path)

    assert {"__cookie__", "abc+def/ghi="} = Rpc.credentials()
  end

  test "refreshed_credentials/0 picks up a rotated secret", %{path: path, original: original} do
    File.write!(path, "__cookie__:first")
    configure(original, cookie_path: path)
    assert {"__cookie__", "first"} = Rpc.credentials()

    # Zebra writes a brand new secret on every start.
    File.write!(path, "__cookie__:second")
    assert {:ok, {"__cookie__", "second"}} = Rpc.refreshed_credentials()
    assert {"__cookie__", "second"} = Rpc.credentials()
  end

  test "falls back to the static credential when there is no cookie file",
       %{dir: dir, original: original} do
    configure(original,
      cookie_path: Path.join(dir, "absent"),
      username: "user",
      password: "pass"
    )

    assert Rpc.credentials() == {"user", "pass"}
  end

  test "no credential at all is :none rather than a crash", %{original: original} do
    configure(original, cookie_path: nil, username: nil, password: nil)
    assert Rpc.credentials() == :none
  end

  test "a malformed cookie file does not yield half a credential",
       %{path: path, original: original} do
    File.write!(path, "no-colon-here")
    configure(original, cookie_path: path, username: nil, password: nil)

    assert Rpc.credentials() == :none
  end

  test "an unreachable node returns an error tuple instead of raising",
       %{original: original} do
    configure(original, url: "http://127.0.0.1:1", cookie_path: nil, timeout: 200)

    assert {:error, message} = Rpc.call("getblockcount")
    assert is_binary(message)
  end
end
