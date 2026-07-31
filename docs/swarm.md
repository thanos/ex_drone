# Swarms

`Drone.Swarm` coordinates a named set of drones. Each member is still a
normal `Drone.Vehicle` with its own safety pipeline. The swarm adds
membership, coordinated fan-out, and formation planning.

`Drone.Swarm.start/1` mirrors `Drone.connect/2`: it returns a handle
(`:name` or `pid`) and does not link the caller. Use `child_spec/1` under
your own supervisor when you need OTP linking.

## Quick start

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

Named swarms are registered under `Drone.Swarm.Registry`:

```elixir
{:ok, :advisors} =
  Drone.Swarm.start(
    name: :advisors,
    members: [
      {:a, adapter: :sim, initial_x: 0},
      {:b, adapter: :sim, initial_x: 100}
    ]
  )

Drone.Swarm.whereis(:advisors)
```

## Coordinated operations

| Function | Behaviour |
|----------|-----------|
| `connect_sdk/1` | Fan-out SDK mode |
| `takeoff/1` | Coordinated takeoff |
| `land/1` | Coordinated land |
| `emergency/1` | Best-effort emergency on all members (not blocked by `run/2`) |
| `run/2` / `run/3` | Formation, mission map, or custom function |
| `telemetry/1` | Map of per-member telemetry |
| `stop/1` | Stop swarm (disconnects members by default) |

Default fan-out policy is **fail-fast**:

```elixir
{:ok, %{a: :ok, b: :ok}}
{:error, :partial, %{a: :ok, b: {:error, reason}}}
```

Already-completed members are not undone. Call `land/1` or `emergency/1`
explicitly after a partial failure. Coordinated calls default to a 60s
timeout; override with `timeout:` on the call or when starting the swarm.

## Running missions

```elixir
Drone.Swarm.run(swarm, :vee)
Drone.Swarm.run(swarm, :echelon, side: :left)

Drone.Swarm.run(swarm, %{
  good: good_mission,
  bad: bad_mission
})

Drone.Swarm.run(swarm, fn members ->
  Enum.each(members, fn {_name, drone} -> Drone.hover(drone) end)
  :ok
end)
```

See `docs/formations.md` for the formation catalog.

## Simulator offsets

Multi-drone formations need a shared world frame. Pass `initial_x`,
`initial_y`, `initial_z`, and `initial_yaw` when connecting sim members.

## Safety

- Per-drone `Drone.Safety` still gates every command
- Formations enforce plan-time `min_separation_cm` (Separate)
- Live flocking and collision avoidance are not in v0.2.0 — see
  `docs/design/v0_2_0_deferred.md`

## Example

```bash
mix run examples/good_bad_advisor.exs
```

## Hardware note

Absolute formations are simulator-first. Stock Tello Wi-Fi and lack of
global pose make closed-loop choreography unreliable. Tello EDU station
mode helps connectivity, not localization.

## Further Reading

- [Formations](formations.md)
- Research: [Swarm Coordination](research/swarm_coordination.md)
- Deferred flocking and closed-loop work: [v0.2.0 Deferred](design/v0_2_0_deferred.md)
- Surveys and classic papers: [Further Reading](further_reading.md#swarming-formations-and-strategies)
