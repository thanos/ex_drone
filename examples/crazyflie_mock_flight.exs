# Crazyflie mock flight (no hardware).
#
# Run from the project root:
#
#     mix run examples/crazyflie_mock_flight.exs

{:ok, _} = Application.ensure_all_started(:ex_drone)

{:ok, drone} =
  Drone.connect(:crazyflie,
    name: :cf_demo,
    uri: "mock://ready",
    positioning: :flow,
    default_height_cm: 50
  )

IO.inspect(Drone.capabilities(drone).sdk_mode, label: "sdk_mode capability")

:ok = Drone.connect_sdk(drone)
{:ok, battery} = Drone.query(drone, :battery)
IO.puts("battery=#{battery}%")

:ok = Drone.takeoff(drone)
:ok = Drone.move(drone, :forward, 50)
:ok = Drone.rotate(drone, :cw, 90)
:ok = Drone.land(drone)
:ok = Drone.disconnect(drone)

IO.puts("Crazyflie mock flight complete.")
