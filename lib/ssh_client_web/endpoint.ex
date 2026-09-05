defmodule SSHClientWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :ssh_client

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_ssh_client_key",
    signing_salt: "sshclient1",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]
  socket "/socket", SSHClientWeb.UserSocket, websocket: true, longpoll: false

  # Serve static files from the /priv/static directory.
  plug Plug.Static,
    at: "/",
    from: :ssh_client,
    gzip: false,
    only: SSHClientWeb.static_paths()

  # Code reloading available in dev
  if code_reloading? do
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
  plug Plug.Session, @session_options
  plug SSHClientWeb.Router
end
