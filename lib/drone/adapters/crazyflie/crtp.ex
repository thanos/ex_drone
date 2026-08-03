defmodule Drone.Adapters.Crazyflie.CRTP do
  @moduledoc """
  Pure CRTP packet encode/decode for Crazyflie communication.

  A CRTP packet is a 1-byte header plus a payload of at most 30 bytes.
  Header layout (matching the documented CRTP format used by Crazyflie 2.x):

      bits 7..4  port (0..15)
      bits 3..2  link (legacy; set to `0b11`)
      bits 1..0  channel (0..3)

  Null packets use port 15 / channel 3 and are used to poll the radio link.

  ## Examples

      packet = %{port: 8, channel: 0, payload: <<3, 0>>}
      {:ok, <<header, payload::binary>>} = Drone.Adapters.Crazyflie.CRTP.encode(packet)
      {:ok, ^packet} = Drone.Adapters.Crazyflie.CRTP.decode(<<header, payload::binary>>)
  """

  @max_payload 30
  @null_port 15
  @null_channel 3
  @legacy_link 0b11

  @typedoc """
  Decoded CRTP packet.

  | Field | Type | Meaning |
  | --- | --- | --- |
  | `:port` | `0..15` | CRTP port (subsystem); see `Drone.Adapters.Crazyflie.CRTP.Ports` |
  | `:channel` | `0..3` | Channel within the port |
  | `:payload` | `binary()` | 0..30 bytes of command/data |

  ## Examples

      %{port: 15, channel: 3, payload: <<>>}  # null / poll
      %{port: 8, channel: 0, payload: <<3, 0>>}  # high-level STOP, group 0
      %{port: 9, channel: 0, payload: <<0>>}  # supervisor arm
  """
  @type packet :: %{
          port: 0..15,
          channel: 0..3,
          payload: binary()
        }

  @doc """
  Maximum CRTP payload size in bytes.

  ## Returns

  `30`.

  ## Examples

      30 = Drone.Adapters.Crazyflie.CRTP.max_payload()
  """
  @spec max_payload() :: 30
  def max_payload, do: @max_payload

  @doc """
  Builds a CRTP header byte from port and channel.

  The legacy link bits are always set to `0b11`.

  ## Parameters

    * `port` (`0..15`) — CRTP port number
    * `channel` (`0..3`) — channel within the port

  ## Returns

  `byte()` header.

  ## Examples

      header = Drone.Adapters.Crazyflie.CRTP.header(15, 3)
      {15, 3} = Drone.Adapters.Crazyflie.CRTP.decode_header(header)
  """
  @spec header(0..15, 0..3) :: byte()
  def header(port, channel)
      when is_integer(port) and port in 0..15 and is_integer(channel) and channel in 0..3 do
    Bitwise.bor(
      Bitwise.bsl(Bitwise.band(port, 0x0F), 4),
      Bitwise.bor(Bitwise.bsl(@legacy_link, 2), Bitwise.band(channel, 0x03))
    )
  end

  @doc """
  Decodes a header byte into `{port, channel}`.

  ## Parameters

    * `header` (`byte()`) — first byte of a CRTP frame

  ## Returns

  `{port :: 0..15, channel :: 0..3}`.

  ## Examples

      {8, 0} = Drone.Adapters.Crazyflie.CRTP.decode_header(0x8C)
  """
  @spec decode_header(byte()) :: {0..15, 0..3}
  def decode_header(header) when is_integer(header) and header in 0..255 do
    port = Bitwise.bsr(Bitwise.band(header, 0xF0), 4)
    channel = Bitwise.band(header, 0x03)
    {port, channel}
  end

  @doc """
  Encodes a CRTP packet to a binary (`header <> payload`).

  ## Parameters

    * `packet` (`t:packet/0`) — map with `:port`, `:channel`, `:payload`

  ## Returns

    * `{:ok, binary()}` — encoded frame
    * `{:error, :oversized_payload}` — payload longer than 30 bytes
    * `{:error, :invalid_packet}` — missing or out-of-range fields

  ## Examples

      {:ok, bin} =
        Drone.Adapters.Crazyflie.CRTP.encode(%{
          port: 9,
          channel: 0,
          payload: <<0>>
        })

      {:error, :oversized_payload} =
        Drone.Adapters.Crazyflie.CRTP.encode(%{
          port: 0,
          channel: 0,
          payload: :binary.copy(<<0>>, 31)
        })
  """
  @spec encode(packet()) :: {:ok, binary()} | {:error, :oversized_payload | :invalid_packet}
  def encode(%{port: port, channel: channel, payload: payload})
      when is_integer(port) and port in 0..15 and is_integer(channel) and channel in 0..3 and
             is_binary(payload) do
    if byte_size(payload) > @max_payload do
      {:error, :oversized_payload}
    else
      {:ok, <<header(port, channel), payload::binary>>}
    end
  end

  def encode(_), do: {:error, :invalid_packet}

  @doc """
  Decodes a CRTP binary into a packet map.

  ## Parameters

    * `binary` (`binary()`) — raw CRTP frame (`header <> payload`)

  ## Returns

    * `{:ok, packet()}` — decoded packet
    * `{:error, :empty_packet}` — empty binary
    * `{:error, :invalid_packet}` — payload longer than 30 bytes or non-binary

  ## Examples

      {:ok, %{port: 15, channel: 3, payload: <<>>}} =
        Drone.Adapters.Crazyflie.CRTP.decode(<<0xFF>>)

      {:error, :empty_packet} = Drone.Adapters.Crazyflie.CRTP.decode(<<>>)
  """
  @spec decode(binary()) :: {:ok, packet()} | {:error, :empty_packet | :invalid_packet}
  def decode(<<header, payload::binary>>) when byte_size(payload) <= @max_payload do
    {port, channel} = decode_header(header)
    {:ok, %{port: port, channel: channel, payload: payload}}
  end

  def decode(<<>>), do: {:error, :empty_packet}
  def decode(_), do: {:error, :invalid_packet}

  @doc """
  True when the packet is a null/poll packet (port 15, channel 3).

  ## Parameters

    * `packet` (`t:packet/0`) — packet map

  ## Returns

  `boolean()`.

  ## Examples

      true = Drone.Adapters.Crazyflie.CRTP.null?(Drone.Adapters.Crazyflie.CRTP.null_packet())
      false = Drone.Adapters.Crazyflie.CRTP.null?(%{port: 8, channel: 0, payload: <<>>})
  """
  @spec null?(packet()) :: boolean()
  def null?(%{port: @null_port, channel: @null_channel, payload: <<>>}), do: true
  def null?(_), do: false

  @doc """
  Builds a null packet used to poll downlink when idle.

  ## Returns

  `t:packet/0` with port 15, channel 3, empty payload.

  ## Examples

      %{port: 15, channel: 3, payload: <<>>} =
        Drone.Adapters.Crazyflie.CRTP.null_packet()
  """
  @spec null_packet() :: packet()
  def null_packet, do: %{port: @null_port, channel: @null_channel, payload: <<>>}

  @doc """
  Encodes a null packet binary (single `0xFF` header with empty payload).

  ## Returns

  `binary()` — typically `<<0xFF>>`.

  ## Examples

      <<0xFF>> = Drone.Adapters.Crazyflie.CRTP.encode_null()
  """
  @spec encode_null() :: binary()
  def encode_null do
    {:ok, bin} = encode(null_packet())
    bin
  end
end
