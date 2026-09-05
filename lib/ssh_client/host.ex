defmodule SSHClient.Host do
  @moduledoc """
  Data model representing an SSH host target.
  """

  @enforce_keys [:id, :name, :address, :port, :user]
  defstruct [
    :id,
    :name,
    :address,
    :port,
    :user,
    auth_method: :key,
    identity_file: nil,
    jump_host: nil,
    group: nil,
    auth_order: [:key, :password, :keyboard_interactive],
    connect_timeout: 10_000,
    poll_interval: 5_000,
    last_connected_at: nil
  ]

  @type auth_method :: :key | :password | :agent | :keyboard_interactive

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          address: String.t(),
          port: pos_integer(),
          user: String.t(),
          auth_method: auth_method(),
          identity_file: Path.t() | nil,
          jump_host: String.t() | nil,
          group: String.t() | nil,
          auth_order: list(atom()),
          connect_timeout: pos_integer(),
          poll_interval: pos_integer(),
          last_connected_at: DateTime.t() | nil
        }
end
