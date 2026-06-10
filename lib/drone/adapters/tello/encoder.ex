defmodule Drone.Adapters.Tello.Encoder do
  @moduledoc """
  Encodes Drone.Command structs into Tello UDP command strings.

  The Tello SDK uses plain ASCII text commands sent over UDP. This module
  converts the structured `Drone.Command` representation into the wire format.
  """

  alias Drone.Command

  @spec encode(Command.t()) :: String.t()
  def encode(%Command{type: :sdk_mode}), do: "command"
  def encode(%Command{type: :takeoff}), do: "takeoff"
  def encode(%Command{type: :land}), do: "land"
  def encode(%Command{type: :emergency}), do: "emergency"
  def encode(%Command{type: :stop}), do: "stop"

  def encode(%Command{type: :move, args: args}) do
    direction = Keyword.fetch!(args, :direction)
    distance = Keyword.fetch!(args, :distance)
    "#{direction} #{distance}"
  end

  def encode(%Command{type: :rotate, args: args}) do
    direction = Keyword.fetch!(args, :direction)
    degrees = Keyword.fetch!(args, :degrees)
    "#{direction} #{degrees}"
  end

  def encode(%Command{type: :flip, args: args}) do
    direction = Keyword.fetch!(args, :direction)
    short = flip_direction(direction)
    "flip #{short}"
  end

  def encode(%Command{type: :speed, args: args}) do
    speed = Keyword.fetch!(args, :speed)
    "speed #{speed}"
  end

  def encode(%Command{type: :hover}), do: "stop"

  def encode(%Command{type: :query, args: args}) do
    type = Keyword.fetch!(args, :type)
    query_string(type)
  end

  defp flip_direction(:left), do: "l"
  defp flip_direction(:right), do: "r"
  defp flip_direction(:forward), do: "f"
  defp flip_direction(:back), do: "b"

  defp query_string(:battery), do: "battery?"
  defp query_string(:height), do: "height?"
  defp query_string(:speed), do: "speed?"
  defp query_string(:time), do: "time?"
  defp query_string(:wifi), do: "wifi?"
  defp query_string(:sdk_version), do: "sdk?"
  defp query_string(:serial_number), do: "sn?"
end
