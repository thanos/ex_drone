defmodule Drone.Safety.Geofence do
  @moduledoc """
  Geofence definitions for restricting drone flight area.

  A geofence defines an allowed flight area. Movement commands that would
  take the drone outside the geofence are rejected by the safety pipeline.

  Two geofence shapes are supported:

    - Circle: defined by a center point and radius
    - Polygon: defined by a list of vertices

  Coordinates are in centimeters from the launch point.
  """

  @type t :: %__MODULE__{
          type: :circle | :polygon,
          center: {integer(), integer()} | nil,
          radius_cm: pos_integer() | nil,
          points: [{integer(), integer()}] | nil
        }

  defstruct [:type, :center, :radius_cm, :points]

  @doc """
  Creates a circular geofence centred at the given point with the given radius.
  """
  @spec circle({integer(), integer()}, pos_integer()) :: t()
  def circle(center, radius_cm) do
    %__MODULE__{type: :circle, center: center, radius_cm: radius_cm}
  end

  @doc """
  Creates a polygon geofence from a list of vertices.

  The polygon must have at least 3 vertices. The last vertex is automatically
  connected to the first.
  """
  @spec polygon([{integer(), integer()}]) :: t()
  def polygon([_, _, _ | _] = points) do
    %__MODULE__{type: :polygon, points: points}
  end

  @doc """
  Creates a circular geofence centred at the origin with the given radius.

  This is a convenience for defining a radius around the launch point.
  """
  @spec radius(pos_integer()) :: t()
  def radius(radius_cm) do
    circle({0, 0}, radius_cm)
  end

  @doc """
  Checks whether a point is inside the geofence.

  Returns `true` if the point is inside or on the boundary, `false` otherwise.
  """
  @spec contains?(t() | nil, {integer(), integer()}) :: boolean()
  def contains?(nil, _point), do: true

  def contains?(%__MODULE__{type: :circle, center: {cx, cy}, radius_cm: r}, {px, py}) do
    dx = px - cx
    dy = py - cy
    :math.sqrt(dx * dx + dy * dy) <= r
  end

  def contains?(%__MODULE__{type: :polygon, points: points}, point) do
    point_in_polygon?(point, points)
  end

  defp point_in_polygon?({px, py}, polygon) do
    polygon
    |> Stream.concat(Stream.take(polygon, 1))
    |> Stream.chunk_every(2, 1, :discard)
    |> Enum.reduce(0, fn [{x1, y1}, {x2, y2}], crossings ->
      if edge_crosses?({x1, y1}, {x2, y2}, px, py) do
        crossings + 1
      else
        crossings
      end
    end)
    |> rem(2) == 1
  end

  defp edge_crosses?({x1, y1}, {x2, y2}, px, py) do
    if y1 <= y2 do
      py > y1 and py <= y2 and px < x1 + (py - y1) * (x2 - x1) / (y2 - y1)
    else
      py > y2 and py <= y1 and px < x2 + (py - y2) * (x1 - x2) / (y1 - y2)
    end
  end
end
