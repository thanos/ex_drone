# Swarm Coordination Research

## Overview

This document researches how multi-drone coordination should work in ex_drone
v0.2.0, building on the v0.1.0 foundation of one GenServer per drone, a named
Registry, a pure safety pipeline, and a deterministic simulator.

## Why OTP Fits Swarms

A swarm is a set of independent actors that must occasionally act together.

| Swarm need                         | OTP primitive                         |
|------------------------------------|---------------------------------------|
| One drone, isolated state          | GenServer (`Drone.Vehicle`)           |
| Lookup by name                     | Registry (`Drone.Vehicle.Registry`)   |
| Crash isolation                    | Supervision (`:one_for_one`)          |
| Group lifecycle                    | Supervisor or Swarm GenServer         |
| Fan-out command                    | Enumerate members, call each process  |
| Partial failure                    | Explicit per-drone result aggregation |
| Deterministic testing              | Simulator + sequential calls          |

OTP does not magically solve mid-air physics. It solves process identity,
supervision, messaging, and failure boundaries — the software side of swarm
control.

## What v0.1.0 Already Provides

- Named vehicles via `Drone.Vehicle.Registry`
- Per-drone safety pipeline (altitude, distance, battery, geofence, allowlist)
- Position tracking (`x`, `y`, `z`, `yaw`) in vehicle state and simulator
- Shared geometry helpers for yaw-aware movement
- Single-drone mission DSL (`Drone.Mission`)
- Telemetry events per vehicle

v0.2.0 does not reinvent these. It composes them.

## Coordination Models Considered

### 1. Pure fan-out helper (stateless)

```elixir
Drone.Swarm.takeoff([:good, :bad])
```

Pros: simple, no new process.
Cons: no group lifecycle, no shared formation context, no place to attach
swarm telemetry or failure policy.

### 2. Swarm GenServer owning member list

```elixir
{:ok, swarm} = Drone.Swarm.start([{:good, adapter: :sim}, {:bad, adapter: :sim}])
```

Pros: matches the prompt API; holds formation state; can supervise group
ops; emits swarm-level telemetry; natural home for `run/2` formation scripts.
Cons: another process to reason about; must define ownership of vehicles
(create vs adopt).

### 3. DynamicSupervisor per swarm

Pros: restart strategy per group.
Cons: heavier than needed for v0.2.0; vehicles already live under
`Drone.Supervisor`. Nested supervisors add little until real-hardware swarm
recovery is a goal.

**Decision for v0.2.0:** model 2 — a `Drone.Swarm` GenServer that starts (or
adopts) named vehicles and coordinates group operations. Vehicles remain under
`Drone.Supervisor`. The swarm process holds membership and formation context
only.

## Named Registry

v0.1.0 already registers vehicles under `Drone.Vehicle.Registry`.

v0.2.0 requirements:

- Swarm members are always named atoms (`:good`, `:bad`)
- Swarm itself may be optionally named via `:name` for lookup
- No second vehicle registry — reuse `Drone.Vehicle.Registry`
- Optional `Drone.Swarm.Registry` only if multiple named swarms need via-tuple
  lookup; otherwise a single named GenServer or anonymous pid is enough

**Decision:** reuse `Drone.Vehicle.Registry` for drones. Register swarms with
`{:via, Registry, {Drone.Swarm.Registry, name}}` when `:name` is given, so
multiple concurrent swarms are testable.

## Coordinated Takeoff / Land

### Semantics

Coordinated takeoff means: send `takeoff` to every member, then return a
collective result. Same for land.

### Ordering and concurrency

Options:

1. **Sequential** — call each drone in member order. Deterministic. Slow for
   real hardware, ideal for simulator tests.
2. **Async Task** — `Task.async_stream` with timeout. Faster on real drones,
   harder to reason about in tests unless ordered collection is forced.

**Decision for v0.2.0:** sequential by default for determinism. Optional
`:async` mode is deferred — see `docs/design/v0_2_0_deferred.md`.

### Partial failure policy

If drone A takes off and drone B fails:

| Policy            | Behavior                                      | v0.2.0 |
|-------------------|-----------------------------------------------|--------|
| `:fail_fast`      | Stop remaining; return error with results so far | **Default** |
| `:best_effort`    | Continue all; return mixed results            | Deferred |
| `:all_or_nothing` | On any failure, land/emergency the succeeders | Deferred |

**Decision for v0.2.0:** `:fail_fast` default. Return:

```elixir
{:ok, %{good: :ok, bad: :ok}}
# or
{:error, :partial, %{good: :ok, bad: {:error, reason}}}
```

Emergency remains per-drone and swarm-wide: `Drone.Swarm.emergency(swarm)`
must fan out immediately and bypass normal formation logic.

## Formation Primitives

v0.2.0 uses **geometric formations**: one-shot planners that compute slots in a
shared world frame and emit per-drone missions. They are not continuous
controllers and not decentralized flocking.

**Default reference:** centroid of current member positions, or a configured
swarm origin `(origin_x, origin_y)` plus `heading_deg` (direction of motion).
An optional `leader:` is plan-time pose only — not a runtime dependency.
Leader failure policy and deferred recovery behaviours are documented in
`docs/design/v0_2_0_deferred.md`.

### Two models (do not conflate)

| Model | How structure is held | v0.2.0 |
|-------|----------------------|--------|
| Geometric formation | Plan slots once, fly there | **In scope** |
| Behavioral flocking | Continuous Separate / Align / Cohere | **Deferred** |

