# ex_drone v0.1.0 Release Notes

**Release Date:** 2026-06-10

BEAM-native drone control for Elixir and Erlang. Fly, monitor, and simulate programmable drones using supervised processes, telemetry, and missions.

---

## What's New

This is the inaugural release of ex_drone, a safety-first drone control library built on OTP principles.

### Core Modules

| Module | Purpose |
|--------|---------|
| `Drone` | Public API — connect, fly, query, disconnect |
| `Drone.Vehicle` | GenServer per drone, supervised by `Drone.Supervisor` |
| `Drone.Adapter` | Behaviour for pluggable adapters |
| `Drone.Adapters.Sim` | In-process simulator — no hardware needed |
| `Drone.Adapters.Tello` | DJI Tello UDP adapter |
| `Drone.Command` | Struct constructors for all Tello SDK commands |
| `Drone.Safety` | Pure validation pipeline — altitude, distance, battery, geofence, allowlist |
| `Drone.Safety.Policy` | Presets: `default/0`, `indoor/0`, `unrestricted/0` |
| `Drone.Safety.Geofence` | Circle and polygon geofencing |
| `Drone.Geometry` | Shared position math (move_delta, rotate_yaw, flip_delta) |
| `Drone.Telemetry` | `:telemetry` event helpers |
| `Drone.Mission` | Command sequence DSL |
| `Drone.Error` | Error type helpers |
| `Drone.Supervisor` | DynamicSupervisor for vehicle processes |
| `Drone.Application` | OTP app entry point |

### Features

- **Simulator-first design** — all APIs testable without hardware
- **Safety pipeline** — every command validated before reaching the drone
  - Command argument validation (distance 20-500cm, degrees 1-3600, speed 10-100cm/s, hover >0s)
  - Mode enforcement (idle → SDK mode → flying → land/emergency)
  - Allowlist support, altitude/distance/battery limits, geofence
  - Emergency commands bypass all safety checks
- **Dry-run mode** — validate missions without flying
- **Flight time simulation** — `query(:time)` returns cumulative motor-on seconds (matches real Tello)
- **Battery simulation** — configurable drain rates, always reported as integer
- **Failure injection** — test error handling with `failure_rate` and `fail_commands`
- **Position tracking** — x, y, z, yaw with proper heading-aware math
- **Telemetry events** — `[:drone, :command, :start/stop]`, `[:drone, :safety, :reject]`, `[:drone, :connect]`, `[:drone, :disconnect]`
- **Geofencing** — circle and polygon boundaries
- **Mission DSL** — script command sequences with error-early semantics

### CI/CD Pipeline

7-job pipeline on GitHub Actions:

1. **Lint** — format check, unused deps, credo strict with ex_slop
2. **Test matrix** — Elixir 1.17-1.20 × OTP 26-29
3. **Coverage** — 90.2% (threshold: 70%), coveralls upload
4. **Security** — sobelow scan
5. **Dialyzer** — type checking
6. **Docs** — mix docs build (html + epub)
7. **Release gate** — publishes to Hex.pm on merge to main

---

## Bug Fixes (from code review)

| ID | Fix |
|----|-----|
| F-01 | Command argument validation — reject out-of-range values with `{:error, :safety, reason}` |
| F-02 | Battery always reported as integer (`trunc/1`) |
| F-04 | Graceful `{:error, :not_connected}` for unknown drone names |
| F-06 | `Drone.Error.safety/1` used throughout Safety module (was inline tuples) |
| F-08 | Tello parser handles negative numbers (`-45`) |
| F-09 | `Policy.new(unrestricted: true)` no longer crashes |
| F-10 | `Drone.connect/2` accepts `%Policy{}` struct directly |
| Telemetry | `terminate/2` emits adapter key (`:sim`/`:tello`), not raw module name |

---

## GitHub Issues Resolved

