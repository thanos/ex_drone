# Swarms

`Drone.Swarm` coordinates a named set of drones. Each member is still a
normal `Drone.Vehicle` with its own safety pipeline. The swarm adds
membership, coordinated fan-out, and formation planning.

## Quick start

```elixir
{:ok, swarm} =
  Drone.Swarm.start_link([
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
  Drone.Swarm.start_link(
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
| `emergency/1` | Best-effort emergency on all members |
| `run/2` | Formation, mission map, or custom function |
| `telemetry/1` | Map of per-member telemetry |
| `stop/1` | Stop swarm (disconnects members by default) |

Default fan-out policy is **fail-fast**:

```elixir
{:ok, %{a: :ok, b: :ok}}
{:error, :partial, %{a: :ok, b: {:error, reason}}}
```

Already-completed members are not undone. Call `land/1` or `emergency/1`
explicitly after a partial failure.

## Running missions

```elixir
Drone.Swarm.run(swarm, :vee)

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
