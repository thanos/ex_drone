# v0.2.0 Deferred Work — Future Swarm Implementation

This document records every swarm-related feature or behaviour discussed during
v0.2.0 planning that is **intentionally left out of this release**. It is the
backlog seed for later milestones. Do not treat absence from the v0.2.0
implementation checklist as “forgotten.”

Related:

- In scope: `docs/research/swarm_coordination.md` and `docs/swarm.md`
- Research: `docs/research/swarm_coordination.md`
- Formation guide: `docs/formations.md`

Suggested roadmap homes are indicative, not commitments. Revisit when that
milestone is planned.

---

## 1. Behavioral flocking (decentralized local rules)

**Discussed:** Swarms can hold structure without a central leader by relying on
local interactions (Reynolds-style / boids).

| Rule | Meaning | v0.2.0 | Future |
|------|---------|--------|--------|
| **Separate** | Maintain a safe minimum distance from neighbors | Plan-time `min_separation_cm` only | Continuous steer-away from live neighbors |
| **Align** | Match velocity / heading of local neighbors | Not implemented | Behavior tick that biases yaw/speed |
| **Cohere** | Steer toward local flock centroid | Not implemented | Behavior tick toward neighbor centroid |

**Future module sketch:** `Drone.Swarm.Behavior` (or `Drone.Flocking`)

- Periodic tick (simulator-first)
- Each vehicle reads neighbor telemetry within a radius
- Emits soft relative move / rotate suggestions (still through Safety)
- No central leader required for structure maintenance

**Why deferred:** Needs a neighbor sensing loop, timing model, and non-
deterministic-friendly test strategy. v0.2.0 ships **geometric planners**, not
emergent flocking.

**Likely home:** after swarm primitives stabilize; possibly with richer safety /
observability work.

---

## 2. Live / dynamic collision avoidance

**Discussed:** Reject or reshape commands that would collide with other swarm
members during flight.

| Layer | v0.2.0 | Future |
|-------|--------|--------|
| Plan-time slot separation | Yes | Keep |
| Mid-flight collision prediction in `Drone.Safety` | No | Ingest neighbors' positions into Safety |
| Simulator collision volume checks | No | Optional sim physics / bounding spheres |
| Reactive stop / hover on predicted conflict | No | Swarm or vehicle policy |

**Future sketch:**

- Vehicle Safety gains optional `neighbors: [%{name, x, y, z}, ...]`
- Swarm periodically publishes member poses to members (or Safety queries swarm)
- On predicted breach of `min_separation_cm`, reject move or force hover

**Why deferred:** Changes the Safety contract and requires a pose distribution
path. Easy to get wrong on real hardware without global localization.

---

## 3. Continuous / closed-loop formation control

**Discussed:** Hold Front/Vee/etc. over time while the group translates or turns
(PID / leader-follower / virtual structure).

| Approach | v0.2.0 | Future |
|----------|--------|--------|
| One-shot slot planner → missions | Yes | Keep as bootstrap |
| Continuous slot tracking | No | Recompute error each tick; issue corrections |
| Velocity sync across members | No | Shared speed / phase targets |
| Formation while translating (move as a Front) | No | Group translation primitive |

**Why deferred:** v0.2.0 formations are **command generators**, not pilots.
Closed-loop needs reliable pose and a control period.

---

## 4. Leader-based runtime dependency and recovery

**Discussed:** Formations relative to an explicit leader; what if the leader
fails?

**v0.2.0 decision:**

- Default reference = **centroid or configured swarm origin**, not a living leader
- Optional `leader:` means **plan-time pose snapshot only**
- Missing leader at plan time → hard error (`:leader_unavailable`)
- Leader command failure during `run` → same as any member (`:fail_fast`)
- No auto-undo of followers

**Deferred behaviours:**

| Behaviour | Notes |
|-----------|--------|
| Live leader-follower re-anchor | Followers continuously track leader pose |
| Automatic leader election / promotion | On leader crash, elect next member |
| Replan formation on membership change | Recompute slots when members join/leave/fail |
| Follower hold / orbit until new leader | Recovery choreography |
| `:all_or_nothing` undo after leader failure | Land/emergency succeeders automatically |

