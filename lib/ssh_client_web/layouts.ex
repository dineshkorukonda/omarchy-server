defmodule SSHClientWeb.Layouts do
  @moduledoc false

  use Phoenix.Component

  import Phoenix.Controller, only: [get_csrf_token: 0]

  embed_templates "layouts/*"
end
