# ex_drone

[![Hex version](https://img.shields.io/hexpm/v/ex_drone.svg)](https://hex.pm/packages/ex_drone)
[![Hex docs](https://img.shields.io/badge/docs-hexdocs.pm-blue)](https://hexdocs.pm/ex_drone)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/thanos/ex_drone/blob/main/LICENSE)
[![CI](https://github.com/thanos/ex_drone/actions/workflows/ci.yml/badge.svg)](https://github.com/thanos/ex_drone/actions/workflows/ci.yml) [![Coverage Status](https://coveralls.io/repos/github/thanos/ex_drone/badge.svg?branch=main)](https://coveralls.io/github/thanos/ex_drone?branch=main)

BEAM-native drone control for Elixir and Erlang. Fly, monitor, and simulate programmable drones — including Tello, Crazyflie (mock or Crazyradio), and multi-drone swarms — using supervised processes, telemetry, and missions.

## Safety Warning

**Drones are physical devices that can cause injury or property damage.**

- Do not fly near faces or people
- Use prop guards at all times
- Test in the simulator (or Crazyflie `mock://`) before connecting to real hardware
- Crazyflie high-level flight requires a working positioning system (Flow, Lighthouse, or Loco)
- Use open indoor spaces or outdoor areas with clear lines of sight
- Have an emergency stop ready at all times
- Understand and follow local laws and regulations

## Installation

Add `ex_drone` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_drone, "~> 0.3.0"}
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

## Swarms

Coordinate multiple simulated drones with `Drone.Swarm`:

```elixir
{:ok, swarm} =
  Drone.Swarm.start([
    {:good, adapter: :sim, initial_x: -50},
    {:bad, adapter: :sim, initial_x: 50}
  ])

Drone.Swarm.connect_sdk(swarm)
{:ok, _} = Drone.Swarm.takeoff(swarm)
{:ok, _} = Drone.Swarm.run(swarm, :front)
{:ok, _} = Drone.Swarm.land(swarm)
:ok = Drone.Swarm.stop(swarm)
```

See [Swarms](docs/swarm.md), [Formations](docs/formations.md), and
`examples/good_bad_advisor.exs`.

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

See `Drone.Safety.Policy` and the [Safety guide](docs/safety.md).

## Tello Connection

```elixir
{:ok, drone} = Drone.connect(:tello, name: :tello_1)
Drone.connect_sdk(drone)
Drone.takeoff(drone)
Drone.land(drone)
Drone.disconnect(drone)
```

See [Connecting to Hardware](docs/connecting.md) and the [Tello guide](docs/tello.md).

## Crazyflie Connection

```elixir
{:ok, drone} =
  Drone.connect(:crazyflie,
    name: :cf_1,
    uri: "mock://ready",
    positioning: :flow
  )

Drone.connect_sdk(drone)
Drone.takeoff(drone)
Drone.move(drone, :forward, 50)
Drone.land(drone)
Drone.disconnect(drone)
```

Use `mock://` without hardware. Real Crazyradio links need a `usb_backend`
implementing `Drone.Adapters.Crazyflie.USB`. See
[Connecting to Hardware](docs/connecting.md), the [Crazyflie guide](docs/crazyflie.md),
and `examples/crazyflie_mock_flight.exs`.

```shell
mix run examples/crazyflie_mock_flight.exs
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
- **Drone.Adapter** -- Behaviour for drone communication (Sim, Tello, Crazyflie)
- **Drone.Geometry** -- Shared position math (move, rotate, flip deltas)
- **Drone.Safety** -- Pure validation module, no side effects
- **Drone.Telemetry** -- `:telemetry` events for observability
- **Drone.Mission** -- Command sequence DSL
- **Drone.Swarm** -- Multi-drone coordinator (`start/1`, fan-out, `run/2`/`run/3`)
- **Drone.Formation** -- One-shot geometric formation planners
- **Drone.Adapter.Capabilities** -- Per-adapter capability metadata

See the [Architecture guide](docs/architecture.md).

## Documentation

### Guides

- [Getting Started](docs/getting_started.md)
- [Connecting to Hardware](docs/connecting.md)
- [Safety](docs/safety.md)
- [Simulator](docs/simulator.md)
- [Tello](docs/tello.md)
- [Crazyflie](docs/crazyflie.md)
- [Swarms](docs/swarm.md)
- [Formations](docs/formations.md)
- [Architecture](docs/architecture.md)
- [Adapter Authoring](docs/adapter_authoring.md)
- [Further Reading](docs/further_reading.md)

### Design

- [Adapter Contract](docs/design/adapter_contract.md)
- [Safety Pipeline](docs/design/safety_pipeline.md)
- [Telemetry Events](docs/design/telemetry_events.md)
- [v0.2.0 Deferred Work](docs/design/v0_2_0_deferred.md)
- [v0.3.0 Deferred Work](docs/design/v0_3_0_deferred.md)

### Research

- [Tello SDK](docs/research/tello_sdk.md)
- [BEAM UDP](docs/research/beam_udp.md)
- [Safety Model](docs/research/safety_model.md)
- [Simulator Design](docs/research/simulator_design.md)
- [Swarm Coordination](docs/research/swarm_coordination.md)

On HexDocs these pages appear under **Guides**, **Design**, and **Research**.

## Further Reading

Short starter set; the full annotated list is in [docs/further_reading.md](docs/further_reading.md).

- **Tello:** [DJI Tello SDK 2.0 User Guide (PDF)](https://dl-cdn.ryzerobotics.com/downloads/Tello/Tello%20SDK%202.0%20User%20Guide.pdf)
- **Swarm behaviour:** Reynolds, C. W. "Flocks, Herds, and Schools: A Distributed Behavioral Model." SIGGRAPH, 1987
- **Formation control:** Balch, T., and Arkin, R. C. "Behavior-based formation control for multirobot teams." IEEE TRA, 1998
- **Swarm robotics survey:** Brambilla, M. et al. "Swarm robotics: a review from the swarm engineering perspective." Swarm Intelligence, 2013
- **Motion planning:** LaValle, S. M. [Planning Algorithms](http://lavalle.pl/planning/)
- **Safety:** Leveson, N. G. *Engineering a Safer World*. MIT Press, 2011
- **OTP:** [OTP Design Principles](https://www.erlang.org/doc/system/design_principles.html)
- **Other platforms:** [Crazyflie](https://www.bitcraze.io/documentation/), [MAVLink](https://mavlink.io/en/), [PX4](https://docs.px4.io/), [ArduPilot](https://ardupilot.org/), [Nerves](https://nerves-project.org/)

## Roadmap

### v0.1.0 — Tello + Simulator Foundation

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
- [x] CI/CD — lint, test matrix (1.17-1.20 / OTP 26-29), coverage, sobelow, dialyzer, docs, Hex.pm publish
- [x] 291+ tests, credo --strict clean, --warnings-as-errors clean

### v0.2.0 — Swarms and Mission Orchestration

Multi-drone coordination on the v0.1.0 vehicle model.

- [x] `Drone.Swarm` — supervised group of drones with fail-fast fan-out
- [x] Named swarm registry (`Drone.Swarm.Registry`)
- [x] Coordinated takeoff / land / emergency
- [x] Formation planners — front, column, vee, diamond, echelon, circle
- [x] `Swarm.run/2` / `run/3` — formations, per-drone missions, or custom functions
- [x] Simulator initial world offsets for multi-drone layouts
- [x] Good Advisor / Bad Advisor example
- [x] Deferred flocking / closed-loop catalogue (`docs/design/v0_2_0_deferred.md`)

### v0.3.0 — Crazyflie Adapter & Capabilities

Single-drone Crazyflie high-level flight, capability reporting, and shared adapter contracts.

- [x] `Drone.Adapters.Crazyflie` — Crazyradio / mock high-level position flight
- [x] CRTP logging subscribe — battery (`pm.batteryLevel` / `pm.vbat`) + `sys.canfly`
- [x] Optional SafeLink negotiation (`?safelink=1`)
- [x] Pluggable `usb_backend` (`Drone.Adapters.Crazyflie.USB`)
- [x] Adapter capabilities — optional `capabilities/1` + `Drone.capabilities/1`
- [x] Common adapter acceptance tests — shared Sim / Crazyflie contract checks
- [x] Capability-aware mission validation before takeoff
- [x] Estimator / stale-telemetry safety options (fail closed)
- [x] Deferred catalogue (`docs/design/v0_3_0_deferred.md`)
- [ ] `Drone.Adapters.MAVLink` — MAVLink-compatible drones via serial/UDP
- [ ] Adapter registry — `Drone.Adapter.register/2` for third-party adapters
- [ ] Command retry with configurable backoff (`safe_to_retry?/1` already in `Drone.Command`)
- [ ] `Mission.run_async/2` — fire-and-forget mission execution with progress events
- [ ] Reconnect on adapter failure — Vehicle auto-reconnects after network errors
- [ ] `Drone.Adapters.Tello` — state recovery on reconnect (re-query SDK mode, battery, position)
- [ ] Configurable command timeout per-vehicle (default 10s)

### v0.4.0 — Video & Sensors

Video stream handling and real-time sensor data from Tello EDU.

- [ ] `Drone.Adapters.Tello.Stream` — receive H.264 video stream via UDP
- [ ] `Drone.Adapters.Tello.State` — subscribe to real-time telemetry (100ms interval)
- [ ] `Drone.Telemetry.stream/1` — stream telemetry events as Elixir Stream
- [ ] Video frame extraction — decode keyframes to JPEG for snapshot API
- [ ] `Drone.query(:wifi_signal)` — WiFi signal quality from state stream

### v0.5.0 — Persistence & Analytics

Flight logging, replay, and observability.

- [ ] Ecto-backed persistence — mission logs, flight history, anomaly tracking
- [ ] Mission replay — replay a recorded mission against a simulator for regression testing
- [ ] `:telemetry` analytics dashboard — LiveDashboard plugin with real-time charts
- [ ] Flight log query API — filter by drone, date, safety rejections, battery level
- [ ] Live flocking / neighbor-aware collision avoidance (see deferred swarm catalogue)

### v1.0.0 — Stable API

API freeze, production hardening, and deployment guides.

- [ ] API stability guarantee — no breaking changes within 1.x
- [ ] Fly.io deployment guide — run command relay in the cloud
- [ ] Nerves integration guide — run on Raspberry Pi with Tello
- [ ] Comprehensive property-based testing (`StreamData`)
- [ ] Performance benchmarks and soak tests

## License

MIT
