defmodule SSHClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :ssh_client,
      version: "0.2.0",
      elixir: "~> 1.18 or ~> 1.19 or ~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :ssh],
      mod: {SSHClient.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:yaml_elixir, "~> 2.12"}
    ]
  end
end
