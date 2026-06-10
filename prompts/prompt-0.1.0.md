

# Overall roadmap for ex_drone

## v0.1.0 — Tello + Simulator foundation

Goal: first usable BEAM-native drone control library.

Scope:

* Drone public API
* Drone.Vehicle supervised GenServer per drone
* Drone.Adapter behaviour
* Drone.Adapters.Sim
* Drone.Adapters.Tello
* Drone.Command
* Drone.Safety
* Drone.Telemetry
* Drone.Mission
* UDP command support for Tello / Tello EDU
* fake UDP server tests
* simulator-first examples

Why Tello first: the official SDK exposes Wi-Fi UDP text commands, which maps well to Elixir’s :gen_udp.  ￼

Deliverable article:

“Building a BEAM-native drone controller: processes, UDP, safety, and simulation.”

⸻

## v0.2.0 — Swarms and mission orchestration

Scope:

* Drone.Swarm
* named drone registry
* coordinated takeoff / land
* mission scripts
* formation primitives
* deterministic simulator tests
* example: “Good Advisor / Bad Advisor”

Deliverable article:

“Why OTP is a natural model for drone swarms.”

⸻

## v0.3.0 — Crazyflie adapter

Scope:

* adapter via Python cflib port first
* later native protocol investigation
* telemetry bridge
* connection URI handling
* safety parity with simulator

Crazyflie’s official control library is Python-based and hides lower-level communication details, so a port/bridge is the pragmatic first adapter.  ￼

Deliverable article:

“Bridging Elixir and robotics SDKs: controlling Crazyflie from the BEAM.”

⸻

## v0.4.0 — MAVLink / PX4 foundation

Scope:

* MAVLink packet encoding/decoding research
* telemetry receive loop
* heartbeat support
* basic command-long support
* PX4 SITL integration
* no real flight until simulator tests pass

MAVLink is the lightweight drone messaging protocol used by PX4 and many ground-control/drone systems.  ￼

Deliverable article:

“MAVLink on the BEAM: telemetry, commands, and fault tolerance.”

⸻

## v0.5.0 — Safety, policy, and observability

Scope:

* kill switch
* geofence
* altitude limits
* command allowlists
* battery policies
* supervised failure recovery
* :telemetry dashboards
* Livebook demos

Deliverable article:

“Safety-first robotics APIs in Elixir.”

⸻

## v0.6.0 — Educational robotics toolkit

Scope:

* Livebook lessons
* simulator playground
* classroom examples
* mission visualizer
* event log replay
* Drone.DigitalTwin

Deliverable article:

“Teaching robotics with Elixir, OTP, and simulation.”

⸻

## v1.0.0 — Stable public API

Scope:

* stable adapter contract
* stable mission DSL
* Tello production quality
* simulator production quality
* Crazyflie beta/stable depending on reliability
* MAVLink beta
* full documentation site

⸻

# Development rule

Every milestone must proceed in this order:

Research → Design Plan → Review Checklist → Implementation → Tests → Docs → Educational Article Notes

No coding before the plan and review checklist exist.

# ExDrone Implementation Prompt

You are building an Elixir library called ex_drone.

Repository: ex_drone
Hex package: ex_drone
OTP app: :ex_drone
Public namespace: Drone

## Project Mission

Build a BEAM-native framework for controlling programmable drones from Elixir and Erlang.

The library must support:

* supervised drone processes
* pluggable drone adapters
* simulator-first development
* safety-first APIs
* telemetry
* mission planning
* swarm coordination
* educational documentation at every stage

This is both a working open-source library and an educational project. At every milestone, generate learning material that explains what is being built, why it matters, what BEAM/OTP concepts are involved, and how the work could become a later Medium article.

## Non-Negotiable Workflow

For every milestone, proceed in this exact order:

1. Research notes
2. Design plan
3. Architecture review
4. Risk and safety review
5. Implementation plan
6. Only then write code
7. Tests
8. Documentation
9. Educational notes
10. Medium article outline

Do not begin implementation until the planning documents and review checklist are written.

## Core Principles

