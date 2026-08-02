defmodule Drone.Adapters.Crazyflie.Commander do
  @moduledoc """
  High-level commander CRTP payload builders (port `setpoint_hl`).

  Packet layouts follow the documented Crazyflie high-level commander
  commands (`TAKEOFF_2`, `LAND_2`, `STOP`, `GO_TO_2`). Floats are little-endian.

  These helpers return `Drone.Adapters.Crazyflie.CRTP.packet()` maps ready for
  `Session.send_packet/2`. Public `Drone` distances remain centimeters; convert
  with `Drone.Adapters.Crazyflie.Units` before calling.

  ## Examples

      packet =
        Drone.Adapters.Crazyflie.Commander.takeoff_2(0.5, 2.0,
          yaw: 0.0,
          use_current_yaw: true
        )

      8 = packet.port
      <<7, _rest::binary>> = packet.payload
  """

  alias Drone.Adapters.Crazyflie.CRTP
  alias Drone.Adapters.Crazyflie.CRTP.Ports

  @all_groups 0
  @cmd_stop 3
  @cmd_takeoff_2 7
  @cmd_land_2 8
  @cmd_go_to_2 12

  @doc """
  Builds a TAKEOFF_2 packet.

  ## Parameters

    * `height_m` (`number()`) — absolute takeoff height in **meters**
    * `duration_s` (`number()`) — maneuver duration in **seconds**
    * `opts` (`keyword()`) — optional:
      * `:group_mask` (`byte()`) — commander group mask (default `0` = all)
      * `:yaw` (`number()`) — yaw setpoint in **radians** (default `0.0`)
      * `:use_current_yaw` (`boolean()`) — keep current yaw when `true` (default)

  ## Returns

  `Drone.Adapters.Crazyflie.CRTP.packet()` on port `:setpoint_hl`, channel `0`.

  ## Examples

      packet = Drone.Adapters.Crazyflie.Commander.takeoff_2(0.4, 1.5)
      <<7, 0, _height::little-float-32, _rest::binary>> = packet.payload
  """
  @spec takeoff_2(number(), number(), keyword()) :: CRTP.packet()
  def takeoff_2(height_m, duration_s, opts \\ []) do
    group = Keyword.get(opts, :group_mask, @all_groups)
    yaw = Keyword.get(opts, :yaw, 0.0) * 1.0
    use_current_yaw = Keyword.get(opts, :use_current_yaw, true)
    height = height_m * 1.0
    duration = duration_s * 1.0

    payload =
      <<@cmd_takeoff_2, group, height::little-float-32, yaw::little-float-32,
        bool_byte(use_current_yaw), duration::little-float-32>>

    packet(payload)
  end

  @doc """
  Builds a LAND_2 packet.

  ## Parameters

    * `height_m` (`number()`) — landing height in **meters** (often `0.0`)
    * `duration_s` (`number()`) — maneuver duration in **seconds**
    * `opts` (`keyword()`) — same as `takeoff_2/3`
      (`:group_mask`, `:yaw`, `:use_current_yaw`)

  ## Returns

  `Drone.Adapters.Crazyflie.CRTP.packet()`.

  ## Examples

      packet = Drone.Adapters.Crazyflie.Commander.land_2(0.0, 2.0)
      <<8, 0, _rest::binary>> = packet.payload
  """
  @spec land_2(number(), number(), keyword()) :: CRTP.packet()
  def land_2(height_m, duration_s, opts \\ []) do
    group = Keyword.get(opts, :group_mask, @all_groups)
    yaw = Keyword.get(opts, :yaw, 0.0) * 1.0
    use_current_yaw = Keyword.get(opts, :use_current_yaw, true)
    height = height_m * 1.0
    duration = duration_s * 1.0

    payload =
      <<@cmd_land_2, group, height::little-float-32, yaw::little-float-32,
        bool_byte(use_current_yaw), duration::little-float-32>>

    packet(payload)
  end

  @doc """
  Builds a STOP packet (motors off / cancel trajectory).

  ## Parameters

    * `opts` (`keyword()`) — optional:
      * `:group_mask` (`byte()`) — default `0`

  ## Returns

  `Drone.Adapters.Crazyflie.CRTP.packet()` with payload `<<3, group>>`.

  ## Examples

      %{payload: <<3, 0>>} = Drone.Adapters.Crazyflie.Commander.stop()
  """
  @spec stop(keyword()) :: CRTP.packet()
  def stop(opts \\ []) do
    group = Keyword.get(opts, :group_mask, @all_groups)
    packet(<<@cmd_stop, group>>)
  end

  @doc """
  Builds a GO_TO_2 packet.

  ## Parameters

    * `x`, `y`, `z` (`number()`) — position in **meters** (absolute or relative)
    * `yaw` (`number()`) — yaw in **radians**
    * `duration_s` (`number()`) — maneuver duration in **seconds**
    * `opts` (`keyword()`) — optional:
      * `:group_mask` (`byte()`) — default `0`
      * `:relative` (`boolean()`) — treat XYZ as deltas when `true` (default `false`)
      * `:linear` (`boolean()`) — linear interpolation hint (default `false`)

  ## Returns

  `Drone.Adapters.Crazyflie.CRTP.packet()`.

  ## Examples

      # Relative forward 0.3 m over 1 s
      packet =
        Drone.Adapters.Crazyflie.Commander.go_to_2(
          0.0,
          0.3,
          0.0,
          0.0,
          1.0,
          relative: true
        )

      <<12, 0, 1, 0, _rest::binary>> = packet.payload
  """
  @spec go_to_2(number(), number(), number(), number(), number(), keyword()) :: CRTP.packet()
  def go_to_2(x, y, z, yaw, duration_s, opts \\ []) do
    group = Keyword.get(opts, :group_mask, @all_groups)
    relative = Keyword.get(opts, :relative, false)
    linear = Keyword.get(opts, :linear, false)
    xf = x * 1.0
    yf = y * 1.0
    zf = z * 1.0
    yawf = yaw * 1.0
    duration = duration_s * 1.0

    payload =
      <<@cmd_go_to_2, group, bool_byte(relative), bool_byte(linear), xf::little-float-32,
        yf::little-float-32, zf::little-float-32, yawf::little-float-32,
        duration::little-float-32>>

    packet(payload)
  end

  defp packet(payload) do
    %{port: Ports.port(:setpoint_hl), channel: 0, payload: payload}
  end

  defp bool_byte(true), do: 1
  defp bool_byte(false), do: 0
end
