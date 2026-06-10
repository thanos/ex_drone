# Tello Adapter

The `Drone.Adapters.Tello` adapter communicates with DJI Tello and Tello EDU drones over Wi-Fi UDP.

## Prerequisites

- DJI Tello or Tello EDU drone
- Wi-Fi connection to the drone's network (SSID: `TELLO-XXXXXX`)

## Connecting

```elixir
{:ok, drone} = Drone.connect(:tello, name: :tello_1)
Drone.connect_sdk(drone)
Drone.takeoff(drone)
Drone.move(drone, :forward, 100)
Drone.land(drone)
Drone.disconnect(drone)
```

## Custom Configuration

```elixir
{:ok, drone} = Drone.connect(:tello, name: :tello_1,
  drone_ip: {192, 168, 10, 1},
  drone_port: 8889,
  local_port: 9030,
  timeout: 15_000
)
```

Defaults (configured in `Drone.Adapters.Tello.Connection`):

- Drone IP: `192.168.10.1` (`Connection.default_drone_ip/0`)
- Drone port: `8889` (`Connection.default_drone_port/0`)
- Local port: `8889` (`Connection.default_local_port/0`)
- Command timeout: `10_000` ms (`Connection.default_timeout/0`)

## Protocol

The Tello SDK uses plain ASCII text commands over UDP. The adapter handles:

- Encoding `Drone.Command` structs to Tello command strings
- Sending commands via `:gen_udp` and receiving responses
- Parsing Tello responses (`ok`, `error`, numeric values)
- Command timeout handling

## Testing

The Tello adapter can be tested without hardware using the simulator or by
directly calling the adapter functions with a simulated UDP socket. See the
test suite in `test/drone/adapters/tello/` for examples.

## Safety

Always use safety policies when flying a real drone:

```elixir
{:ok, drone} = Drone.connect(:tello, name: :tello_1,
  safety: [indoor: true, prop_guards: true]
)
```

**Warning**: The Tello is a real physical drone. Always test in the simulator first. Use prop guards. Do not fly near faces.