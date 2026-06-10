defmodule Drone.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_drone,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: [
        main: "Drone",
        extras: [
          "docs/getting_started.md",
          "docs/safety.md",
          "docs/simulator.md",
          "docs/tello.md",
          "docs/architecture.md",
          "docs/adapter_authoring.md"
        ],
        source_url: "https://github.com/user/ex_drone",
        formatters: ["html", "epub"]
      ],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        sobelow: :dev
      ],
      source_url: "https://github.com/user/ex_drone",
      package: package(),
      description: "BEAM-native drone control for Elixir and Erlang."
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Drone.Application, []}
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 1.0"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      name: "ex_drone",
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE),
      licenses: ["MIT"],
      maintainers: ["Thanos Vassilakis"],
      links: %{"GitHub" => "https://github.com/user/ex_drone"}
    ]
  end
end
