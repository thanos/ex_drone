# v0.3.0 Deferred Work — Crazyflie & Adapter Backlog

This document records items from v0.3.0 planning that are **intentionally left
out of this release**. Absence from the Hex package is not an oversight; it is
the backlog seed for later milestones.

Suggested roadmap homes are indicative, not commitments.

## Shipped in v0.3.0 (for contrast)

| Item | Status |
|------|--------|
| Single Crazyflie via Crazyradio / `mock://` | Shipped |
| High-level commander (takeoff / land / go-to / stop) | Shipped |
| CRTP logging subscribe for battery + `sys.canfly` | Shipped |
| Optional SafeLink (`?safelink=1`) | Shipped |
| Pluggable `usb_backend` (no bundled libusb NIF) | Shipped |
| Optional `capabilities/1` + `Drone.capabilities/1` | Shipped |
| Capability-aware mission preflight | Shipped |
| Estimator / telemetry-age safety options | Shipped |

## Deferred — Crazyflie platform

| Item | Why deferred | Suggested home |
|------|--------------|----------------|
| BLE link | Separate stack from Crazyradio; different pairing / reliability story | v0.4+ |
| Direct Crazyflie USB (no Crazyradio) | Different USB framing; niche for lab benches | Later adapter variant |
| Raw attitude / rate setpoints | Outside the high-level public API; easy to misuse | Advanced API or research |
| Trajectory upload / memory subsystem | Large CRTP surface; needs memory TOC | Later milestone |
| Parameter read/write | Separate TOC; not required for HL flight | Later milestone |
| Firmware flashing | Host tooling, not flight control | Out of library scope or companion tool |
| Arbitrary custom log blocks | Only readiness block is wired; general logger is a product | Later milestone |
| Multi-Crazyflie / Crazyflie + `Drone.Swarm` | Radio scheduling, address management, shared channel | After single-drone hardening |
| Bundled libusb NIF in Hex package | Native deps break portable CI; keep pluggable | Optional companion package |

## Deferred — shared adapter / vehicle resilience

These were listed under the v0.3.0 “Adapters & Resilience” roadmap theme but
are not required to ship a credible Crazyflie adapter:

| Item | Notes | Suggested home |
|------|-------|----------------|
| `Drone.Adapters.MAVLink` | Large protocol; separate design | v0.4+ |
| Adapter registry (`register/2`) | Third-party discovery | Later |
| Command retry / backoff | Needs `safe_to_retry?/1` policy per command | Later |
| `Mission.run_async/2` | Progress events + cancellation | Later |
| Vehicle auto-reconnect | Network / radio loss recovery | Later |
| Tello state recovery on reconnect | Re-query SDK / battery / pose | Later |
| Configurable per-vehicle command timeout | Default 10s today | Later |

## Deferred — swarm (carried from v0.2.0)

Crazyflie does not change the v0.2.0 swarm non-goals. Live flocking, closed-loop
formation hold, and absolute Tello choreography remain deferred — see
[v0.2.0 Deferred Work](v0_2_0_deferred.md). Multi-Crazyflie under `Drone.Swarm`
is explicitly still out of scope for v0.3.0.

## Hardware / CI stance

| Concern | v0.3.0 decision |
|---------|-----------------|
| Default CI | `mock://` only — no radio hardware required |
| Real `radio://` | User supplies `usb_backend` implementing `Drone.Adapters.Crazyflie.USB` |
| HIL | Optional / external; not part of Hex CI matrix |

## How to use this document

1. Prefer this catalogue over ad-hoc scope creep in PRs.
2. When promoting an item into a milestone, move or check it off here and update
   the README roadmap.
3. Do not implement deferred items opportunistically inside a patch release
   without updating this file and the changelog.
