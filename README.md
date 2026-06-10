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

## Roadmap

### v0.1.0 — Tello + Simulator Foundation (current)

Public API, supervised processes, safety pipeline, simulator, Tello adapter, missions, telemetry.

- [x] `Drone` public API (`connect/2`, `disconnect/1`, `takeoff/1`, `move/3`, `rotate/3`, etc.)
- [x] `Drone.Vehicle` — one GenServer per drone, supervised
- [x] `Drone.Adapter` behaviour — pluggable adapters
- [x] `Drone.Adapters.Sim` — in-process simulator with position tracking, battery drain, failure injection
- [x] `Drone.Adapters.Tello` — DJI Tello UDP adapter (command encoding, response parsing, state management)
- [x] `Drone.Command` — struct constructors for 14 command types
- [x] `Drone.Safety` — 8-stage validation pipeline (args, mode, allowlist, flying, altitude, distance, battery, geofence)
- [x] `Drone.Safety.Policy` — default, indoor, unrestricted presets
- [x] `Drone.Safety.Geofence` — circle and polygon geofencing
- [x] `Drone.Geometry` — shared position math (heading-aware movement, rotation, flips)
- [x] `Drone.Telemetry` — `:telemetry` events (command start/stop, safety reject, connect, disconnect)
- [x] `Drone.Mission` — command sequence DSL with error-early semantics
- [x] `Drone.Error` — error type helpers (`safety/1`, `adapter/1`, `invalid_command/1`)
- [x] Command argument validation per Tello SDK ranges
- [x] Emergency stop bypassing all safety checks
- [x] Dry-run mode for validating missions without flying
- [x] Flight time simulation (`query(:time)` returns cumulative motor-on seconds)
- [x] CI/CD — lint, test matrix (1.17-1.20 / OTP 26-29), coverage (90.2%), sobelow, dialyzer, docs, Hex.pm publish
- [x] 253 tests, 90.2% coverage, credo --strict clean, --warnings-as-errors clean

### v0.2.0 — Async Missions & Retry

Command retry with exponential backoff, async mission execution, and improved error recovery.

- [ ] Command retry with configurable backoff (`safe_to_retry?/1` already in `Drone.Command`)
- [ ] `Mission.run_async/2` — fire-and-forget mission execution with progress events
- [ ] `Mission.run_stream/2` — streamed results via `GenStage` or `Stream`
- [ ] Reconnect on adapter failure — Vehicle auto-reconnects to Tello after network errors
- [ ] `Drone.Adapters.Tello` — state recovery on reconnect (re-query SDK mode, battery, position)
- [ ] Configurable command timeout per-vehicle (default 10s)

### v0.3.0 — Multi-Drone Coordination

Swarm primitives for coordinating multiple drones.

- [ ] `Drone.Swarm` — supervised group of drones with shared mission context
- [ ] Formation flying —grid, line, circle— via relative position commands
- [ ] `Drone.Mission.concurrent/2` — run missions on multiple drones in parallel
- [ ] Collision avoidance in simulator — safety policy rejects commands that would collide
- [ ] Coordinated takeoff/land — swarm-level commands that dispatch to individual drones

### v0.4.0 — Video & Sensors

Video stream handling and real-time sensor data from Tello EDU.

- [ ] `Drone.Adapters.Tello.Stream` — receive H.264 video stream via UDP
- [ ] `Drone.Adapters.Tello.State` — subscribe to real-time telemetry (100ms interval)
- [ ] `Drone.Telemetry.stream/1` — stream telemetry events as Elixir Stream
- [ ] Video frame extraction — decode keyframes to JPEG for snapshot API
- [ ] `Drone.query(:wifi_signal)` — WiFi signal quality from state stream

### v0.5.0 — New Adapters & Protocol Extensions

Additional hardware support beyond Tello.

- [ ] `Drone.Adapters.Crazyflie` — Crazyflie BLE/USB adapter
- [ ] `Drone.Adapters.MAVLink` — MAVLink-compatible drones via serial/UDP
- [ ] `Drone.Adapters.PX4` — PX4 SITL integration for simulation at scale
- [ ] Adapter registry — `Drone.Adapter.register/2` for third-party adapters
- [ ] Common adapter test suite — shared `Drone.Adapter.Acceptance` tests

### v1.0.0 — Stable API

API freeze, production hardening, and enterprise features.

- [ ] API stability guarantee — no breaking changes within 1.x
- [ ] `:telemetry` analytics dashboard integration (LiveDashboard plugin)
- [ ] Ecto-backed persistence — mission logs, flight history, anomaly tracking
- [ ] Fly.io deployment guide — run command relay in the cloud
- [ ] Nerves integration guide — run on Raspberry Pi with Tello
- [ ] Comprehensive property-based testing (`StreamData`)
- [ ] Performance benchmarks and soak tests

## License

MIT
