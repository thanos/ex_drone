defmodule Drone.Adapters.Crazyflie.SupervisorCmd do
  @moduledoc """
  Supervisor subsystem packets (CRTP port 9).

  Provides arm, disarm, and emergency stop encodings used by the adapter.
  Channel 0 carries control requests.

  ## Examples

      %{port: 9, channel: 0, payload: <<0>>} =
        Drone.Adapters.Crazyflie.SupervisorCmd.arm()
  """

  alias Drone.Adapters.Crazyflie.CRTP
  alias Drone.Adapters.Crazyflie.CRTP.Ports

  # Documented supervisor request ids used by Crazyflie 2.x firmware.
  @cmd_arm 0
  @cmd_disarm 1
  @cmd_emergency 2

  @doc """
  Builds an arm request packet.

  ## Returns

  `Drone.Adapters.Crazyflie.CRTP.packet()` with payload `<<0>>`.

  ## Examples

      packet = Drone.Adapters.Crazyflie.SupervisorCmd.arm()
      <<0>> = packet.payload
  """
  @spec arm() :: CRTP.packet()
  def arm, do: packet(<<@cmd_arm>>)

  @doc """
  Builds a disarm request packet.

  ## Returns

  `Drone.Adapters.Crazyflie.CRTP.packet()` with payload `<<1>>`.

  ## Examples

      <<1>> = Drone.Adapters.Crazyflie.SupervisorCmd.disarm().payload
  """
  @spec disarm() :: CRTP.packet()
  def disarm, do: packet(<<@cmd_disarm>>)

  @doc """
  Builds an emergency stop request packet.

  ## Returns

  `Drone.Adapters.Crazyflie.CRTP.packet()` with payload `<<2>>`.

  ## Examples

      <<2>> = Drone.Adapters.Crazyflie.SupervisorCmd.emergency().payload
  """
  @spec emergency() :: CRTP.packet()
  def emergency, do: packet(<<@cmd_emergency>>)

  defp packet(payload) do
    %{port: Ports.port(:supervisor), channel: 0, payload: payload}
  end
end
