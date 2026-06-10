# v0.1.0 Review Checklist

## Purpose

This document answers the six critical review questions before implementation begins. Implementation must not start until all questions are answered affirmatively.

---

## 1. Is the simulator useful without hardware?

**Yes.**

- The simulator (`Drone.Adapters.Sim`) runs entirely in-process with no UDP, no network, and no external dependencies
- It implements the same `Drone.Adapter` behaviour as the Tello adapter
- It tracks position (x, y, z, yaw), battery, and state machine
- It supports configurable failure injection for testing error scenarios
- It enforces the same safety rules as real adapters
- All documentation examples use the simulator
- All tests can run without hardware

Verification criteria:
- [ ] A user can run `Drone.connect(:sim, name: :test)` with no hardware connected
- [ ] A complete mission (takeoff -> move -> rotate -> land) works in simulator
- [ ] Safety violations are detected in simulation
- [ ] All tests pass without a drone on the network

---

## 2. Can all public APIs be tested without a drone?

**Yes.**

- Every public API call flows through the `Drone.Vehicle` GenServer
- The GenServer uses the `Drone.Adapter` behaviour for all drone communication
- The simulator adapter provides a complete in-process implementation
- The Tello adapter can be tested with a fake UDP server (also in-process)
- The `Drone.Safety` module is pure and takes explicit inputs

| API Call            | Test Approach                                    |
|----------------------|--------------------------------------------------|
| `Drone.connect/2`   | Test with `:sim` adapter                          |
| `Drone.takeoff/1`   | Test with simulator                               |
| `Drone.move/3`      | Test with simulator                               |
| `Drone.rotate/3`    | Test with simulator                               |
| `Drone.land/1`      | Test with simulator                               |
| `Drone.emergency/1` | Test with simulator                               |
| `Drone.query/2`     | Test with simulator                               |
| `Drone.telemetry/1` | Test with simulator                               |
| `Drone.disconnect/1`| Test with simulator                               |
| `Drone.Safety.check/3` | Pure function test                             |

Verification criteria:
- [ ] Every public function has at least one test using the simulator
- [ ] No test requires a physical drone on the network
- [ ] The fake UDP server enables testing the Tello adapter without hardware

---

## 3. Are dangerous commands protected by safety rules?

**Yes.**

- The safety pipeline runs before every non-emergency command
- Emergency commands bypass safety (by design -- they MUST go through)
- Movement commands are validated against max altitude and max distance
- Takeoff is blocked below minimum battery
- Command allowlists restrict available commands
- Geofence prevents flight outside allowed areas
- All safety rejections emit telemetry events

| Dangerous Scenario              | Safety Check                                      |
|---------------------------------|---------------------------------------------------|
| Fly above max altitude          | Rejected by max_altitude_cm check                  |
| Fly beyond max distance          | Rejected by max_distance_cm check                  |
| Takeoff with low battery        | Rejected by min_battery_percent check              |
| Unauthorized command            | Rejected by allowlist check                        |
| Leave geofenced area            | Rejected by geofence check                         |
| Flip without prop guards        | Warning by prop_guards check                       |

Verification criteria:
- [ ] Every safety rule has a dedicated test that verifies rejection
- [ ] Emergency commands are never blocked by safety rules
- [ ] All safety rejections include a descriptive reason atom

---

## 4. Are errors explicit and useful?

**Yes.**

All errors use explicit tuples with descriptive atoms:

| Error Format                       | When                                              |
|------------------------------------|----------------------------------------------------|
| `{:error, :safety, reason}`        | Safety pipeline rejected command                   |
| `{:error, :timeout}`               | Drone did not respond within timeout               |
| `{:error, :connection_error}`      | Could not establish connection                     |
| `{:error, :command_error}`          | Drone returned `error` response                    |
| `{:error, :not_in_sdk_mode}`       | Command sent before `command`                      |
| `{:error, :not_flying}`            | Movement command sent while grounded               |
| `{:error, :already_flying}`        | Takeoff sent while already airborne                |
| `{:error, :emergency_active}`      | Command sent while in emergency state               |
| `{:error, :low_battery}`           | Battery too low for takeoff                        |
| `{:error, :max_altitude}`          | Would exceed altitude limit                        |
| `{:error, :max_distance}`          | Would exceed distance limit                         |
| `{:error, :geofence_violation}`    | Would leave geofenced area                         |
| `{:error, :command_not_allowed}`   | Command not on allowlist                            |
| `{:error, :invalid_command}`       | Command has invalid arguments                       |
| `{:error, :simulated_failure}`     | Sim adapter configured failure                     |

