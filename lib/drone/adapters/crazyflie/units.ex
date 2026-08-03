defmodule Drone.Adapters.Crazyflie.Units do
  @moduledoc """
  Unit conversions at the Crazyflie adapter boundary.

  Public `Drone` API distances are centimeters and angles are degrees.
  Crazyflie high-level commander packets use meters and radians.

  ## Examples

      0.5 = Drone.Adapters.Crazyflie.Units.cm_to_m(50)
      50 = Drone.Adapters.Crazyflie.Units.m_to_cm(0.5)
  """

  @doc """
  Converts centimeters to meters.

  ## Parameters

    * `cm` (`number()`) — distance in centimeters

  ## Returns

  `float()` meters.

  ## Examples

      1.0 = Drone.Adapters.Crazyflie.Units.cm_to_m(100)
  """
  @spec cm_to_m(number()) :: float()
  def cm_to_m(cm) when is_number(cm), do: cm / 100.0

  @doc """
  Converts meters to centimeters (truncated toward zero).

  ## Parameters

    * `m` (`number()`) — distance in meters

  ## Returns

  `integer()` centimeters.

  ## Examples

      50 = Drone.Adapters.Crazyflie.Units.m_to_cm(0.509)
  """
  @spec m_to_cm(number()) :: integer()
  def m_to_cm(m) when is_number(m), do: trunc(m * 100)

  @doc """
  Converts degrees to radians.

  ## Parameters

    * `deg` (`number()`) — angle in degrees

  ## Returns

  `float()` radians.

  ## Examples

      approx_pi = Drone.Adapters.Crazyflie.Units.deg_to_rad(180)
      true = abs(approx_pi - :math.pi()) < 1.0e-9
  """
  @spec deg_to_rad(number()) :: float()
  def deg_to_rad(deg) when is_number(deg), do: deg * :math.pi() / 180.0

  @doc """
  Converts radians to degrees (truncated toward zero).

  ## Parameters

    * `rad` (`number()`) — angle in radians

  ## Returns

  `integer()` degrees.

  ## Examples

      90 = Drone.Adapters.Crazyflie.Units.rad_to_deg(:math.pi() / 2)
  """
  @spec rad_to_deg(number()) :: integer()
  def rad_to_deg(rad) when is_number(rad), do: trunc(rad * 180.0 / :math.pi())

  @doc """
  Default horizontal move duration in seconds for a distance in cm.

  Uses `distance_cm / speed_cm_s`, floored at `0.5` seconds so short hops
  still get a usable commander duration.

  ## Parameters

    * `distance_cm` (`pos_integer()`) — commanded distance in centimeters
    * `speed_cm_s` (`pos_integer()`) — speed in centimeters per second

  ## Returns

  `float()` duration in seconds (at least `0.5`).

  ## Examples

      2.0 = Drone.Adapters.Crazyflie.Units.move_duration_s(100, 50)
      0.5 = Drone.Adapters.Crazyflie.Units.move_duration_s(20, 100)
  """
  @spec move_duration_s(pos_integer(), pos_integer()) :: float()
  def move_duration_s(distance_cm, speed_cm_s)
      when is_integer(distance_cm) and distance_cm > 0 and is_integer(speed_cm_s) and
             speed_cm_s > 0 do
    max(distance_cm / speed_cm_s, 0.5)
  end
end
