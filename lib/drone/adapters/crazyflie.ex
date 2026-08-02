defmodule Drone.Adapters.Crazyflie do
  @moduledoc """
  Crazyflie 2.x adapter over Crazyradio (or an in-process mock transport).

  Implements `Drone.Adapter`. Prefer connecting through `Drone.connect/2`
  rather than calling this module directly.

  ## Supported configuration (v0.3.0)

  * Crazyflie 2.1 / 2.1+ with a documented CRTP protocol version
  * Crazyradio PA / Crazyradio 2.0 via a pluggable USB backend
  * High-level position commands with a positioning system (`:flow`, `:lighthouse`, `:loco`)
  * One Crazyflie per adapter process

  ## Connection options

  | Option | Type | Default | Meaning |
  | --- | --- | --- | --- |
  | `:uri` | `String.t()` | `"mock://ready"` | Link URI (`mock://…` or `radio://…`) |
  | `:transport` | `module()` | from URI | Override transport module |
  | `:usb_backend` | `module()` | `USB.Unavailable` | Required for `radio://` |
  | `:positioning` | `atom()` | `:flow` | Positioning system label |
  | `:default_height_cm` | `pos_integer()` | `50` | Takeoff height in centimeters |
  | `:default_speed_cm_s` | `pos_integer()` | `50` | Horizontal move speed |

  ## Connection

      {:ok, drone} =
        Drone.connect(:crazyflie,
          name: :cf_1,
          uri: "mock://ready",
          positioning: :flow,
          default_height_cm: 50
        )

      :ok = Drone.connect_sdk(drone)

  `connect_sdk/1` is a documented no-op that succeeds for mission compatibility.
  Real radio URIs require `usb_backend: YourUSBModule` implementing
  `Drone.Adapters.Crazyflie.USB`.

  ## Deferred

  BLE, direct Crazyflie USB flight control, raw attitude setpoints, trajectory
  upload, parameter editing, firmware flashing, and multi-Crazyflie swarms.
  """

  @behaviour Drone.Adapter

  alias Drone.Adapter.Capabilities

  alias Drone.Adapters.Crazyflie.{
    Commander,
    Session,
    SupervisorCmd,
    Transport,
    Units
  }

  alias Drone.Command

  @typedoc """
  Crazyflie adapter state held by `Drone.Vehicle`.

  | Field | Type | Meaning |
  | --- | --- | --- |
  | `:session` | `Drone.Adapters.Crazyflie.Session.t()` | Open CRTP session |
  | `:uri` | `String.t()` | Connection URI used at open |
  | `:positioning` | `atom()` | `:flow`, `:lighthouse`, `:loco`, … |
  | `:default_height_cm` | `integer()` | Takeoff target height (cm) |
  | `:default_speed_cm_s` | `integer()` | Initial move speed (cm/s) |
  | `:move_speed_cm_s` | `integer()` | Current move speed (updated by `:speed`) |
  | `:protocol_version` | `integer()` \\| `nil` | Negotiated CRTP protocol version |
  | `:capabilities` | `Drone.Adapter.Capabilities.t()` | Advertised capabilities |
  | `:mode` | `atom()` | `:idle`, `:sdk_mode`, `:flying`, `:emergency` |
  | `:flying` | `boolean()` | Whether a takeoff is considered active |
  | `:armed` | `boolean()` | Supervisor arm state |
  | `:x`, `:y`, `:z` | `integer()` | Estimated position in centimeters |
  | `:yaw` | `integer()` | Yaw in degrees |
  | `:battery` | `integer()` | Battery percent 0..100 |
  | `:estimator_ready` | `boolean()` | Positioning estimator readiness |
  | `:link_quality` | `integer()` | Link quality percent (best-effort) |
  | `:telemetry_at` | `integer()` \\| `nil` | Monotonic ms of last telemetry touch |
  | `:firmware` | `String.t()` | Firmware label when known |
  | `:last_error` | `term()` \\| `nil` | Most recent link/command error |

  ## Example

      %Drone.Adapters.Crazyflie{
        uri: "mock://ready",
        positioning: :flow,
        default_height_cm: 50,
        mode: :flying,
        flying: true,
        z: 50,
        battery: 95,
        estimator_ready: true,
        protocol_version: 8
      }
  """
  @type t :: %__MODULE__{
          session: Session.t() | nil,
          uri: String.t() | nil,
          positioning: atom() | nil,
          default_height_cm: integer() | nil,
          default_speed_cm_s: integer() | nil,
          move_speed_cm_s: integer() | nil,
          protocol_version: integer() | nil,
          capabilities: Capabilities.t() | nil,
          mode: atom(),
          flying: boolean(),
          armed: boolean(),
          x: integer(),
          y: integer(),
          z: integer(),
          yaw: integer(),
          battery: integer(),
          estimator_ready: boolean(),
          link_quality: integer(),
          telemetry_at: integer() | nil,
          firmware: String.t(),
          last_error: term() | nil
        }

  defstruct [
    :session,
    :uri,
    :positioning,
    :default_height_cm,
    :default_speed_cm_s,
    :move_speed_cm_s,
    :protocol_version,
    :capabilities,
    mode: :idle,
    flying: false,
    armed: false,
    x: 0,
    y: 0,
    z: 0,
    yaw: 0,
    battery: 100,
    estimator_ready: true,
    link_quality: 100,
    telemetry_at: nil,
    firmware: "mock",
    last_error: nil
  ]

  @doc """
  Opens a Crazyflie link and returns initial adapter state.

  Resolves a transport via `Transport.resolve/1`, runs the CRTP handshake
  through `Session.connect/2`, and seeds telemetry (including mock profile
  values when using the mock transport).

  ## Parameters

    * `opts` (`keyword()`) — see Connection options in the moduledoc

  ## Returns

    * `{:ok, t()}` — connected adapter state
    * `{:error, term()}` — URI, USB, or handshake failure

  ## Examples

      {:ok, state} =
        Drone.Adapters.Crazyflie.connect(
          uri: "mock://ready",
          positioning: :flow,
          default_height_cm: 40
        )

      true = state.estimator_ready
  """
  @impl true
  def connect(opts) do
    uri = Keyword.get(opts, :uri, "mock://ready")
    positioning = Keyword.get(opts, :positioning, :flow)
    default_height_cm = Keyword.get(opts, :default_height_cm, 50)
    default_speed = Keyword.get(opts, :default_speed_cm_s, 50)

    with {:ok, transport_mod} <- Transport.resolve(opts),
         {:ok, session} <- Session.connect(transport_mod, Keyword.put(opts, :uri, uri)) do
      state = %__MODULE__{
        session: session,
        uri: uri,
        positioning: positioning,
        default_height_cm: default_height_cm,
        default_speed_cm_s: default_speed,
        move_speed_cm_s: default_speed,
        protocol_version: session.protocol_version,
        capabilities: Capabilities.crazyflie(positioning: positioning),
        telemetry_at: System.monotonic_time(:millisecond)
      }

      {:ok, sync_mock_telemetry(state)}
    end
  end

  @doc """
  Returns Crazyflie capability metadata for the connected state.

  ## Parameters

    * `state` (`t:t/0`) — adapter state from `connect/1`

  ## Returns

  `Drone.Adapter.Capabilities.t()` (includes `:requires_estimator`, `:link`).

  ## Examples

      caps = Drone.Adapters.Crazyflie.capabilities(state)
      :fire_and_forget = caps.maneuver_completion
  """
  @impl true
  def capabilities(%__MODULE__{capabilities: caps}), do: caps

  @doc """
  Executes a normalized `Drone.Command` over CRTP.

  Supported types include `:sdk_mode` (no-op success), `:takeoff`, `:land`,
  `:emergency`, `:move`, `:rotate`, `:stop`, `:hover`, `:speed`, and `:query`.
  `:flip` returns `{:error, :unsupported_command, state}`.

  Takeoff arms the supervisor, then sends high-level `TAKEOFF_2`. Land and
  emergency use commander/supervisor packets. Moves and rotates use relative
  `GO_TO_2` with unit conversion via `Units`.

  ## Parameters

    * `state` (`t:t/0`) — current adapter state
    * `command` (`Drone.Command.t()`) — command from the vehicle pipeline

  ## Returns

    * `{:ok, reply, t()}` — `reply` is usually `:ok` or a query value
    * `{:error, reason, t()}` — readiness, link, or unsupported command

  ## Examples

      {:ok, :ok, state} =
        Drone.Adapters.Crazyflie.command(state, Drone.Command.takeoff())

      {:ok, pct, state} =
        Drone.Adapters.Crazyflie.command(
          state,
          Drone.Command.query(:battery)
        )
  """
  @impl true
  def command(%__MODULE__{} = state, %Command{type: :sdk_mode}) do
    # Crazyflie has no SDK mode; succeed so shared missions remain portable.
    {:ok, :ok, %{state | mode: :sdk_mode}}
  end

  def command(%__MODULE__{} = state, %Command{type: :takeoff}) do
    with :ok <- readiness_gate(state),
         {:ok, state} <- send_packet(state, SupervisorCmd.arm()),
         height_m <- Units.cm_to_m(state.default_height_cm),
         duration <- max(height_m / 0.5, 1.0),
         {:ok, state} <- send_packet(state, Commander.takeoff_2(height_m, duration)) do
      {:ok, :ok,
       %{
         state
         | flying: true,
           armed: true,
           mode: :flying,
           z: state.default_height_cm,
           telemetry_at: now()
       }}
    else
      {:error, reason, state} -> {:error, reason, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  def command(%__MODULE__{} = state, %Command{type: :land}) do
    duration = max(Units.cm_to_m(state.z) / 0.5, 1.0)

    with {:ok, state} <- send_packet(state, Commander.land_2(0.0, duration)),
         {:ok, state} <- send_packet(state, SupervisorCmd.disarm()) do
      {:ok, :ok,
       %{state | flying: false, armed: false, mode: :sdk_mode, z: 0, telemetry_at: now()}}
    end
  end

  def command(%__MODULE__{} = state, %Command{type: :emergency}) do
    case send_packet(state, SupervisorCmd.emergency()) do
      {:ok, state} ->
        {:ok, :ok,
         %{state | flying: false, armed: false, mode: :emergency, z: 0, telemetry_at: now()}}

      {:error, reason, state} ->
        # Emergency must still surface link loss rather than fake a land.
        {:error, reason, %{state | last_error: reason, mode: :emergency, flying: false}}
    end
  end

  def command(%__MODULE__{} = state, %Command{type: :move, args: args}) do
    direction = Keyword.fetch!(args, :direction)
    distance = Keyword.fetch!(args, :distance)
    {dx_cm, dy_cm, dz_cm} = move_delta_cm(direction, distance)
    duration = Units.move_duration_s(distance, state.move_speed_cm_s)

    packet =
      Commander.go_to_2(
        Units.cm_to_m(dx_cm),
        Units.cm_to_m(dy_cm),
        Units.cm_to_m(dz_cm),
        0.0,
        duration,
        relative: true
      )

    case send_packet(state, packet) do
      {:ok, state} ->
        {:ok, :ok,
         %{
           state
           | x: state.x + dx_cm,
             y: state.y + dy_cm,
             z: max(0, state.z + dz_cm),
             telemetry_at: now()
         }}

      other ->
        other
    end
  end

  def command(%__MODULE__{} = state, %Command{type: :rotate, args: args}) do
    direction = Keyword.fetch!(args, :direction)
    degrees = Keyword.fetch!(args, :degrees)
    signed = if direction == :cw, do: degrees, else: -degrees
    yaw_rad = Units.deg_to_rad(signed)
    duration = max(abs(degrees) / 90.0, 0.5)

    packet = Commander.go_to_2(0.0, 0.0, 0.0, yaw_rad, duration, relative: true)

    case send_packet(state, packet) do
      {:ok, state} ->
        new_yaw = rem(state.yaw + signed + 360, 360)
        {:ok, :ok, %{state | yaw: new_yaw, telemetry_at: now()}}

      other ->
        other
    end
  end

  def command(%__MODULE__{} = state, %Command{type: :stop}) do
    case send_packet(state, Commander.stop()) do
      {:ok, state} -> {:ok, :ok, %{state | telemetry_at: now()}}
      other -> other
    end
  end

  def command(%__MODULE__{} = state, %Command{type: :hover}) do
    {:ok, :ok, %{state | telemetry_at: now()}}
  end

  def command(%__MODULE__{} = state, %Command{type: :speed, args: args}) do
    speed = Keyword.fetch!(args, :speed)
    {:ok, :ok, %{state | move_speed_cm_s: speed}}
  end

  def command(%__MODULE__{} = state, %Command{type: :flip}) do
    {:error, :unsupported_command, state}
  end

  def command(%__MODULE__{} = state, %Command{type: :query, args: args}) do
    case Keyword.fetch!(args, :type) do
      :battery -> {:ok, state.battery, touch(state)}
      :height -> {:ok, state.z, touch(state)}
      :sdk_version -> {:ok, state.protocol_version, touch(state)}
      :serial_number -> {:ok, "mock-cf", touch(state)}
      :speed -> {:ok, state.move_speed_cm_s, touch(state)}
      other -> {:error, {:unsupported_query, other}, state}
    end
  end

  def command(state, _cmd), do: {:error, :unsupported_command, state}

  @doc """
  Returns a telemetry snapshot for the vehicle safety / state machine.

  When the session uses the mock transport, fields are synced from mock
  kinematics (meters/radians → cm/degrees).

  ## Parameters

    * `state` (`t:t/0`) — current adapter state

  ## Returns

    * `{:ok, map(), t()}` — map includes `:x`, `:y`, `:z`, `:yaw`, `:battery`,
      `:flying`, `:mode`, `:estimator_ready`, `:link_quality`, `:positioning`,
      `:protocol_version`, `:firmware`, `:telemetry_at`

  ## Examples

      {:ok, telem, state} = Drone.Adapters.Crazyflie.telemetry(state)
      true = is_integer(telem.battery)
  """
  @impl true
  def telemetry(%__MODULE__{} = state) do
    state = sync_mock_telemetry(state)

    {:ok,
     %{
       x: state.x,
       y: state.y,
       z: state.z,
       yaw: state.yaw,
       battery: state.battery,
       flying: state.flying,
       mode: state.mode,
       estimator_ready: state.estimator_ready,
       link_quality: state.link_quality,
       positioning: state.positioning,
       protocol_version: state.protocol_version,
       firmware: state.firmware,
       telemetry_at: state.telemetry_at || now()
     }, state}
  end

  @doc """
  Closes the CRTP session and releases the transport.

  ## Parameters

    * `state` (`t:t/0`) — final adapter state

  ## Returns

  Always `:ok`.

  ## Examples

      :ok = Drone.Adapters.Crazyflie.disconnect(state)
  """
  @impl true
  def disconnect(%__MODULE__{session: session}) do
    Session.close(session)
    :ok
  end

  defp readiness_gate(%__MODULE__{} = state) do
    cond do
      state.battery < 15 -> {:error, :low_battery}
      not state.estimator_ready -> {:error, :estimator_not_ready}
      is_nil(state.telemetry_at) -> {:error, :stale_telemetry}
      true -> :ok
    end
  end

  defp send_packet(%__MODULE__{session: session} = state, packet) do
    case Session.send_packet(session, packet) do
      {:ok, _ack, new_session} ->
        {:ok, %{state | session: new_session, telemetry_at: now()}}

      {:error, reason, new_session} ->
        {:error, reason, %{state | session: new_session, last_error: reason}}
    end
  end

  defp sync_mock_telemetry(%__MODULE__{session: %{transport_state: ts}} = state)
       when is_struct(ts, Drone.Adapters.Crazyflie.Transport.Mock) do
    %{
      state
      | battery: ts.battery_percent,
        estimator_ready: ts.estimator_ready,
        x: Units.m_to_cm(ts.x),
        y: Units.m_to_cm(ts.y),
        z: Units.m_to_cm(ts.z),
        yaw: Units.rad_to_deg(ts.yaw),
        flying: ts.flying,
        armed: ts.armed,
        telemetry_at: now()
    }
  end

  defp sync_mock_telemetry(state), do: state

  defp move_delta_cm(:forward, d), do: {0, d, 0}
  defp move_delta_cm(:back, d), do: {0, -d, 0}
  defp move_delta_cm(:left, d), do: {-d, 0, 0}
  defp move_delta_cm(:right, d), do: {d, 0, 0}
  defp move_delta_cm(:up, d), do: {0, 0, d}
  defp move_delta_cm(:down, d), do: {0, 0, -d}

  defp touch(state), do: %{state | telemetry_at: now()}
  defp now, do: System.monotonic_time(:millisecond)
end
