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

  alias Drone.{Command, Geometry}

  @supported_positioning [:flow, :lighthouse, :loco]

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
          battery: integer() | nil,
          estimator_ready: boolean() | nil,
          link_quality: integer() | nil,
          telemetry_at: integer() | nil,
          firmware: String.t() | nil,
          serial_number: String.t() | nil,
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
    # nil until transport.telemetry/1 reports a value (fail closed on radio).
    battery: nil,
    estimator_ready: nil,
    link_quality: nil,
    telemetry_at: nil,
    firmware: nil,
    serial_number: nil,
    last_error: nil
  ]

  @doc """
  Opens a Crazyflie link and returns initial adapter state.

  Resolves a transport via `Transport.resolve/1`, runs the CRTP handshake
  through `Session.connect/2`, and seeds telemetry via optional
  `c:Transport.telemetry/1`.
  """
  @impl true
  def connect(opts) do
    uri = Keyword.get(opts, :uri, "mock://ready")
    positioning = Keyword.get(opts, :positioning, :flow)
    default_height_cm = Keyword.get(opts, :default_height_cm, 50)
    default_speed = Keyword.get(opts, :default_speed_cm_s, 50)

    with :ok <- validate_positioning(positioning),
         :ok <- validate_height(default_height_cm),
         {:ok, transport_mod} <- Transport.resolve(opts),
         {:ok, session} <- Session.connect(transport_mod, Keyword.put(opts, :uri, uri)) do
      state = %__MODULE__{
        session: session,
        uri: uri,
        positioning: positioning,
        default_height_cm: default_height_cm,
        default_speed_cm_s: default_speed,
        move_speed_cm_s: default_speed,
        protocol_version: session.protocol_version,
        capabilities:
          Capabilities.crazyflie(
            positioning: positioning,
            takeoff_height_cm: default_height_cm
          ),
        telemetry_at: System.monotonic_time(:millisecond)
      }

      {:ok, sync_transport_telemetry(state)}
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
    with {:ok, state} <- readiness_gate(state),
         {:ok, armed_state} <- send_packet(state, SupervisorCmd.arm()),
         height_m <- Units.cm_to_m(armed_state.default_height_cm),
         duration <- max(height_m / 0.5, 1.0) do
      case send_packet(armed_state, Commander.takeoff_2(height_m, duration)) do
        {:ok, state} ->
          {:ok, :ok,
           %{
             state
             | flying: true,
               armed: true,
               mode: :flying,
               z: state.default_height_cm,
               telemetry_at: now()
           }}

        {:error, reason, state} ->
          state = best_effort_disarm(state)
          {:error, reason, state}
      end
    end
  end

  def command(%__MODULE__{} = state, %Command{type: :land}) do
    with {:ok, state} <- readiness_gate(state),
         duration <- max(Units.cm_to_m(max(state.z, 1)) / 0.5, 1.0),
         {:ok, state} <- send_packet(state, Commander.land_2(0.0, duration)),
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
        # Do not claim the vehicle landed when the packet was not acknowledged.
        {:error, reason, %{state | last_error: reason, mode: :emergency}}
    end
  end

  def command(%__MODULE__{} = state, %Command{type: :move, args: args}) do
    with {:ok, state} <- readiness_gate(state) do
      direction = Keyword.fetch!(args, :direction)
      distance = Keyword.fetch!(args, :distance)
      {dx_cm, dy_cm, dz_cm} = Geometry.move_delta(direction, distance, state.yaw)
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
  end

  def command(%__MODULE__{} = state, %Command{type: :rotate, args: args}) do
    with {:ok, state} <- readiness_gate(state) do
      direction = Keyword.fetch!(args, :direction)
      degrees = Keyword.fetch!(args, :degrees)
      signed = if direction == :cw, do: degrees, else: -degrees
      yaw_rad = Units.deg_to_rad(signed)
      duration = max(abs(degrees) / 90.0, 0.5)

      packet = Commander.go_to_2(0.0, 0.0, 0.0, yaw_rad, duration, relative: true)

      case send_packet(state, packet) do
        {:ok, state} ->
          new_yaw = Geometry.rotate_yaw(direction, state.yaw, degrees)
          {:ok, :ok, %{state | yaw: new_yaw, telemetry_at: now()}}

        other ->
          other
      end
    end
  end

  def command(%__MODULE__{} = state, %Command{type: :stop}) do
    case send_packet(state, Commander.stop()) do
      {:ok, state} -> {:ok, :ok, %{state | telemetry_at: now()}}
      other -> other
    end
  end

  def command(%__MODULE__{} = state, %Command{type: :hover, args: args}) do
    seconds = Keyword.get(args, :seconds, 1) * 1.0

    packet = Commander.go_to_2(0.0, 0.0, 0.0, 0.0, seconds, relative: true)

    case send_packet(state, packet) do
      {:ok, state} -> {:ok, :ok, %{state | telemetry_at: now()}}
      other -> other
    end
  end

  def command(%__MODULE__{} = state, %Command{type: :speed, args: args}) do
    speed = Keyword.fetch!(args, :speed)
    {:ok, :ok, %{state | move_speed_cm_s: speed}}
  end

  def command(%__MODULE__{} = state, %Command{type: :flip}) do
    {:error, :unsupported_command, state}
  end

  def command(%__MODULE__{} = state, %Command{type: :query, args: args}) do
    state = sync_transport_telemetry(state)

    case Keyword.fetch!(args, :type) do
      :battery ->
        if is_integer(state.battery) do
          {:ok, state.battery, touch(state)}
        else
          {:error, :telemetry_unavailable, state}
        end

      :height ->
        {:ok, state.z, touch(state)}

      :sdk_version ->
        {:ok, state.protocol_version, touch(state)}

      :serial_number ->
        if is_binary(state.serial_number) do
          {:ok, state.serial_number, touch(state)}
        else
          {:error, :telemetry_unavailable, state}
        end

      :speed ->
        {:ok, state.move_speed_cm_s, touch(state)}

      other ->
        {:error, {:unsupported_query, other}, state}
    end
  end

  def command(state, _cmd), do: {:error, :unsupported_command, state}

  @doc """
  Returns a telemetry snapshot for the vehicle safety / state machine.

  Transport-reported readiness fields are synced via optional
  `c:Transport.telemetry/1`. Pose (`x`/`y`/`z`/`yaw`) is maintained by the
  adapter from commanded moves.
  """
  @impl true
  def telemetry(%__MODULE__{} = state) do
    state = sync_transport_telemetry(state)

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
       takeoff_height_cm: state.default_height_cm,
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
    state = sync_transport_telemetry(state)

    cond do
      is_nil(state.battery) or is_nil(state.estimator_ready) ->
        {:error, :telemetry_unavailable, state}

      state.battery < 15 ->
        {:error, :low_battery, state}

      state.estimator_ready != true ->
        {:error, :estimator_not_ready, state}

      is_nil(state.telemetry_at) ->
        {:error, :stale_telemetry, state}

      true ->
        {:ok, state}
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

  defp best_effort_disarm(state) do
    case send_packet(state, SupervisorCmd.disarm()) do
      {:ok, state} ->
        %{state | armed: false}

      {:error, _reason, state} ->
        %{state | armed: false, last_error: :disarm_after_failed_takeoff}
    end
  end

  defp sync_transport_telemetry(%__MODULE__{session: session} = state) do
    mod = session.transport_module
    _ = Code.ensure_loaded(mod)

    if function_exported?(mod, :telemetry, 1) do
      case mod.telemetry(session.transport_state) do
        {:ok, telem, new_ts} when is_map(telem) ->
          state = %{state | session: %{session | transport_state: new_ts}}
          apply_transport_telem(state, telem)

        _ ->
          state
      end
    else
      state
    end
  end

  defp apply_transport_telem(state, telem) do
    state
    |> put_if_present(telem, :battery)
    |> put_if_present(telem, :estimator_ready)
    |> put_if_present(telem, :flying)
    |> put_if_present(telem, :armed)
    |> put_if_present(telem, :firmware)
    |> put_if_present(telem, :serial_number)
    |> put_if_present(telem, :link_quality)
    |> Map.put(:telemetry_at, now())
  end

  defp put_if_present(state, telem, key) do
    if Map.has_key?(telem, key) do
      Map.put(state, key, Map.get(telem, key))
    else
      state
    end
  end

  defp validate_positioning(pos) when pos in @supported_positioning, do: :ok
  defp validate_positioning(other), do: {:error, {:unsupported_positioning, other}}

  defp validate_height(h) when is_integer(h) and h > 0, do: :ok
  defp validate_height(other), do: {:error, {:invalid_default_height_cm, other}}

  defp touch(state), do: %{state | telemetry_at: now()}
  defp now, do: System.monotonic_time(:millisecond)
end