* Idiomatic Elixir
* Supervision-first design
* Explicit error tuples
* No hidden global process state
* Simulator before hardware
* Safety checks before real commands
* No cloud dependency
* No automatic retry of dangerous movement commands unless explicitly enabled
* Clear adapter boundaries
* Testable without real drones
* Documentation-driven development
* No emojis in documentation
* Do not commit code

## Initial Architecture

Create these modules:

* `Drone`
* `Drone.Vehicle`
* `Drone.Adapter`
* `Drone.Adapters.Sim`
* `Drone.Adapters.Tello`
* `Drone.Command`
* `Drone.Mission`
* `Drone.Swarm`
* `Drone.Safety`
* `Drone.Telemetry`
* `Drone.Error`

## Public API Target

```elixir
{:ok, drone} = Drone.connect(:sim, name: :good_advice)

Drone.takeoff(drone)
Drone.hover(drone, seconds: 5)
Drone.move(drone, :up, 40)
Drone.rotate(drone, :cw, 90)
Drone.land(drone)
```

Tello example:

```elixir
{:ok, drone} = Drone.connect(:tello, name: :tello_1)

Drone.takeoff(drone)
Drone.move(drone, :forward, 50)
Drone.rotate(drone, :cw, 90)
Drone.land(drone)
```

Swarm example:

```elixir
{:ok, swarm} =
  Drone.Swarm.start_link([
    {:good, adapter: :sim},
    {:bad, adapter: :sim}
  ])
Drone.Swarm.takeoff(swarm)
Drone.Swarm.run(swarm, :shoulder_pair)
Drone.Swarm.land(swarm)
```

## Adapter Behaviour

Define:

```elixir
defmodule Drone.Adapter do
  @callback connect(keyword()) :: {:ok, term()} | {:error, term()}
  @callback command(state :: term(), command :: Drone.Command.t()) ::
              {:ok, reply :: term(), new_state :: term()}
              | {:error, reason :: term(), new_state :: term()}
  @callback telemetry(state :: term()) ::
              {:ok, map(), term()} | {:error, term(), term()}
  @callback disconnect(state :: term()) :: :ok
end
```

## v0.1.0 Milestone: Simulator + Tello

### Research Phase

Before coding, create:

* `docs/research/tello_sdk.md`
* `docs/research/beam_udp.md`
* `docs/research/safety_model.md`
* `docs/research/simulator_design.md`

Explain:

* how the Tello SDK works
* how UDP maps to :gen_udp
* what commands are safe to retry
* what commands must never be retried automatically
* how simulator state should mirror real drone state

### Design Phase

Create:

* `docs/design/v0_1_0_plan.md`
* `docs/design/adapter_contract.md`
* `docs/design/safety_pipeline.md`
* `docs/design/telemetry_events.md`

Include diagrams in Mermaid where helpful.

### Review Gate

Create:

* `docs/reviews/v0_1_0_review_checklist.md`

The review must answer:

* Is the simulator useful without hardware?
* Can all public APIs be tested without a drone?
* Are dangerous commands protected by safety rules?
* Are errors explicit and useful?
* Can the Tello adapter be replaced without changing user code?
* Does the architecture support Crazyflie and MAVLink later?

Do not implement until this review document exists.

### Tello Adapter Requirements

Use `:gen_udp`.

Defaults:

* drone IP: `192.168.10.1`
* command port: `8889`
* local command socket: configurable
* command timeout: configurable

Implement:

* command
* takeoff
* land
* emergency
* up
* down
* left
* right
* forward
* back
* cw
* ccw
* flip
* battery?
* height?
* speed?
* time?

Parse:

* ok
* error
* numeric query responses
* timeout
* socket errors

Safety:

* emergency must always bypass normal safety checks
* movement commands must pass safety validation
* never automatically retry movement commands by default
* query commands may be retried safely
* takeoff and land require special handling

### Simulator Requirements

The simulator must maintain:

* x
* y
* z
* yaw
* flying?
* battery
* last command
* command history

The simulator must:

* enforce the same safety rules as real adapters
* support deterministic tests
* allow mission replay
* allow telemetry snapshots
* simulate battery drain
* simulate command failures when configured

### Safety Requirements

