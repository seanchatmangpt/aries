defmodule AriesPaaS.MixProject do
  use Mix.Project

  @version "26.8.26"
  @ash_r2rml_ref "067954ad406fd637fd47646bdb10c4580809c79d"

  def project do
    [
      app: :aries_paas,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:ash, "~> 3.0 and >= 3.28.0"},
      {:ash_r2rml,
       git: "https://github.com/seanchatmangpt/ash_r2rml.git", ref: @ash_r2rml_ref},
      {:reactor, ">= 0.9.0"},
      {:jason, "~> 1.4"}
    ]
  end
end
