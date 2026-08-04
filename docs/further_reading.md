# Further Reading

Curated references for the ideas behind ex_drone: platforms and adapters,
safety, geometry, mission planning, and multi-drone formations. Prefer the
in-repo guides for how this library works; use the external sources for
background and next steps.

## In this repository

### Guides

| Guide | Topic |
|-------|-------|
| [Getting Started](getting_started.md) | Install, first simulator flight, Tello connect |
| [Connecting to Hardware](connecting.md) | Step-by-step Tello Wi-Fi and Crazyflie Crazyradio |
| [Safety](safety.md) | Policies, geofencing, allowlists, emergency |
| [Simulator](simulator.md) | In-process adapter, battery, failure injection, initial pose |
| [Tello](tello.md) | DJI Tello / Tello EDU UDP adapter |
| [Crazyflie](crazyflie.md) | Crazyflie 2.x via Crazyradio / mock transport |
| [Swarms](swarm.md) | `Drone.Swarm` membership, fan-out, fail-fast |
| [Formations](formations.md) | Geometric formation catalog and planners |
| [Architecture](architecture.md) | Modules, supervision tree, design rationale |
| [Adapter Authoring](adapter_authoring.md) | Implementing `Drone.Adapter` |

### Design notes

| Document | Topic |
|----------|-------|
| [Adapter Contract](design/adapter_contract.md) | Behaviour expectations for adapters |
| [Safety Pipeline](design/safety_pipeline.md) | Validation stages and policy model |
| [Telemetry Events](design/telemetry_events.md) | Vehicle and swarm `:telemetry` events |
| [v0.2.0 Deferred Work](design/v0_2_0_deferred.md) | Intentionally postponed swarm features |
| [v0.3.0 Deferred Work](design/v0_3_0_deferred.md) | Intentionally postponed Crazyflie / adapter items |

### Research notes

| Document | Topic |
|----------|-------|
| [Tello SDK](research/tello_sdk.md) | Command set and protocol notes |
| [BEAM UDP](research/beam_udp.md) | UDP on the BEAM for drone links |
| [Safety Model](research/safety_model.md) | Why safety sits on each vehicle |
| [Simulator Design](research/simulator_design.md) | Deterministic sim for tests and teaching |
| [Swarm Coordination](research/swarm_coordination.md) | OTP coordinator model and formation scope |

## Platforms and adapters

ex_drone talks to vehicles through the `Drone.Adapter` behaviour. v0.3.0
ships an in-process simulator, a DJI Tello UDP adapter, and a Crazyflie
adapter (Crazyradio with pluggable USB backend, plus `mock://` for CI).

