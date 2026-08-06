# Connecting to Hardware

Step-by-step guide for flying a real **DJI Tello** or **Bitcraze Crazyflie**
with ex_drone. Always validate missions on `:sim` (or Crazyflie `mock://`)
before attaching hardware.

## Safety first

- Prop guards on; clear people and obstacles
- Keep `Drone.emergency/1` reachable
- Prefer indoor policies for classrooms:

```elixir
safety: [indoor: true, prop_guards: true]
```

See the [Safety guide](safety.md).

---

## Choose your path

| Goal | Adapter | Link |
|------|---------|------|
| No hardware | `:sim` | In-process |
| Crazyflie without radio | `:crazyflie` + `mock://` | In-process |
| DJI Tello / Tello EDU | `:tello` | Wi-Fi UDP |
| Crazyflie 2.x | `:crazyflie` + `radio://` | Crazyradio USB |

---

## Tello (Wi-Fi)

### What you need

- DJI Tello or Tello EDU, charged
- Laptop with Wi-Fi (macOS, Linux, or Windows)
- Elixir ~> 1.17 / OTP 26+

### Steps

1. **Power on** the Tello. Wait for the Wi-Fi LED / network to appear.
2. **Join the drone AP.** SSID looks like `TELLO-XXXXXX`. The host gets an
   address on `192.168.10.x`; the drone is `192.168.10.1`.
3. **Confirm the link** (optional):

   ```shell
   ping 192.168.10.1
   ```

4. **Connect from Elixir:**

   ```elixir
   {:ok, drone} =
     Drone.connect(:tello,
       name: :tello_1,
       safety: [indoor: true, prop_guards: true]
     )

   :ok = Drone.connect_sdk(drone)
   {:ok, battery} = Drone.query(drone, :battery)
   IO.inspect(battery, label: "battery %")

   :ok = Drone.takeoff(drone)
   :ok = Drone.land(drone)
   :ok = Drone.disconnect(drone)
   ```

### Defaults and overrides

| Option | Default | Meaning |
|--------|---------|---------|
| `drone_ip` | `{192, 168, 10, 1}` | Tello address |
| `drone_port` | `8889` | Command port |
| `local_port` | `8889` | Local UDP bind |
| `timeout` | `10_000` | Command timeout (ms) |

```elixir
Drone.connect(:tello,
  name: :tello_1,
  drone_ip: {192, 168, 10, 1},
  drone_port: 8889,
  local_port: 9030,
  timeout: 15_000
)
```

### Tello troubleshooting

| Symptom | Likely fix |
|---------|------------|
| Connect hangs / `:timeout` | Rejoin `TELLO-*` Wi-Fi; close apps using UDP 8889 |
| `error` replies | Send `connect_sdk` before flight commands |
| Intermittent drops | Stay close; avoid crowded 2.4 GHz; power-cycle Tello |
| EDU station mode | Point `drone_ip` at the drone’s LAN address |

More detail: [Tello guide](tello.md).

---

## Crazyflie (mock first, then radio)

### What you need (hardware path)

- Crazyflie 2.1 / 2.1+ with a **positioning** setup (Flow Deck, Lighthouse, or Loco)
- Crazyradio PA or Crazyradio 2.0
- A module implementing `Drone.Adapters.Crazyflie.USB` (libusb binding — not
  bundled in the Hex package)
- Linux or macOS (Windows experimental)

### Practice without hardware

```elixir
{:ok, drone} =
  Drone.connect(:crazyflie,
    name: :cf_1,
    uri: "mock://ready",
    positioning: :flow,
    safety: [indoor: true]
  )

:ok = Drone.connect_sdk(drone)
:ok = Drone.takeoff(drone)
:ok = Drone.move(drone, :forward, 40)
:ok = Drone.land(drone)
:ok = Drone.disconnect(drone)
```

```shell
mix run examples/crazyflie_mock_flight.exs
```

### Radio setup checklist

