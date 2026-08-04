# Crazyflie Adapter

The `Drone.Adapters.Crazyflie` adapter flies a single Crazyflie 2.x through
Crazyradio (or an in-process mock transport for CI and dry development).

## Supported configuration (v0.3.0)

| Item | Support |
|------|---------|
| Airframe | Crazyflie 2.1 / 2.1+ |
| Link | Crazyradio PA, Crazyradio 2.0 |
| Host OS | Linux and macOS (Windows experimental) |
| Commands | takeoff, land, emergency, move, rotate, stop, hover, battery/height queries |
| Positioning | Required (`:flow`, `:lighthouse`, or `:loco`; validated at connect) |
| Process model | One Crazyflie per adapter / vehicle process |
| Telemetry | Mock + radio report battery/estimator via CRTP logging (`pm.batteryLevel`, `sys.canfly`) |

**Not in this release:** BLE, direct Crazyflie USB flight control, raw attitude
setpoints, trajectory upload, parameter editing, firmware flashing, arbitrary
log-block customization beyond the built-in readiness subscription, and
multi-Crazyflie swarms.

## Mock connection (no hardware)

```elixir
{:ok, drone} =
  Drone.connect(:crazyflie,
    name: :cf_1,
    uri: "mock://ready",
    positioning: :flow,
    default_height_cm: 50
  )

:ok = Drone.connect_sdk(drone)
{:ok, battery} = Drone.query(drone, :battery)
:ok = Drone.takeoff(drone)
:ok = Drone.move(drone, :forward, 50)
:ok = Drone.rotate(drone, :cw, 90)
:ok = Drone.land(drone)
:ok = Drone.disconnect(drone)
```

`connect_sdk/1` is a documented no-op that succeeds so shared missions stay
portable across Tello, Sim, and Crazyflie.

Mock URI profiles:

| URI | Behaviour |
|-----|-----------|
| `mock://ready` / `mock://default` | Healthy estimator, full battery |
| `mock://estimator_not_ready` | Takeoff rejected |
| `mock://low_battery` | Takeoff rejected |
| `mock://unplug` | Link lost on send |

## Radio connection

```elixir
{:ok, drone} =
  Drone.connect(:crazyflie,
    name: :cf_1,
    uri: "radio://0/80/2M/E7E7E7E7E7",
    positioning: :flow,
    usb_backend: MyApp.CrazyradioUSB
  )
```

`usb_backend` must implement `Drone.Adapters.Crazyflie.USB`. Without it,
`radio://` URIs return `{:error, :usb_backend_unavailable}`. The default
backend is intentionally unavailable so Hex packages do not require native
USB NIFs; wire your own libusb binding for hardware.

### URI format

```text
radio://<radio_index>/<channel>/<datarate>/<address>?safelink=1&timeout=1000
```

- `radio_index` — Crazyradio ordinal (0 for the first dongle)
- `channel` — 0–125 (Crazyradio 2.0: 0–100)
- `datarate` — `250K`, `1M`, or `2M`
- `address` — 5-byte hex radio address (default `E7E7E7E7E7`)
- `safelink=1` — negotiate Bitcraze SafeLink on open (default off)
- `timeout` — USB bulk timeout in milliseconds

## Positioning and readiness

High-level position commands need a working estimator (Flow Deck, Lighthouse,
or Loco Positioning). Pass `positioning: :flow | :lighthouse | :loco` (default
`:flow`). Unknown values fail at connect with
`{:error, {:unsupported_positioning, value}}`.

The adapter readiness gate (takeoff, land, move, rotate) checks:

- transport-reported battery (reject when unknown or below 15%)
- `estimator_ready == true` (reject when unknown/false)
- a non-nil telemetry timestamp

Emergency bypasses the readiness gate.

On connect, the session downloads the logging TOC and starts a block for
`pm.batteryLevel` (or `pm.vbat`) plus `sys.canfly`. Radio `telemetry/1` reads
that cache; until the first log-data packet arrives, battery/estimator stay
`nil` and motion commands fail closed with `:telemetry_unavailable`.

Safety policies can also enforce the same gates for motion commands:

```elixir
Drone.connect(:crazyflie,
  name: :cf_safe,
  uri: "mock://ready",
  safety: [
    require_estimator: true,
    max_telemetry_age_ms: 500
  ]
)
```

When `max_telemetry_age_ms` is set, a missing `telemetry_at` is treated as stale.

## Units

| Quantity | Public API | Crazyflie packets |
|----------|------------|-------------------|
| Distance | centimeters | meters |
| Angle | degrees | radians |
| Duration | seconds (missions / hover) | seconds in commander packets |

## Linux USB permissions

Create `/etc/udev/rules.d/99-crazyradio.rules`:

```
SUBSYSTEM=="usb", ATTRS{idVendor}=="1915", ATTRS{idProduct}=="7777", MODE="0666"
```

Then reload rules: `sudo udevadm control --reload-rules && sudo udevadm trigger`.

## macOS notes

Install a working libusb stack for your USB backend (Homebrew `libusb` is
common). Grant the terminal / IDE USB access if the OS prompts. Prefer
testing with `mock://` before attaching a radio.

## Firmware / protocol compatibility

The adapter accepts CRTP protocol versions **4–12**. Unsupported versions
fail at connect with `{:error, {:unsupported_protocol, version}}`.

Keep firmware within the range documented by Bitcraze for high-level
commander (`TAKEOFF_2`, `LAND_2`, `GO_TO_2`).

## Safety checklist

1. Test the mission on `mock://ready` first
2. Confirm positioning deck / system is calibrated
3. Clear prop / people hazards
4. Keep `Drone.emergency/1` reachable
5. Treat radio unplug / link loss as unknown flight state — never as a
   successful land

## Capability differences

| Feature | Sim | Tello | Crazyflie |
|---------|-----|-------|-----------|
| SDK mode | required | required | optional no-op |
| Flip | yes | yes | unsupported |
| Positioning | dead-reckoning | dead-reckoning | estimator + deck |
| Link | in-process | Wi-Fi UDP | Crazyradio USB |

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| `:usb_backend_unavailable` | No `usb_backend` module for `radio://` |
| `:crazyradio_not_found` | Dongle missing / permissions |
| `:estimator_not_ready` | Flow/Lighthouse/Loco not converged |
| `:stale_telemetry` | Telemetry timestamp missing/old when age limit is set |
| `:telemetry_unavailable` | Radio transport has no battery/estimator snapshot yet |
| `:link_lost` / `:no_ack` | Out of range, wrong channel/address, or unplug |
| Mission `{:unsupported_command, :flip}` | Capability preflight rejected flip |

## Further Reading

- Step-by-step radio / mock connect: [Connecting to Hardware](connecting.md)
- Deferred scope: [v0.3.0 Deferred Work](design/v0_3_0_deferred.md)
- Research-style refs: [Further Reading — Platforms](further_reading.md#platforms-and-adapters)
- Official: [CRTP](https://www.bitcraze.io/documentation/repository/crazyflie-firmware/master/functional-areas/crtp/), [Crazyradio USB](https://www.bitcraze.io/documentation/repository/crazyradio-firmware/master/functional-areas/usb_radio_protocol/), [Logging](https://www.bitcraze.io/documentation/repository/crazyflie-firmware/master/functional-areas/crtp/crtp_log/)