- [DJI Tello SDK 2.0 User Guide (PDF)](https://dl-cdn.ryzerobotics.com/downloads/Tello/Tello%20SDK%202.0%20User%20Guide.pdf) - official command and response reference for Tello / Tello EDU
- [Ryze Tello product page](https://www.ryzerobotics.com/tello) - hardware overview and EDU variants
- [Bitcraze Crazyflie documentation](https://www.bitcraze.io/documentation/) - research quadrotor platform
- [CRTP specification](https://www.bitcraze.io/documentation/repository/crazyflie-firmware/master/functional-areas/crtp/) - Crazyflie packet protocol
- [Crazyradio USB protocol](https://www.bitcraze.io/documentation/repository/crazyradio-firmware/master/functional-areas/usb_radio_protocol/) - radio dongle framing
- [MAVLink protocol](https://mavlink.io/en/) - common message set used by many autopilots (planned adapter)
- [ArduPilot documentation](https://ardupilot.org/) - autopilot stack often paired with MAVLink
- [PX4 User Guide](https://docs.px4.io/) - autopilot stack often paired with MAVLink
- [Nerves Project](https://nerves-project.org/) - Elixir on embedded devices (roadmap: on-drone or companion hosting)

In-repo: [Tello guide](tello.md), [Crazyflie guide](crazyflie.md), [Adapter authoring](adapter_authoring.md),
[Adapter contract](design/adapter_contract.md), [Tello SDK research](research/tello_sdk.md),
[BEAM UDP research](research/beam_udp.md).

## Safety

ex_drone validates every command in a pure safety pipeline before it reaches
an adapter. Emergency stop bypasses normal checks on purpose.

- Leveson, N. G. *Engineering a Safer World: Systems Thinking Applied to Safety*. MIT Press, 2011.
- ISO 12100:2010 - Safety of machinery, general principles for design and risk assessment
- ASTM F38 committee materials on unmanned aircraft systems standards (overview via [ASTM](https://www.astm.org/get-involved/technical-committees/committee-f38))
- FAA / local aviation authority recreational and educational UAS rules for your region

In-repo: [Safety guide](safety.md), [Safety pipeline](design/safety_pipeline.md),
[Safety model research](research/safety_model.md).

## Geometry and frames

Sim and vehicle math share one heading convention: yaw `0` faces `+Y`,
with forward/right deltas from that frame.

- Craig, J. J. *Introduction to Robotics: Mechanics and Control*. Pearson.
- LaValle, S. M. *Planning Algorithms*. Cambridge University Press, 2006. Free online: [http://lavalle.pl/planning/](http://lavalle.pl/planning/)
- Standard references on rotation conventions and body vs world frames in mobile robotics textbooks

In-repo: architecture notes on shared geometry helpers, [Simulator guide](simulator.md),
[Simulator design](research/simulator_design.md).

## Missions and planners

Missions are ordered command scripts. Formations are **one-shot geometric
planners** that emit per-drone missions; they are not closed-loop controllers.

- LaValle, S. M. *Planning Algorithms* (motion planning survey and methods)
- Choset, H. et al. *Principles of Robot Motion*. MIT Press.
- Mission / waypoint patterns in ArduPilot and PX4 documentation (external platforms)

In-repo: [Formations](formations.md), [Getting started](getting_started.md),
mission usage in the `Drone` and `Drone.Mission` module docs.

## Swarming, formations, and strategies

v0.2.0 ships geometric formations with plan-time separation only. Continuous
flocking (Separate / Align / Cohere), live collision avoidance, and alternate
failure policies are catalogued as deferred work.

- Reynolds, C. W. "Flocks, Herds, and Schools: A Distributed Behavioral Model."
  *Computer Graphics* (SIGGRAPH), 1987. Classic boids rules.
- Balch, T., and Arkin, R. C. "Behavior-based formation control for multirobot teams."
  *IEEE Transactions on Robotics and Automation*, 14(6), 1998.
- Ren, W., and Beard, R. W. *Distributed Consensus in Multi-vehicle Cooperative Control*.
  Springer, 2008.
- Brambilla, M., Ferrante, E., Birattari, M., and Dorigo, M. "Swarm robotics: a review from the swarm engineering perspective."
  *Swarm Intelligence*, 7, 2013.
- Şahin, E. "Swarm robotics: From sources of inspiration to domains of application."
  In *Swarm Robotics*, Springer LNCS, 2005.
- Oh, K.-K., Park, M.-C., and Ahn, H.-S. "A survey of multi-agent formation control."
  *Automatica*, 53, 2015.

In-repo: [Swarms](swarm.md), [Formations](formations.md),
[Swarm coordination research](research/swarm_coordination.md),
[Deferred swarm work](design/v0_2_0_deferred.md).

## Tello and classroom hardware

- [DJI Tello SDK 2.0 User Guide (PDF)](https://dl-cdn.ryzerobotics.com/downloads/Tello/Tello%20SDK%202.0%20User%20Guide.pdf)
- [Ryze Robotics Tello](https://www.ryzerobotics.com/tello)
- Tello EDU station mode helps multi-drone Wi-Fi connectivity; it does not by
  itself provide a shared global pose suitable for absolute choreography

In-repo: [Tello guide](tello.md), [Tello SDK research](research/tello_sdk.md),
hardware caveats in [Swarms](swarm.md).

## BEAM, OTP, and telemetry

ex_drone uses one GenServer per vehicle, registries for naming, dynamic
supervisors for membership, and the standard Elixir `:telemetry` library.

- [OTP Design Principles](https://www.erlang.org/doc/system/design_principles.html)
- [Elixir GenServer](https://hexdocs.pm/elixir/GenServer.html)
- [Registry](https://hexdocs.pm/elixir/Registry.html)
- [DynamicSupervisor](https://hexdocs.pm/elixir/DynamicSupervisor.html)
- [telemetry](https://hexdocs.pm/telemetry/)
- Armstrong, J. *Programming Erlang*. Pragmatic Bookshelf.
- Cesarini, F., and Vinoski, S. *Designing for Scalability with Erlang/OTP*. O'Reilly.

In-repo: [Architecture](architecture.md), [Telemetry events](design/telemetry_events.md),
[BEAM UDP research](research/beam_udp.md).

## Related platforms (roadmap context)

Crazyflie single-drone support ships in v0.3.0. The links below remain useful
for classroom comparisons and for adapters that are still on the roadmap
(MAVLink, companion-computer hosting, …).

- [Bitcraze Crazyflie docs](https://www.bitcraze.io/documentation/)
- [MAVLink](https://mavlink.io/en/)
- [ArduPilot](https://ardupilot.org/)
- [PX4](https://docs.px4.io/)
- [Nerves](https://nerves-project.org/)

Deferred Crazyflie / adapter items: [v0.3.0 Deferred Work](design/v0_3_0_deferred.md).
