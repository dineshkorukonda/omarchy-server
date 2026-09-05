import Config

config :ssh_client, SSHClientWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  secret_key_base: "sshclientdevkeybase0000000000000000000000000000000000000000000000",
  live_view: [signing_salt: "sshclientlv"],
  debug_errors: true,
  code_reloader: false,
  watchers: []
