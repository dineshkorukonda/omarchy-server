defmodule OmarchyServer.Config.Check do
  @moduledoc """
  Specifies a service check to run on a managed server.
  """

  @enforce_keys [:type, :name]
  defstruct [:type, :name]

  @type check_type :: :systemctl | :pm2 | :docker | atom()
  @type t :: %__MODULE__{
          type: check_type(),
          name: String.t()
        }

  @valid_types ["systemctl", "pm2", "docker"]

  @doc """
  Builds and validates a Check struct from raw configuration data.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(%{"type" => type, "name" => name})
      when is_binary(type) and is_binary(name) and byte_size(name) > 0 do
    if type in @valid_types do
      {:ok, %__MODULE__{type: String.to_atom(type), name: name}}
    else
      {:error,
       "unsupported check type '#{type}'; supported types: #{Enum.join(@valid_types, ", ")}"}
    end
  end

  def from_map(%{"type" => _type}) do
    {:error, "check is missing a valid 'name'"}
  end

  def from_map(%{"name" => _name}) do
    {:error, "check is missing a valid 'type'"}
  end

  def from_map(invalid) when is_map(invalid) do
    {:error, "check must specify 'type' and 'name'"}
  end

  def from_map(_other) do
    {:error, "check must be a map"}
  end
end
