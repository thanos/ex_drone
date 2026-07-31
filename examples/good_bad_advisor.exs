# Good Advisor / Bad Advisor — swarm demo
#
# Run: mix run examples/good_bad_advisor.exs

Application.ensure_all_started(:ex_drone)

good = :good_advisor
bad = :bad_advisor

IO.puts("Starting swarm with :good and :bad advisors (simulator)...")

{:ok, swarm} =
  Drone.Swarm.start(
    name: :advisors,
    members: [
      {good, adapter: :sim, initial_x: 0, initial_y: 0},
      {bad, adapter: :sim, initial_x: 0, initial_y: 0, safety: [max_altitude_cm: 50]}
    ],
    spacing_cm: 100,
    min_separation_cm: 80
  )

IO.inspect(Drone.Swarm.members(swarm), label: "members")

{:ok, _} = Drone.Swarm.connect_sdk(swarm)
{:ok, _} = Drone.Swarm.takeoff(swarm)

IO.puts("\n1) Coordinated front formation (both should succeed)...")
{:ok, formation_results} = Drone.Swarm.run(swarm, :front)
IO.inspect(formation_results, label: "formation")

IO.puts("\n2) Per-drone missions — :bad attempts an unsafe climb...")

good_mission =
  Drone.Mission.new(name: "good")
  |> Drone.Mission.move(:forward, 40)
  |> Drone.Mission.hover(seconds: 1)

bad_mission =
  Drone.Mission.new(name: "bad")
  |> Drone.Mission.move(:up, 200)

case Drone.Swarm.run(swarm, %{good => good_mission, bad => bad_mission}) do
  {:error, :partial, results} ->
    IO.puts("Partial swarm result (expected):")
    IO.inspect(results, label: "results")

  other ->
    IO.inspect(other, label: "unexpected")
end

{:ok, telemetry} = Drone.Swarm.telemetry(swarm)
IO.puts("\nTelemetry after partial failure:")
IO.inspect(telemetry[good], label: "good")
IO.inspect(telemetry[bad], label: "bad")

IO.puts("\nLanding both advisors...")
{:ok, _} = Drone.Swarm.land(swarm)
:ok = Drone.Swarm.stop(swarm)

IO.puts("Done.")