**Why deferred:** Recovery policy is product-sensitive and unsafe to guess.
Callers use explicit `land/1` or `emergency/1` in v0.2.0.

---

## 5. Alternate swarm failure policies

**Discussed:** `:fail_fast` vs `:best_effort` vs `:all_or_nothing`.

| Policy | v0.2.0 | Future |
|--------|--------|--------|
| `:fail_fast` | Default | Keep as default |
| `:best_effort` | Not shipped | Optional opt on coordinated ops |
| `:all_or_nothing` | Not shipped | On any failure, auto land/emergency succeeders |
| Configurable per-op policy | No | `takeoff(swarm, policy: :best_effort)` |

**Why deferred:** `:all_or_nothing` implies automatic dangerous commands.
Must be explicit, tested, and documented before enabling.

---

## 6. Async / concurrent fan-out

**Discussed:** `Task.async_stream` for faster real-hardware coordination;
`Mission.concurrent/2` for parallel per-drone missions.

| Feature | v0.2.0 | Future |
|---------|--------|--------|
| Sequential fan-out | Default | Keep for deterministic tests |
| `:async` coordinated takeoff/land/run | No | Opt-in with timeouts and ordered result maps |
| `Mission.concurrent/2` (planned) | No | Run missions on many drones in parallel |
| Barrier sync (“all reached slot”) | No | Wait until all members report pose within epsilon |

**Why deferred:** Concurrency complicates tests and partial-failure semantics.
Sim-first milestone prioritizes determinism.

---

## 7. Automatic retry of swarm / movement steps

**Discussed:** Retry failed formation legs or movement commands.

**v0.2.0:** No automatic retry of dangerous movement commands (existing core
principle). Swarm does not retry failed member steps.

**Future (only with explicit enablement):**

- Query retries remain separately allowable (already a v0.1.0 principle)
- Optional swarm `retry: [max: n, only: [:query | ...]]` — never default-on for moves
- Human-in-the-loop replay of failed member missions

---

## 8. Multi-node / distributed swarms

**Discussed:** Swarm members on multiple BEAM nodes.

**v0.2.0:** Single-node only.

**Future:**

- Distributed Registry or explicit node-qualified member refs
- Partition handling (split-brain is hazardous for physical actuators)
- Cross-node emergency propagation

**Likely home:** post-v1.0 research; treat as advanced/ops concern.

---

## 9. Nested swarm supervisors / per-swarm vehicle ownership

**Discussed:** DynamicSupervisor per swarm that owns vehicle children; richer
restart strategies for the group.

**v0.2.0:** Vehicles stay under `Drone.Supervisor`; swarm is a sibling
coordinator.

**Future:**

- Optional “swarm owns vehicles” mode for classroom demos
- Group restart policies (restart all members if one crashes — usually wrong
  for hardware, maybe useful for sim)

---

## 10. Real-hardware absolute formation flight (Tello)

**Discussed:** Running geometric formations on real Tello / Tello EDU.

**v0.2.0:** Simulator-first. Docs warn about Wi-Fi AP vs EDU station mode and
lack of global pose. No claim of closed-loop choreography on bare Tello.

**Future:**

- Tello EDU station-mode multi-drone connectivity guide
- External localization (UWB, mocap, vision) feeding vehicle state
- Hardware-in-the-loop tests behind explicit tags / opt-in CI
- Honest accuracy bounds for open-loop slot flying on consumer drones

---

## 11. Adapter / platform swarm work beyond Sim

| Item | Roadmap hint |
|------|----------------|
| Crazyflie multi-vehicle via same `Drone.Swarm` | v0.3.0+ |
| MAVLink / PX4 multi-vehicle + SITL swarm | v0.4.0+ |
| Adapter position fidelity requirements for formations | When non-sim adapters join swarms |
| Swarm acceptance tests shared across adapters | With adapter test suite work |

Swarm and Formation modules must stay adapter-agnostic in v0.2.0 so these can
plug in later.

---

## 12. Sensing, video, and surveillance semantics

**Discussed:** Circular/Diamond layouts for 360° surveillance and defense;
Vee for aerodynamic drag savings.

