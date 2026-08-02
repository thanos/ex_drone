defmodule Drone.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_drone,
      version: "0.3.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: docs(),
      test_coverage: [
        tool: ExCoveralls,
        ignore_modules: [FakeTelloServer, Drone.Test.MoxHelpers]
      ],
      source_url: "https://github.com/thanos/ex_drone",
      package: package(),
      description: "BEAM-native drone control for Elixir and Erlang.",
      aliases: [
        verify: &verify/1
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        sobelow: :dev
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Drone.Application, []}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "docs/getting_started.md": [title: "Getting Started"],
        "docs/safety.md": [title: "Safety"],
        "docs/simulator.md": [title: "Simulator"],
        "docs/tello.md": [title: "Tello"],
        "docs/crazyflie.md": [title: "Crazyflie"],
        "docs/swarm.md": [title: "Swarms"],
        "docs/formations.md": [title: "Formations"],
        "docs/architecture.md": [title: "Architecture"],
        "docs/adapter_authoring.md": [title: "Adapter Authoring"],
        "docs/further_reading.md": [title: "Further Reading"],
        "docs/design/adapter_contract.md": [title: "Adapter Contract"],
        "docs/design/safety_pipeline.md": [title: "Safety Pipeline"],
        "docs/design/telemetry_events.md": [title: "Telemetry Events"],
        "docs/design/v0_2_0_deferred.md": [title: "v0.2.0 Deferred Work"],
        "docs/research/tello_sdk.md": [title: "Tello SDK"],
        "docs/research/beam_udp.md": [title: "BEAM UDP"],
        "docs/research/safety_model.md": [title: "Safety Model"],
        "docs/research/simulator_design.md": [title: "Simulator Design"],
        "docs/research/swarm_coordination.md": [title: "Swarm Coordination"]
      ],
      groups_for_extras: [
        Guides: [
          "docs/getting_started.md",
          "docs/safety.md",
          "docs/simulator.md",
          "docs/tello.md",
          "docs/crazyflie.md",
          "docs/swarm.md",
          "docs/formations.md",
          "docs/architecture.md",
          "docs/adapter_authoring.md",
          "docs/further_reading.md"
        ],
        Design: [
          "docs/design/adapter_contract.md",
          "docs/design/safety_pipeline.md",
          "docs/design/telemetry_events.md",
          "docs/design/v0_2_0_deferred.md"
        ],
        Research: [
          "docs/research/tello_sdk.md",
          "docs/research/beam_udp.md",
          "docs/research/safety_model.md",
          "docs/research/simulator_design.md",
          "docs/research/swarm_coordination.md"
        ]
      ],
      skip_undefined_reference_warnings_on: ["README.md", "CHANGELOG.md"],
      source_url: "https://github.com/thanos/ex_drone",
      formatters: ["html", "epub"]
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 1.0"},
      {:mox, "~> 1.1", only: :test},
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
      files: ~w(lib docs .formatter.exs mix.exs README.md CHANGELOG.md LICENSE),
      licenses: ["MIT"],
      maintainers: ["Thanos Vassilakis"],
      links: %{
        "GitHub" => "https://github.com/thanos/ex_drone",
        "Changelog" => "https://hexdocs.pm/ex_drone/changelog.html",
        "Further Reading" => "https://hexdocs.pm/ex_drone/further_reading.html"
      }
    ]
  end

  defp verify(_) do
    steps = [
      {"compile --warnings-as-errors", :dev},
      {"format --check-formatted", :dev},
      {"credo --strict", :dev},
      {"dialyzer", :dev},
      {"test --cover", :test},
      {"docs --warnings-as-errors", :dev}
    ]

    Enum.each(steps, fn {task, env} ->
      Mix.shell().info([:bright, "==> mix #{task}", :reset])

      {_, exit_code} =
        System.cmd("mix", String.split(task),
          env: [{"MIX_ENV", to_string(env)}],
          into: IO.stream()
        )

      if exit_code != 0 do
        Mix.raise("mix #{task} failed (exit code #{exit_code})")
      end
    end)

    Mix.shell().info([:green, :bright, "\nAll verification checks passed!", :reset])
  end
end
