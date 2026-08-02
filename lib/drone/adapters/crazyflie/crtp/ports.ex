defmodule Drone.Adapters.Crazyflie.CRTP.Ports do
  @moduledoc """
  Documented CRTP port numbers for Crazyflie 2.x subsystems.

  See the [CRTP specification](https://www.bitcraze.io/documentation/repository/crazyflie-firmware/master/functional-areas/crtp/).

  ## Examples

      8 = Drone.Adapters.Crazyflie.CRTP.Ports.port(:setpoint_hl)
      9 = Drone.Adapters.Crazyflie.CRTP.Ports.port(:supervisor)
  """

  @ports %{
    console: 0x00,
    param: 0x02,
    commander: 0x03,
    mem: 0x04,
    logging: 0x05,
    localization: 0x06,
    commander_generic: 0x07,
    setpoint_hl: 0x08,
    supervisor: 0x09,
    platform: 0x0D,
    linkctrl: 0x0F
  }

  @doc """
  Returns the CRTP port integer for a named subsystem.

  ## Parameters

    * `name` (`atom()`) — one of the keys from `all/0`
      (`:setpoint_hl`, `:supervisor`, `:platform`, `:linkctrl`, …)

  ## Returns

  `0..15` port number.

  ## Raises

  `FunctionClauseError` when `name` is unknown.

  ## Examples

      13 = Drone.Adapters.Crazyflie.CRTP.Ports.port(:platform)
  """
  @spec port(atom()) :: 0..15
  def port(name) when is_map_key(@ports, name), do: Map.fetch!(@ports, name)

  @doc """
  Map of all known named ports.

  ## Returns

  `%{atom() => 0..15}`.

  ## Examples

      ports = Drone.Adapters.Crazyflie.CRTP.Ports.all()
      8 = ports.setpoint_hl
      true = Map.has_key?(ports, :supervisor)
  """
  @spec all() :: %{atom() => 0..15}
  def all, do: @ports
end
