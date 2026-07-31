# Formations

`Drone.Formation` is a pure planner. Given member positions and options, it
returns per-drone `Drone.Mission` scripts that move each drone to its slot.
It does not run a control loop.

## Catalog

| Atom | Name | Min drones | Layout |
|------|------|------------|--------|
| `:front` | Front (Line) | 2 | Side-by-side, perpendicular to heading |
| `:column` | Column | 2 | Nose-to-tail along heading |
| `:vee` | Vee | 3 | V opening opposite travel (geometry only) |
| `:diamond` | Diamond | 4 | Four-sided closed layout |
| `:echelon` | Echelon | 2 | Diagonal stepped rank (`side: :left \| :right`) |
| `:circle` | Circular | 3 | Even spacing on a ring (`radius_cm`) |
| `:shoulder_pair` | alias | 2 | `:front` with two members |
| `:grid` | Grid | 2 | Optional classroom lattice (`columns`) |

## Options

```elixir
Formation.plan(:front, %{
  drones: [:a, :b],
  positions: %{
    a: %{x: 0, y: 0, z: 30, yaw: 0},
    b: %{x: 0, y: 0, z: 30, yaw: 0}
  },
  heading_deg: 0,
  spacing_cm: 100,
  min_separation_cm: 80,
  origin: :centroid
  # origin: {:xy, 0, 0}
  # leader: :a   # plan-time pose only
})
```

- **heading_deg** — direction of motion (yaw 0 is +Y, matching shared geometry conventions)
- **origin** — `:centroid` (default) or `{:xy, x, y}`
- **leader** — optional; uses that member's pose as the plan-time origin only
- **min_separation_cm** — plan-time Separate check; rejects too-tight slots

## Movement strategy

For each drone:

1. Rotate to face the target bearing
2. Move forward (split into 500 cm segments if needed)
3. Rotate back toward the original yaw when needed

Moves shorter than 20 cm are skipped (Tello/SDK minimum distance).

## Through the swarm

```elixir
Drone.Swarm.run(swarm, :front)
Drone.Swarm.run(swarm, :column)
Drone.Swarm.run(swarm, :vee)
Drone.Swarm.run(swarm, :echelon, side: :left, heading_deg: 90)
Drone.Swarm.run(swarm, :circle, radius_cm: 150)
Drone.Swarm.run(swarm, :grid, columns: 2)
```

Swarm spacing defaults come from `start` options `:spacing_cm` and
`:min_separation_cm`. Pass formation options as the third argument to
`Drone.Swarm.run/3` to override them per call (`:leader`, `:origin`, `:side`,
`:radius_cm`, `:columns`, `:heading_deg`, etc.).

Planned slots are checked for separation; flight paths between slots are not
deconflicted (two drones may cross while relocating). Live collision avoidance
is deferred.

## Not included

Live Separate/Align/Cohere, closed-loop hold, formation morphing, and
leader election are deferred — see `docs/design/v0_2_0_deferred.md`.
