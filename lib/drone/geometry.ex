defmodule Drone.Geometry do
  @moduledoc false
  # Shared position math for translating directional movement commands into
  # x/y/z deltas, accounting for the drone's current yaw. Used by both the
  # simulator adapter and the vehicle state tracker so their position models
  # stay in sync.

  @doc """
  Returns the `{dx, dy, dz}` delta for a movement command.

  `direction` is one of `:up`, `:down`, `:forward`, `:back`, `:left`, `:right`.
  `distance` is in centimeters and `yaw` is the current heading in degrees.
  """
  @spec move_delta(atom(), integer(), integer()) :: {integer(), integer(), integer()}
  def move_delta(:up, distance, _yaw), do: {0, 0, distance}
  def move_delta(:down, distance, _yaw), do: {0, 0, -distance}
  def move_delta(:forward, distance, yaw), do: forward_delta(distance, yaw)
  def move_delta(:back, distance, yaw), do: forward_delta(-distance, yaw)
  def move_delta(:left, distance, yaw), do: right_delta(-distance, yaw)
  def move_delta(:right, distance, yaw), do: right_delta(distance, yaw)

  @doc """
  Returns the `{dx, dy}` horizontal delta for a flip in the given direction.
  """
  @spec flip_delta(atom()) :: {integer(), integer()}
  def flip_delta(:left), do: {-20, 0}
  def flip_delta(:right), do: {20, 0}
  def flip_delta(:forward), do: {0, 20}
  def flip_delta(:back), do: {0, -20}

  @doc """
  Returns the new yaw after rotating `degrees` in the given direction.
  """
  @spec rotate_yaw(:cw | :ccw, integer(), integer()) :: integer()
  def rotate_yaw(:cw, yaw, degrees), do: rem(yaw + degrees, 360)
  def rotate_yaw(:ccw, yaw, degrees), do: rem(yaw - degrees + 360, 360)

  defp forward_delta(distance, yaw) do
    radians = yaw * :math.pi() / 180
    {trunc(distance * :math.sin(radians)), trunc(distance * :math.cos(radians)), 0}
  end

  defp right_delta(distance, yaw) do
    radians = yaw * :math.pi() / 180
    {trunc(distance * :math.cos(radians)), trunc(-distance * :math.sin(radians)), 0}
  end
end
