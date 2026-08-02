defmodule Drone.Adapters.Crazyflie.Transport.Mock do
  @moduledoc """
  In-process Crazyflie transport for CI and dry development.

  Profiles (via `mock://PROFILE` or `:mock_profile`):

  * `:default` / `:ready` — healthy estimator, full battery
  * `:estimator_not_ready` — rejects takeoff readiness
  * `:low_battery` — reports low battery percent
  * `:unplug` — next send fails with `:link_lost`

  Simulates link probe, protocol version, supervisor, and high-level commander
  replies so `Session.connect/2` and adapter commands work without hardware.

  ## Examples

      {:ok, state} =
        Drone.Adapters.Crazyflie.Transport.Mock.open(uri: "mock://ready")

      {:ok, %{acked: true}, state} =
        Drone.Adapters.Crazyflie.Transport.Mock.send(
          state,
          Drone.Adapters.Crazyflie.CRTP.null_packet()
        )

      :ok = Drone.Adapters.Crazyflie.Transport.Mock.close(state)
  """

  @behaviour Drone.Adapters.Crazyflie.Transport

  alias Drone.Adapters.Crazyflie.CRTP
  alias Drone.Adapters.Crazyflie.CRTP.Ports
  alias Drone.Adapters.Crazyflie.LinkURI

  @typedoc """
  In-memory mock radio / Crazyflie state.

  | Field | Type | Meaning |
  | --- | --- | --- |
  | `:profile` | `atom()` | Active mock profile |
  | `:protocol_version` | `integer()` | Version returned to platform queries |
  | `:battery_percent` | `integer()` | Reported battery |
  | `:estimator_ready` | `boolean()` | Takeoff gate |
  | `:armed` | `boolean()` | Supervisor arm flag |
  | `:flying` | `boolean()` | After successful takeoff |
  | `:x`, `:y`, `:z` | `float()` | Position in **meters** |
  | `:yaw` | `float()` | Yaw in **radians** |
  | `:unplugged` | `boolean()` | When true, `send/2` returns `:link_lost` |
  | `:sent` | `[CRTP.packet()]` | Packets observed (newest first) |

  ## Example

      %Drone.Adapters.Crazyflie.Transport.Mock{
        profile: :ready,
        protocol_version: 8,
        battery_percent: 95,
        estimator_ready: true,
        flying: false,
        z: 0.0
      }
  """
  @type t :: %__MODULE__{
          profile: atom() | nil,
          protocol_version: integer(),
          battery_percent: integer(),
          estimator_ready: boolean(),
          armed: boolean(),
          flying: boolean(),
          x: float(),
          y: float(),
          z: float(),
          yaw: float(),
          unplugged: boolean(),
          sent: [CRTP.packet()]
        }

  defstruct [
    :profile,
    protocol_version: 8,
    battery_percent: 95,
    estimator_ready: true,
    armed: false,
    flying: false,
    x: 0.0,
    y: 0.0,
    z: 0.0,
    yaw: 0.0,
    unplugged: false,
    sent: []
  ]

  @doc """
  Opens a mock transport with a profile from opts or URI.

  ## Parameters

    * `opts` (`keyword()`) — `:uri` (`"mock://ready"`), or `:mock_profile`

  ## Returns

  `{:ok, t()}`.

  ## Examples

      {:ok, state} =
        Drone.Adapters.Crazyflie.Transport.Mock.open(uri: "mock://low_battery")

      10 = state.battery_percent
  """
  @impl true
  def open(opts) do
    profile = resolve_profile(opts)

    state =
      %__MODULE__{profile: profile}
      |> apply_profile(profile)

    {:ok, state}
  end

  @doc """
  Handles CRTP packets and returns synthetic ACKs.

  Recognizes null, linkctrl probe, platform version, supervisor, and
  high-level commander packets. Unknown packets ACK with an empty payload.

  ## Parameters

    * `state` (`t:t/0`) — mock state
    * `packet` (`CRTP.packet()`) — packet to process

  ## Returns

  `Drone.Adapters.Crazyflie.Transport.send_result()`.

  ## Examples

      {:ok, %{payload: <<0, 8>>}, state} =
        Drone.Adapters.Crazyflie.Transport.Mock.send(
          state,
          Drone.Adapters.Crazyflie.Platform.get_protocol_version()
        )
  """
  @impl true
  def send(%__MODULE__{unplugged: true} = state, _packet) do
    {:error, :link_lost, state}
  end

  def send(%__MODULE__{} = state, %{port: port, channel: channel, payload: payload} = packet) do
    state = %{state | sent: [packet | state.sent]}

    cond do
      CRTP.null?(packet) ->
        {:ok, %{acked: true, retries: 0, payload: <<>>}, state}

      port == Ports.port(:linkctrl) and channel == 1 ->
        reply = "Bitcraze Crazyflie"
        {:ok, %{acked: true, retries: 0, payload: reply}, state}

      port == Ports.port(:platform) and channel == 1 ->
        reply = <<0, state.protocol_version>>
        {:ok, %{acked: true, retries: 0, payload: reply}, state}

      port == Ports.port(:supervisor) ->
        handle_supervisor(state, payload)

      port == Ports.port(:setpoint_hl) ->
        handle_commander(state, payload)

      true ->
        {:ok, %{acked: true, retries: 0, payload: <<>>}, state}
    end
  end

  @doc """
  Closes the mock transport (no resources to release).

  ## Parameters

    * `state` (`t:t/0`)

  ## Returns

  Always `:ok`.
  """
  @impl true
  def close(%__MODULE__{}), do: :ok

  @doc false
  def force_unplug(%__MODULE__{} = state), do: %{state | unplugged: true}

  defp resolve_profile(opts) do
    cond do
      opts[:mock_profile] ->
        opts[:mock_profile]

      is_binary(opts[:uri]) ->
        case LinkURI.parse(opts[:uri]) do
          {:ok, %{mock_profile: profile}} -> profile
          _ -> :default
        end

      true ->
        :default
    end
  end

  defp apply_profile(state, :estimator_not_ready), do: %{state | estimator_ready: false}
  defp apply_profile(state, :low_battery), do: %{state | battery_percent: 10}
  defp apply_profile(state, :unplug), do: %{state | unplugged: true}
  defp apply_profile(state, _), do: %{state | estimator_ready: true, battery_percent: 95}

  defp handle_supervisor(state, <<0>>), do: {:ok, ack(), %{state | armed: true}}
  defp handle_supervisor(state, <<1>>), do: {:ok, ack(), %{state | armed: false, flying: false}}

  defp handle_supervisor(state, <<2>>),
    do: {:ok, ack(), %{state | armed: false, flying: false, z: 0.0}}

  defp handle_supervisor(state, _), do: {:ok, ack(), state}

  defp handle_commander(state, <<7, _group, height::little-float-32, _rest::binary>>) do
    if state.estimator_ready do
      {:ok, ack(), %{state | flying: true, armed: true, z: height}}
    else
      {:error, :estimator_not_ready, state}
    end
  end

  defp handle_commander(state, <<8, _group, height::little-float-32, _rest::binary>>) do
    {:ok, ack(), %{state | flying: false, z: height, armed: false}}
  end

  defp handle_commander(state, <<3, _group>>) do
    {:ok, ack(), %{state | flying: false, armed: false}}
  end

  defp handle_commander(
         state,
         <<12, _g, relative, _linear, x::little-float-32, y::little-float-32, z::little-float-32,
           yaw::little-float-32, _dur::little-float-32>>
       ) do
    {nx, ny, nz} =
      if relative == 1 do
        {state.x + x, state.y + y, state.z + z}
      else
        {x, y, z}
      end

    {:ok, ack(), %{state | x: nx, y: ny, z: nz, yaw: yaw}}
  end

  defp handle_commander(state, _), do: {:ok, ack(), state}

  defp ack, do: %{acked: true, retries: 0, payload: <<>>}
end