**v0.2.0:** Geometry only. No sensor tasking, no video sync, no aero model.

**Deferred:**

| Behaviour | Notes |
|-----------|--------|
| Video stream sync across swarm members | Needs video milestone |
| Assign camera yaw / sector per circle slot | Sensor tasking API |
| Vee drag / energy model | Not applicable to Tello-class; do not fake |
| “Defense” behaviours for Diamond | Application-level, not library core |

---

## 13. Formation catalog extensions and motion relative to heading

**v0.2.0 ships geometric planners for classic shapes** (see design plan):
`:front`, `:column`, `:vee`, `:diamond`, `:echelon`, `:circle`, plus aliases
`:shoulder_pair` / optional `:grid`.

**Still deferred beyond those planners:**

| Item | Notes |
|------|--------|
| Formation while translating as a rigid body | Group advance keeping Front/Vee |
| Smooth morph between formations (Front → Vee) | Trajectory blend |
| 3D formations (stacked vertical diamond, sphere) | Needs altitude coordination policy |
| Hollow vs filled circle / wedge variants | Extra parameters |
| Custom user-defined slot maps DSL | Beyond `%{name => Mission}` |
| World-frame path planner with obstacle map | Full nav stack |

Heading-relative layout (`heading_deg`) **is in scope** for v0.2.0 planners so
Front/Column/Vee/Echelon are meaningful; continuous heading tracking while
moving is not.

---

## 14. Mission orchestration extras

| Item | v0.2.0 | Future |
|------|--------|--------|
| Single-drone `Drone.Mission` | Yes (existing) | Stable |
| `Swarm.run` formation / mission map / function | Yes | Extend |
| `Mission.validate/1` | Optional small add | Or defer if unused |
| `Mission.run_async/2` with progress events | No (README idea) | Later |
| Mission replay from logged swarm flights | No | Persistence / analytics milestone |
| Swarm-level DSL (`Swarm.Mission`) | No | Only if single-drone DSL proves insufficient |

---

## 15. Observability and operator tooling

| Item | v0.2.0 | Future |
|------|--------|--------|
| Swarm telemetry events (start/stop/command/emergency) | Yes | Keep |
| LiveDashboard / charts for swarm | No | Observability milestone |
| Mission visualizer / formation overlay | No | Educational toolkit |
| Event log replay of swarm runs | No | Educational / analytics |
| Observer teaching guides for swarm processes | Article notes only | Livebook lessons |

---

## 16. Membership dynamics

| Item | v0.2.0 | Future |
|------|--------|--------|
| Fixed members at `start` | Yes | Keep |
| Hot-add / hot-remove members | No | `Swarm.join/2`, `Swarm.leave/2` |
| Adopt pre-existing vehicles into a swarm | Discussed; not required | Explicit adopt API |
| Stop swarm without disconnecting vehicles | Discussed as optional flag | Document + implement keep flag if needed in v0.2.0 design; richer policies later |

---

## Tracking rule

When a deferred item above is scheduled:

1. Move or copy its section into that milestone’s research/design docs
2. Strike or annotate it here with `Implemented in vX.Y.Z`
3. Do not implement it opportunistically inside v0.2.0 without updating the
   review checklist

---

## Summary table

| Theme | In v0.2.0 | Deferred |
|-------|-----------|----------|
| Coordinator + Registry | Yes | Multi-node, nested ownership |
| Geometric formations | Classic set, one-shot | Morphing, 3D, rigid translation |
| Separate | Plan-time min distance | Live Separate / Align / Cohere |
| Leader | Optional plan-time origin only | Election, live follow, replan |
| Failure policy | `:fail_fast` | `:best_effort`, `:all_or_nothing`, auto-undo |
| Fan-out | Sequential | Async, barriers, concurrent missions |
| Safety | Per-drone + plan separation | Neighbor-aware live collision checks |
| Platforms | Sim-first | Tello absolute, Crazyflie, MAVLink swarms |
| Sensors / aero | None | Video sync, sector tasking, drag models |
| Tooling | Events + example | Dashboard, visualizer, replay |
