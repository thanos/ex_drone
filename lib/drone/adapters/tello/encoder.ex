defmodule Drone.Adapters.Tello.Encoder do
  @moduledoc """
  Encodes `Drone.Command` structs into Tello UDP command strings.

  The Tello SDK uses plain ASCII text commands sent over UDP. This module
  converts the structured `Drone.Command` representation into the wire format
  expected by DJI Tello / Tello EDU firmware.

  ## Mapping overview

  | Command type | Wire string |
  | --- | --- |
  | `:sdk_mode` | `"command"` |
  | `:takeoff` / `:land` / `:emergency` / `:stop` | same atom name as string |
  | `:hover` | `"stop"` |
  | `:move` | `"forward 50"`, `"up 30"`, … |
  | `:rotate` | `"cw 90"`, `"ccw 45"` |
  | `:flip` | `"flip l"` / `"r"` / `"f"` / `"b"` |
  | `:speed` | `"speed 50"` |
  | `:query` | `"battery?"`, `"height?"`, `"sdk?"`, … |

  ## Examples

      "command" = Drone.Adapters.Tello.Encoder.encode(Drone.Command.sdk_mode())
      "forward 50" =
        Drone.Adapters.Tello.Encoder.encode(Drone.Command.move(:forward, 50))
      "battery?" =
        Drone.Adapters.Tello.Encoder.encode(Drone.Command.query(:battery))
  """

  alias Drone.Command

  @doc """
  Encodes a normalized command into a Tello SDK ASCII string.

  ## Parameters

    * `command` (`Drone.Command.t()`) — command produced by `Drone.Command`
      helpers or the vehicle pipeline

  ## Returns

  `String.t()` ready to send with `Drone.Adapters.Tello.Connection.send_command/3`.

  ## Raises

  `KeyError` when required args (`:direction`, `:distance`, `:degrees`,
  `:speed`, `:type`) are missing from the command.

  ## Examples

      iex> Drone.Adapters.Tello.Encoder.encode(Drone.Command.takeoff())
      "takeoff"

      iex> Drone.Adapters.Tello.Encoder.encode(Drone.Command.move(:left, 40))
      "left 40"

      iex> Drone.Adapters.Tello.Encoder.encode(Drone.Command.rotate(:cw, 90))
      "cw 90"

      iex> Drone.Adapters.Tello.Encoder.encode(Drone.Command.flip(:forward))
      "flip f"

      iex> Drone.Adapters.Tello.Encoder.encode(Drone.Command.speed(60))
      "speed 60"

      iex> Drone.Adapters.Tello.Encoder.encode(Drone.Command.hover(3))
      "stop"

      iex> Drone.Adapters.Tello.Encoder.encode(Drone.Command.query(:sdk_version))
      "sdk?"
  """
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
