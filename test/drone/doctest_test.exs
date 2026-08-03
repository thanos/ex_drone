defmodule Drone.DoctestTest do
  use ExUnit.Case, async: true

  doctest Drone.Adapters.Tello.Parser, import: true
  doctest Drone.Adapters.Tello.Encoder, import: true
  doctest Drone.Adapters.Crazyflie.Transport, import: true
end
