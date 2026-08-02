defmodule Drone.Adapters.Crazyflie.Platform do
  @moduledoc """
  Platform / link-control packets for protocol identity.

  Connection sequence (documented CRTP connection procedure):

  1. Probe link with a LINKCTRL source packet.
  2. Request protocol version on PLATFORM channel 1.
  3. Parse the reply and call `check_compatibility/1`.

  ## Examples

      probe = Drone.Adapters.Crazyflie.Platform.link_probe()
      req = Drone.Adapters.Crazyflie.Platform.get_protocol_version()
      {:ok, 8} = Drone.Adapters.Crazyflie.Platform.parse_protocol_version(<<0, 8>>)
      :ok = Drone.Adapters.Crazyflie.Platform.check_compatibility(8)
  """

  alias Drone.Adapters.Crazyflie.CRTP
  alias Drone.Adapters.Crazyflie.CRTP.Ports

  @linkservice_source 1
  @version_command 1
  @version_get_protocol 0

  @min_supported 4
  @max_supported 12

  @doc """
  Minimum accepted CRTP protocol version for this adapter.

  ## Returns

  `pos_integer()` (currently `4`).

  ## Examples

      4 = Drone.Adapters.Crazyflie.Platform.min_supported()
  """
  @spec min_supported() :: pos_integer()
  def min_supported, do: @min_supported

  @doc """
  Maximum accepted CRTP protocol version for this adapter.

  ## Returns

  `pos_integer()` (currently `12`).

  ## Examples

      12 = Drone.Adapters.Crazyflie.Platform.max_supported()
  """
  @spec max_supported() :: pos_integer()
  def max_supported, do: @max_supported

  @doc """
  LINKCTRL probe packet used during connection.

  ## Returns

  `Drone.Adapters.Crazyflie.CRTP.packet()` on port `:linkctrl`, channel `1`,
  payload `<<0>>`.

  ## Examples

      %{port: 15, channel: 1, payload: <<0>>} =
        Drone.Adapters.Crazyflie.Platform.link_probe()
  """
  @spec link_probe() :: CRTP.packet()
  def link_probe do
    %{port: Ports.port(:linkctrl), channel: @linkservice_source, payload: <<0>>}
  end

  @doc """
  PLATFORM request for the CRTP protocol version.

  ## Returns

  `Drone.Adapters.Crazyflie.CRTP.packet()` on port `:platform`, channel `1`,
  payload `<<0>>` (`VERSION_GET_PROTOCOL`).

  ## Examples

      %{port: 13, channel: 1, payload: <<0>>} =
        Drone.Adapters.Crazyflie.Platform.get_protocol_version()
  """
  @spec get_protocol_version() :: CRTP.packet()
  def get_protocol_version do
    %{
      port: Ports.port(:platform),
      channel: @version_command,
      payload: <<@version_get_protocol>>
    }
  end

  @doc """
  Parses a protocol-version response payload.

  Expected shape: `<<0, version>>` where the first byte echoes
  `VERSION_GET_PROTOCOL`.

  ## Parameters

    * `payload` (`binary()`) — ACK payload from the version request

  ## Returns

    * `{:ok, non_neg_integer()}` — protocol version byte
    * `{:error, :invalid_version_response}` — unexpected shape

  ## Examples

      {:ok, 8} = Drone.Adapters.Crazyflie.Platform.parse_protocol_version(<<0, 8>>)
      {:error, :invalid_version_response} =
        Drone.Adapters.Crazyflie.Platform.parse_protocol_version(<<1, 8>>)
  """
  @spec parse_protocol_version(binary()) ::
          {:ok, non_neg_integer()} | {:error, :invalid_version_response}
  def parse_protocol_version(<<@version_get_protocol, version>>) do
    {:ok, version}
  end

  def parse_protocol_version(_), do: {:error, :invalid_version_response}

  @doc """
  Returns `:ok` when `version` is in the supported range.

  ## Parameters

    * `version` (`integer()`) — protocol version from `parse_protocol_version/1`

  ## Returns

    * `:ok` — version between `min_supported/0` and `max_supported/0` inclusive
    * `{:error, {:unsupported_protocol, version}}` — out of range or non-integer

  ## Examples

      :ok = Drone.Adapters.Crazyflie.Platform.check_compatibility(8)

      {:error, {:unsupported_protocol, 99}} =
        Drone.Adapters.Crazyflie.Platform.check_compatibility(99)
  """
  @spec check_compatibility(integer()) :: :ok | {:error, {:unsupported_protocol, integer()}}
  def check_compatibility(version)
      when is_integer(version) and version >= @min_supported and version <= @max_supported do
    :ok
  end

  def check_compatibility(version) when is_integer(version) do
    {:error, {:unsupported_protocol, version}}
  end

  def check_compatibility(_), do: {:error, {:unsupported_protocol, :unknown}}
end
