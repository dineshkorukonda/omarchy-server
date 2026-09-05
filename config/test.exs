import Config

config :ssh_client, SSHClientWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "sshclienttestkeybase0000000000000000000000000000000000000000000000",
  live_view: [signing_salt: "sshclientlv"],
  server: false

config :logger, level: :warning
