# ex_drone

[![Hex version](https://img.shields.io/hexpm/v/ex_data_sketch.svg)](https://hex.pm/packages/ex_drone)
[![Hex docs](https://img.shields.io/badge/docs-hexdocs.pm-blue)](https://hexdocs.pm/ex_drone)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/thanos/ex_drone/actions/workflows/ci.yml/badge.svg)](https://github.com/thanos/ex_drone/actions/workflows/ci.yml) [![Coverage Status](https://coveralls.io/repos/github/thanos/ex_drone/badge.svg?branch=main)](https://coveralls.io/github/thanos/ex_drone?branch=main)

BEAM-native drone control for Elixir and Erlang. Fly, monitor, and simulate programmable drones using supervised processes, telemetry, and missions.

## Safety Warning

**Drones are physical devices that can cause injury or property damage.**

- Do not fly near faces or people
- Use prop guards at all times
- Test in the simulator before connecting to real hardware
- Use open indoor spaces or outdoor areas with clear lines of sight
- Have an emergency stop ready at all times
- Understand and follow local laws and regulations

## Installation

Add `ex_drone` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_drone, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Connect to the simulator (no hardware needed)
{:ok, drone} = Drone.connect(:sim, name: :my_drone)

# Enter SDK mode
Drone.connect_sdk(drone)

# Fly
Drone.takeoff(drone)
Drone.move(drone, :up, 40)
Drone.move(drone, :forward, 100)
Drone.rotate(drone, :cw, 90)
Drone.land(drone)

# Disconnect
Drone.disconnect(drone)
```

## Safety Policies

All commands pass through a safety pipeline before reaching the drone:

```elixir
# Indoor flight with tight limits
{:ok, drone} = Drone.connect(:sim, name: :classroom, safety: [indoor: true])

# Custom safety limits
{:ok, drone} = Drone.connect(:sim, name: :safe,
  safety: [
    max_altitude_cm: 200,
    max_distance_cm: 500,
    prop_guards: true
  ]
)

# Dry-run mode (validates commands without sending)
{:ok, drone} = Drone.connect(:sim, name: :test, safety: [dry_run: true])
```

See `Drone.Safety.Policy` for all safety options.

## Tello Connection

```elixir
{:ok, drone} = Drone.connect(:tello, name: :tello_1)
Drone.connect_sdk(drone)
Drone.takeoff(drone)
Drone.land(drone)
Drone.disconnect(drone)
```

## Mission Scripts

```elixir
mission =
  Drone.Mission.new()
  |> Drone.Mission.sdk_mode()
  |> Drone.Mission.takeoff()
  |> Drone.Mission.move(:up, 40)
  |> Drone.Mission.rotate(:cw, 90)
  |> Drone.Mission.land()

{:ok, results} = Drone.Mission.run(mission, :my_drone)
```

## Architecture

- **Drone.Vehicle** -- One GenServer per drone, supervised
- **Drone.Adapter** -- Behaviour for drone communication (Sim, Tello, future adapters)
- **Drone.Geometry** -- Shared position math (move, rotate, flip deltas)
- **Drone.Safety** -- Pure validation module, no side effects
- **Drone.Telemetry** -- `:telemetry` events for observability
- **Drone.Mission** -- Command sequence DSL

## License

MIT
