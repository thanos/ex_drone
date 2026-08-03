defmodule Drone.Adapters.Crazyflie.SafeLink do
  @moduledoc """
  Bitcraze SafeLink helpers for Crazyradio CRTP framing.

  SafeLink uses the two reserved link bits in the CRTP header as alternating
  uplink / downlink counters so neither side silently drops ACK payloads.

  Enable negotiation (raw USB bytes, not a normal CRTP encode):

      <<0xFF, 0x05, 0x01>>

  Success when the ACK data echoes the same three bytes. Framing then stamps:

      header = (header &&& 0xF3) ||| (up <<< 3) ||| (down <<< 2)

  Counters advance only on ACK: uplink always flips; downlink flips when the
  ACK payload header carries the expected downlink bit.
  """

  import Bitwise

  @enable <<0xFF, 0x05, 0x01>>
  @disable <<0xFF, 0x05, 0x00>>

  @doc "Raw USB enable packet (`<<0xFF, 0x05, 0x01>>`)."
  @spec enable_packet() :: <<_::24>>
  def enable_packet, do: @enable

  @doc "Raw USB disable packet (`<<0xFF, 0x05, 0x00>>`)."
  @spec disable_packet() :: <<_::24>>
  def disable_packet, do: @disable

  @doc """
  True when ACK downlink data echoes the enable packet.
  """
  @spec enabled_echo?(binary()) :: boolean()
  def enabled_echo?(@enable), do: true
  def enabled_echo?(_), do: false

  @doc """
  Stamps SafeLink uplink/downlink bits into a CRTP header byte.
  """
  @spec stamp_header(byte(), 0 | 1, 0 | 1) :: byte()
  def stamp_header(header, up, down)
      when is_integer(header) and header in 0..255 and up in [0, 1] and down in [0, 1] do
    header
    |> band(0xF3)
    |> bor(up <<< 3)
    |> bor(down <<< 2)
  end

  @doc """
  Applies SafeLink framing to an encoded CRTP binary.
  """
  @spec stamp_frame(binary(), 0 | 1, 0 | 1) :: {:ok, binary()} | {:error, :empty_frame}
  def stamp_frame(<<header, rest::binary>>, up, down) do
    {:ok, <<stamp_header(header, up, down), rest::binary>>}
  end

  def stamp_frame(_, _, _), do: {:error, :empty_frame}

  @doc """
  Advances counters after a successful ACK.

  `downlink_header` is the first byte of ACK data when present, otherwise
  `nil` (empty ACK payload — uplink still flips).
  """
  @spec advance(0 | 1, 0 | 1, byte() | nil) :: {0 | 1, 0 | 1}
  def advance(up, down, downlink_header)
      when up in [0, 1] and down in [0, 1] do
    new_down =
      if is_integer(downlink_header) and band(downlink_header, 0x04) == down <<< 2 do
        1 - down
      else
        down
      end

    {1 - up, new_down}
  end
end