No exceptions are raised for expected error conditions. All errors follow the `{:error, reason}` or `{:error, category, reason}` pattern.

Verification criteria:
- [ ] All error paths return explicit error tuples
- [ ] No unexpected exceptions in normal operation
- [ ] Error reasons are documented in `Drone.Error`
- [ ] Error tuples are pattern-matchable for users

---

## 5. Can the Tello adapter be replaced without changing user code?

**Yes.**

- User code calls `Drone.connect(:sim, ...)` or `Drone.connect(:tello, ...)`
- The adapter is selected at connection time, not in user code
- All subsequent API calls (`takeoff`, `move`, `rotate`, etc.) are adapter-agnostic
- The `Drone.Adapter` behaviour defines the contract
- Switching adapters requires only changing the first argument of `Drone.connect/2`

```elixir
# Simulation
{:ok, drone} = Drone.connect(:sim, name: :test)

# Real Tello  
{:ok, drone} = Drone.connect(:tello, name: :tello_1)

# Exact same API from here on
Drone.takeoff(drone)
Drone.move(drone, :forward, 100)
Drone.land(drone)
```

Verification criteria:
- [ ] The simulator and Tello adapter implement the same behaviour
- [ ] User code that works with `:sim` works identically with `:tello`
- [ ] Custom adapters can be created by implementing `Drone.Adapter`
- [ ] The adapter contract documentation is complete (`docs/adapter_authoring.md`)

---

## 6. Does the architecture support Crazyflie and MAVLink later?

**Yes.**

- `Drone.Adapter` is a behaviour that any adapter can implement
- Crazyflie will add `Drone.Adapters.Crazyflie` in v0.3.0
- MAVLink will add `Drone.Adapters.MAVLink` in v0.4.0
- The Vehicle GenServer knows nothing about UDP, ports, or protocols -- it only knows the adapter behaviour
- Safety, telemetry, and mission features are adapter-independent
- New adapters only need to:
  1. Implement `connect/1`, `command/2`, `telemetry/1`, `disconnect/1`
  2. Be registered in the adapter map
  3. Handle their own transport layer

Potential concerns for future adapters:

| Concern                         | Addressed By                                      |
|---------------------------------|----------------------------------------------------|
| More telemetry fields           | Adapter telemetry map is open-ended                 |
| Different connection patterns   | `connect/1` receives arbitrary keyword options      |
| Binary protocols (MAVLink)      | Encoder/decoder hidden in adapter                   |
| Async telemetry (MAVLink)       | Can push to Vehicle via `handle_info`               |
| Multiple connections (swarm)    | Each drone is a separate Vehicle process           |

Verification criteria:
- [ ] The adapter behaviour does not assume UDP or any specific transport
- [ ] The adapter behaviour does not assume text-based commands
- [ ] Telemetry maps can include arbitrary fields
- [ ] The Crazyflie adapter design note exists in `docs/research/crazyflie.md` (v0.3.0)
- [ ] The MAVLink design note exists in `docs/research/mavlink.md` (v0.4.0)

---

## Implementation Readiness Checklist

Before any code is written, the following must exist:

- [x] Research: `docs/research/tello_sdk.md`
- [x] Research: `docs/research/beam_udp.md`
- [x] Research: `docs/research/safety_model.md`
- [x] Research: `docs/research/simulator_design.md`
- [x] Design: `docs/design/v0_1_0_plan.md`
- [x] Design: `docs/design/adapter_contract.md`
- [x] Design: `docs/design/safety_pipeline.md`
- [x] Design: `docs/design/telemetry_events.md`
- [x] Review: `docs/reviews/v0_1_0_review_checklist.md`

## Pre-Implementation Gate

All six review questions must be answered "Yes" with verification criteria.

| # | Question                                                | Answer |
|---|---------------------------------------------------------|--------|
| 1 | Is the simulator useful without hardware?                | Yes    |
| 2 | Can all public APIs be tested without a drone?          | Yes    |
| 3 | Are dangerous commands protected by safety rules?        | Yes    |
| 4 | Are errors explicit and useful?                          | Yes    |
| 5 | Can the Tello adapter be replaced without changing code? | Yes    |
| 6 | Does the architecture support future adapters?           | Yes    |

**Gate status: PASS. Implementation may begin.**