Implement `Drone.Safety`.

Support:

* max altitude
* max distance
* min battery
* command allowlist
* dry-run mode
* indoor mode
* geofence
* emergency stop
* require prop guards flag
* dangerous-command warnings

Safety pipeline:

```
command requested
→ normalize command
→ validate command shape
→ check safety policy
→ emit telemetry
→ adapter command
→ parse result
→ update vehicle state
```

### Telemetry Requirements

Emit :telemetry events for:

* connect start
* connect stop
* connect error
* command start
* command stop
* command error
* safety reject
* telemetry update
* disconnect
* emergency

Use event names like:

```elixir
[:drone, :command, :start]
[:drone, :command, :stop]
[:drone, :safety, :reject]
```

### Tests

Include:

* doctests
* command encoding tests
* safety validation tests
* simulator mission tests
* vehicle GenServer tests
* fake UDP Tello server tests
* telemetry tests
* swarm tests, if included in v0.1.0

Coverage target: 70%+

### Documentation

Create:

* `README.md`
* `docs/getting_started.md`
* `docs/safety.md`
* `docs/simulator.md`
* `docs/tello.md`
* `docs/architecture.md`
* `docs/adapter_authoring.md`
* `docs/article_notes/v0_1_0.md`

README must include a visible safety warning:

* do not fly near faces
* use prop guards
* test in simulator first
* use open indoor space
* have an emergency stop
* understand local laws and rules

### Educational Material

For v0.1.0, write educational sections explaining:

* why one drone maps naturally to one GenServer
* why adapters are behaviours
* why UDP is a good first protocol
* how safety pipelines work
* why simulation should come before hardware
* how telemetry supports observability
* how this design can later support swarms

Also create:

* `docs/article_notes/building_ex_drone_v0_1_0.md`

This should be suitable as source material for a Medium article.

## v0.2.0 Milestone: Swarms and Missions

Before coding, create:

* docs/design/v0_2_0_swarm_plan.md
* docs/reviews/v0_2_0_review_checklist.md
* docs/article_notes/v0_2_0_swarm_article.md

Implement:

* Drone.Swarm
* named drone registry
* coordinated takeoff
* coordinated land
* simple formation primitives
* mission scripts
* deterministic simulation tests

Example mission:

```elixir
Drone.Mission.new()
|> Drone.Mission.takeoff()
|> Drone.Mission.hover(seconds: 3)
|> Drone.Mission.move(:up, 30)
|> Drone.Mission.rotate(:cw, 90)
|> Drone.Mission.land()
```

Include the “Good Advisor / Bad Advisor” example using simulation first.

## v0.3.0 Milestone: Crazyflie

Before coding, create:

* `docs/research/crazyflie.md`
* `docs/design/v0_3_0_crazyflie_plan.md`
* `docs/reviews/v0_3_0_review_checklist.md`
* `docs/article_notes/v0_3_0_crazyflie_article.md`

First implementation may use a Python port around Bitcraze cflib.

The design must preserve the same Drone.Adapter behaviour.

## v0.4.0 Milestone: MAVLink / PX4

Before coding, create:

* `docs/research/mavlink.md`
* docs/research/px4_sitl.md
* `docs/design/v0_4_0_mavlink_plan.md`
* `docs/reviews/v0_4_0_review_checklist.md`
* `docs/article_notes/v0_4_0_mavlink_article.md`

Start with simulator/SITL only.

Implement only the safest minimal subset:

* heartbeat
* telemetry receive loop
* basic command abstraction
* no autonomous real flight in the first MAVLink milestone

## CI

Add GitHub Actions:

* `mix format --check-formatted`
* `mix deps.unlock --check-unused`
* `mix credo --strict`
* `mix test`
* optional Dialyzer
* coverage reporting

Final Deliverable for Each Milestone

Each milestone must produce:

1. Working code
2. Passing tests
3. Documentation
4. Research notes
5. Design notes
6. Review checklist
7. Educational explanation
8. Medium article outline
9. Changelog entry

## First Task

Begin v0.1.0.

Do not code first.

First create the planning and research documents, then stop and present the plan for review.