| # | Title | Resolution |
|---|-------|------------|
| #33 | Command range validation | F-01: Safety.check validates args before policy |
| #38 | Error module unused | F-06: Drone.Error adopted throughout |
| #39 | @type drone too broad | Narrowed from `atom() \| pid()` to `atom()` |
| #40 | Parser negative numbers | F-08: Regex handles `-?\d+` |
| #41 | Policy.unrestricted crash | F-09: Fixed preset construction |
| #42 | Policy struct not accepted | F-10: connect/2 accepts `%Policy{}` or keyword |
| #43 | Tello defaults duplicated | Centralized in `Connection.default_*()` accessors |
| #44 | Vehicle.child_spec dead :id | Simplified to constant `__MODULE__` |
| #45 | query(:time) returns command count | Now returns `flight_time_seconds` |
| #47 | Weak implementation-detail tests | Strengthened with state assertions |
| #48 | Documentation issues | All resolved (see below) |
| #49 | Stale metrics, aspirational claims | Removed, corrected |
| #50 | Dead code and duplication | Removed duplication, extracted shared modules |

---

## Documentation Updates

| File | Change |
|------|--------|
| `CHANGELOG.md` | Comprehensive v0.1.0 Added/Changed/Fixed |
| `README.md` | Added Geometry to architecture, verified no stale claims |
| `docs/architecture.md` | Added Geometry module, updated command pipeline diagram |
| `docs/safety.md` | Added `%Policy{}` struct usage example |
| `docs/simulator.md` | Added flight time simulation section |
| `docs/tello.md` | Replaced FakeServer reference, documented `Connection.default_*()` |
| `mix.exs` | Added Mox dep, excluded FakeTelloServer from coverage |

---

## Quality Metrics

| Metric | Value |
|--------|-------|
| Tests | 253 passing |
| Coverage | 90.2% (threshold: 70%) |
| Credo | strict, 0 issues |
| Dialyzer | clean |
| Compiler | `--warnings-as-errors` clean |
| Format | checked |
| Source files | 19 modules, 2,565 LOC |
| Test files | 21 files, 2,434 LOC |

---

## Coverage by Module

| Module | Coverage |
|--------|----------|
| `Drone` | 96.5% |
| `Drone.Adapter` | 100% |
| `Drone.Adapters.Sim` | 97.4% |
| `Drone.Adapters.Sim.State` | 100% |
| `Drone.Adapters.Tello` | 39.1%* |
| `Drone.Adapters.Tello.Connection` | 83.3% |
| `Drone.Adapters.Tello.Encoder` | 100% |
| `Drone.Adapters.Tello.Parser` | 88.8% |
| `Drone.Command` | 100% |
| `Drone.Error` | 100% |
| `Drone.Geometry` | 100% |
| `Drone.Mission` | 95.8% |
| `Drone.Safety` | 94.1% |
| `Drone.Safety.Geofence` | 100% |
| `Drone.Safety.Policy` | 100% |
| `Drone.Supervisor` | 100% |
| `Drone.Telemetry` | 91.6% |
| `Drone.Vehicle` | 89.3% |

\* Tello adapter requires hardware/UDP; integration tests run separately.

---

## Minimum Requirements

- Elixir ~> 1.17
- Erlang/OTP 26+
- Dependency: telemetry ~> 1.0

---

## Known Limitations

- Tello adapter requires a physical drone and Wi-Fi connection (no mock UDP layer yet)
- Tello adapter coverage is low (39.1%) because connection tests need a real drone
- `safe_to_retry?/1` in `Drone.Command` documents retryability but no retry mechanism exists yet
- Mission `run/2` blocks the calling process — no async mission execution

---

## Upgrading

This is the initial release. Add to your `mix.exs`:

```elixir
def deps do
  [
    {:ex_drone, "~> 0.1.0"}
  ]
end
```

Then:

```shell
mix deps.get
```

See [Getting Started](../docs/getting_started.md) for the full walkthrough.