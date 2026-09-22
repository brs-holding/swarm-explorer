defmodule ZcashExplorerWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :zcash_explorer

  # The session is stored in the cookie and signed, so its contents can be read
  # but not tampered with.
  #
  # SWARM change: the signing salt is no longer a literal in this module. A
  # module attribute is compile-time, so upstream's value was frozen into the
  # release exactly like the two in config/config.exs were, and nobody running
  # the image could replace it. Everything that is not a secret stays here; the
  # salt comes from the application environment, which config/runtime.exs fills
  # from SESSION_SIGNING_SALT on every boot (and config/dev.exs and
  # config/test.exs give a throwaway local value).
  @session_options [
    store: :cookie,
    key: "_swarm_explorer_key"
  ]

  @doc """
  The session options, resolved at runtime.

  Both `Plug.Session` below and the LiveView socket read the session through
  this one function, so the salt they use can never drift apart. Phoenix
  resolves the socket's `{module, function, args}` form per connection.
  """
  def session_options do
    Keyword.merge(@session_options, Application.get_env(:zcash_explorer, :session_options, []))
  end

  socket "/socket", ZcashExplorerWeb.UserSocket,
    websocket: true,
    longpoll: false

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: {__MODULE__, :session_options, []}]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :zcash_explorer,
    gzip: true,
    only: ~w(css fonts images js favicon.ico robots.txt privacy.html)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  # A function plug rather than `plug Plug.Session, @session_options`: the
  # endpoint's plugs are initialised at compile time in :prod, which would
  # capture the salt again.
  plug :session
  plug ZcashExplorerWeb.Plugs.ConfigInjector
  plug ZcashExplorerWeb.Router

  defp session(conn, _opts), do: Plug.Session.call(conn, Plug.Session.init(session_options()))
end