### v0.2.0 classic formation set

| Atom | Name | Description |
|------|------|-------------|
| `:front` | Front (Line) | Side-by-side, perpendicular to direction of motion |
| `:column` | Column | One behind another along direction of motion |
| `:vee` | Vee | V shape (geometry only; no aero / drag claims) |
| `:diamond` | Diamond | Four-sided closed layout (≥4 members) |
| `:echelon` | Echelon | Diagonal stepped rank (`:left` \| `:right`) |
| `:circle` | Circular | Even spacing on a perimeter |
| `:shoulder_pair` | alias | `:front` with 2 members (Good/Bad Advisor) |
| `:grid` | optional | Classroom row/column lattice |

These are **command generators**. Given positions and a formation spec, produce
`%{drone_name => Mission.t()}` (or command lists) that move each drone to its
slot, then optionally hover.

### Coordinate model

Simulator positions are in cm relative to each drone's own launch origin
today. For multi-drone formations, that is insufficient if each sim starts
at `{0,0,0}`.

**Decision:** when starting a swarm with the simulator, assign each member an
initial world offset via adapter opts (e.g. `initial_x`, `initial_y`). The
swarm formation planner works in a shared world frame. If Sim does not yet
support initial offsets, add them in v0.2.0 (small, local change).

### Separate (core behavioural rule — scoped)

Classic swarms maintain structure with decentralized local rules. For v0.2.0
only the **Separate** constraint is enforced, and only at **plan time**:

- Formation spacing must be >= configurable `min_separation_cm`
- Reject plans that place two slots closer than that
- Live Separate / Align / Cohere, and mid-flight collision avoidance, are
  deferred — see `docs/design/v0_2_0_deferred.md`

## Mission Scripts

v0.1.0 `Drone.Mission` is single-drone and already works.

v0.2.0 extends missions in two ways:

1. **Unchanged single-drone missions** — keep current API
2. **Swarm run** — `Drone.Swarm.run(swarm, formation_or_mission)`

`Drone.Swarm.run/2` accepts:

- A formation atom (`:front`, `:column`, `:vee`, `:diamond`, `:echelon`,
  `:circle`, `:shoulder_pair`, optional `:grid`)
- A function `(%{name => drone}) -> :ok | {:error, term()}` for custom scripts
- Optionally a map of `%{drone_name => Mission.t()}` for per-drone missions

Concurrent per-drone mission execution (`Mission.concurrent/2`) is deferred —
see `docs/design/v0_2_0_deferred.md`.

## Deterministic Simulator Tests

Requirements for swarm tests:

- Fixed member order
- Sequential command dispatch
- Known initial world offsets
- No wall-clock sleeps in formation math (hover may use short sleeps; prefer
  `:timer.sleep` only inside hover command path already used by Mission)
- Assert final telemetry positions after formation run
- Assert fail-fast stop when one member's safety policy rejects

Failure injection in Sim remains useful: configure one member to fail takeoff
and assert swarm partial-error shape.

## Hardware Reality Check (Tello)

Real Tello / Tello EDU swarm flight is constrained:

- Stock Tello creates its own Wi-Fi AP — one phone/laptop per drone unless
  using EDU station mode
- Tello EDU station mode joins a shared network — required for multi-drone
  from one host
- UDP command latency and Wi-Fi contention make true simultaneous motion hard
- Position is not globally known on real Tello without external tracking

**Implication:** v0.2.0 formations are **simulator-first**. Real Tello swarm
demo is optional/educational and must warn about EDU station mode and lack of
absolute positioning. Do not claim closed-loop formation flight on bare Tello.

## Good Advisor / Bad Advisor Example

Educational scenario with two simulated drones:

- `:good` — follows a safe mission (takeoff, modest moves, land)
- `:bad` — attempts unsafe moves (excessive altitude, geofence breach) and is
  rejected by safety

Purpose: show that swarm coordination + per-drone safety compose. One
member's rejection does not crash the other process; fail-fast swarm policy
surfaces the error; emergency can still stop both.

This is the flagship example for the v0.2.0 article.

## Out of Scope for v0.2.0

All deferred swarm features and behaviours discussed in planning — including
behavioral flocking (Align / Cohere / live Separate), closed-loop formation
control, leader election and replan, alternate failure policies, async fan-out,
live collision avoidance, multi-node swarms, hardware absolute choreography,
sensor/video/aero semantics, and platform multi-vehicle work — are catalogued
in:

**`docs/design/v0_2_0_deferred.md`**

Do not implement those items in v0.2.0 without updating the review checklist.

## Research Conclusions

1. Swarm = GenServer coordinator + existing Vehicle processes + Registry
2. Sequential coordinated ops first for determinism
3. Formations are offline geometric planners (classic catalog), not flocking
4. Default reference is centroid/origin; leader is optional plan-time only
5. Simulator needs shared-world initial offsets
6. Safety stays per-drone; swarm adds plan-time Separate checks
7. Good Advisor / Bad Advisor is the didactic deliverable
8. Real Tello multi-drone is documented as limited; sim is the proof surface
9. Everything discussed but deferred is tracked in `v0_2_0_deferred.md`

## See also

- Guides: [Swarms](../swarm.md), [Formations](../formations.md)
- Deferred work: [v0.2.0 Deferred](../design/v0_2_0_deferred.md)
- Further reading: [Swarming, formations, and strategies](../further_reading.md#swarming-formations-and-strategies)