1. **Install OS permissions** for the Crazyradio (Linux example):

   ```text
   # /etc/udev/rules.d/99-crazyradio.rules
   SUBSYSTEM=="usb", ATTRS{idVendor}=="1915", ATTRS{idProduct}=="7777", MODE="0666"
   ```

   Then: `sudo udevadm control --reload-rules && sudo udevadm trigger`

2. **Plug in** the Crazyradio. Confirm the OS sees USB vendor `1915` / product `7777`.
3. **Match RF settings** to the copter (channel, datarate, 5-byte address). Defaults
   in ex_drone URIs follow Bitcraze’s common `E7E7E7E7E7` address.
4. **Implement or wire** a `usb_backend` that satisfies
   `Drone.Adapters.Crazyflie.USB` (`discover/1`, `open/2`, control + bulk I/O,
   `close/1`).
5. **Connect:**

   ```elixir
   {:ok, drone} =
     Drone.connect(:crazyflie,
       name: :cf_1,
       uri: "radio://0/80/2M/E7E7E7E7E7?safelink=1",
       positioning: :flow,
       usb_backend: MyApp.CrazyradioUSB,
       safety: [
         indoor: true,
         require_estimator: true,
         max_telemetry_age_ms: 500
       ]
     )

   :ok = Drone.connect_sdk(drone)
   {:ok, battery} = Drone.query(drone, :battery)
   :ok = Drone.takeoff(drone)
   :ok = Drone.land(drone)
   :ok = Drone.disconnect(drone)
   ```

### URI cheat sheet

```text
radio://<radio_index>/<channel>/<datarate>/<address>?safelink=1&timeout=1000
```

| Piece | Example | Notes |
|-------|---------|-------|
| `radio_index` | `0` | First Crazyradio |
| `channel` | `80` | 0–125 (Crazyradio 2.0: 0–100) |
| `datarate` | `2M` | `250K`, `1M`, or `2M` |
| `address` | `E7E7E7E7E7` | 5-byte hex |
| `safelink=1` | optional | Negotiate Bitcraze SafeLink |
| `timeout` | `1000` | USB bulk timeout (ms) |

`positioning:` must be `:flow`, `:lighthouse`, or `:loco` (default `:flow`).

### What connect does on radio

1. Open USB / configure channel, address, rate
2. Optional SafeLink enable when `safelink=1`
3. Protocol version handshake (accepted range **4–12**)
4. CRTP logging subscribe for `pm.batteryLevel` (or `pm.vbat`) and `sys.canfly`
5. Warm the log cache so takeoff readiness can pass

Until the first log packet arrives, battery / estimator may be `nil` and motion
commands fail with `:telemetry_unavailable`.

### Crazyflie troubleshooting

| Symptom | Likely fix |
|---------|------------|
| `:usb_backend_unavailable` | Pass `usb_backend:` implementing `Drone.Adapters.Crazyflie.USB` |
| `:crazyradio_not_found` | Dongle unplugged / udev permissions / wrong index |
| `:safelink_enable_failed` | Copter/radio out of range; retry or drop `safelink=1` |
| `:unsupported_protocol` | Update Crazyflie firmware into CRTP 4–12 |
| `:estimator_not_ready` | Wait for Flow/Lighthouse/Loco convergence |
| `:telemetry_unavailable` | Logging not ready yet; poll `Drone.telemetry/1` / retry takeoff |
| `:no_ack` / `:link_lost` | Wrong channel/address; move closer; check antenna |

More detail: [Crazyflie guide](crazyflie.md).

---

## Shared flight checklist

1. Fly the same mission on `:sim` or `mock://ready`
2. Set `safety: [indoor: true, …]` for real props
3. Query battery before takeoff
4. Keep emergency available: `Drone.emergency(drone)`
5. Land and `Drone.disconnect/1` when done

Portable missions can preflight against `Drone.capabilities/1` via
`Drone.Mission.validate_capabilities/2`.
---

## Next steps

- [Getting Started](getting_started.md) — install and simulator first flight
- [Tello](tello.md) — UDP options and protocol notes
- [Crazyflie](crazyflie.md) — logging, SafeLink, readiness gates
- [Safety](safety.md) — policies and geofencing
- [Further Reading](further_reading.md) — SDK and CRTP references
