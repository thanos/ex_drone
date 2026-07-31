defmodule Drone.SwarmTest do
  use ExUnit.Case, async: false

  alias Drone.Mission

  defp uniq(prefix) do
    :"#{prefix}_#{System.unique_integer([:positive])}"
  end

  defp start_pair(opts \\ []) do
    a = uniq("swarm_a")
    b = uniq("swarm_b")
    swarm_name = uniq("swarm")

    {:ok, swarm} =
      Drone.Swarm.start_link(
        name: swarm_name,
        members: [
          {a, Keyword.merge([adapter: :sim, initial_x: 0, initial_y: 0], opts[:a] || [])},
          {b, Keyword.merge([adapter: :sim, initial_x: 0, initial_y: 0], opts[:b] || [])}
        ],
        spacing_cm: Keyword.get(opts, :spacing_cm, 100),
        min_separation_cm: Keyword.get(opts, :min_separation_cm, 80)
      )

    {swarm, a, b}
  end

  describe "start_link/1" do
    test "starts named swarm with member list sugar" do
      a = uniq("m")
      b = uniq("n")

      assert {:ok, swarm} =
               Drone.Swarm.start_link([
                 {a, adapter: :sim, initial_x: -50},
                 {b, adapter: :sim, initial_x: 50}
               ])

      assert is_pid(swarm) or is_atom(swarm)
      assert Drone.Swarm.members(swarm) == [a, b]
      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "whereis finds named swarm" do
      name = uniq("named_swarm")
      a = uniq("wa")
      b = uniq("wb")

      assert {:ok, ^name} =
               Drone.Swarm.start_link(
                 name: name,
                 members: [{a, adapter: :sim}, {b, adapter: :sim}]
               )

      assert is_pid(Drone.Swarm.whereis(name))
      assert :ok = Drone.Swarm.stop(name)
    end
  end

  describe "coordinated ops" do
    test "connect_sdk takeoff land" do
      {swarm, a, b} = start_pair()

      assert {:ok, results} = Drone.Swarm.connect_sdk(swarm)
      assert results[a] == :ok
      assert results[b] == :ok

      assert {:ok, _} = Drone.Swarm.takeoff(swarm)
      assert {:ok, tel} = Drone.Swarm.telemetry(swarm)
      assert tel[a].flying
      assert tel[b].flying

      assert {:ok, _} = Drone.Swarm.land(swarm)
      assert {:ok, tel} = Drone.Swarm.telemetry(swarm)
      refute tel[a].flying
      refute tel[b].flying

      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "fail_fast on takeoff failure" do
      {swarm, a, b} =
        start_pair(
          a: [],
          b: [fail_commands: [:takeoff]]
        )

      assert {:ok, _} = Drone.Swarm.connect_sdk(swarm)
      assert {:error, :partial, results} = Drone.Swarm.takeoff(swarm)
      assert results[a] == :ok
      assert match?({:error, _}, results[b])

      assert {:ok, _} = Drone.Swarm.emergency(swarm)
      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "emergency fans out best-effort" do
      {swarm, _a, _b} = start_pair()
      assert {:ok, _} = Drone.Swarm.connect_sdk(swarm)
      assert {:ok, _} = Drone.Swarm.takeoff(swarm)
      assert {:ok, results} = Drone.Swarm.emergency(swarm)
      assert map_size(results) == 2
      assert :ok = Drone.Swarm.stop(swarm)
    end
  end

  describe "run/2" do
    test "runs front formation from shared origin" do
      {swarm, a, b} = start_pair()
      assert {:ok, _} = Drone.Swarm.connect_sdk(swarm)
      assert {:ok, _} = Drone.Swarm.takeoff(swarm)

      assert {:ok, _} = Drone.Swarm.run(swarm, :front)

      assert {:ok, tel} = Drone.Swarm.telemetry(swarm)
      # After front with spacing 100 around centroid at takeoff positions (0,0)/(0,0)
      # slots approximately (-50, 0) and (50, 0)
      xs = [tel[a].x, tel[b].x] |> Enum.sort()
      assert abs(Enum.at(xs, 0) - -50) <= 5
      assert abs(Enum.at(xs, 1) - 50) <= 5

      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "runs per-drone missions with partial safety failure" do
      a = uniq("good")
      b = uniq("bad")
      swarm = uniq("advisors")

      assert {:ok, ^swarm} =
               Drone.Swarm.start_link(
                 name: swarm,
                 members: [
                   {a, adapter: :sim, initial_x: -50},
                   {b, adapter: :sim, initial_x: 50, safety: [max_altitude_cm: 50]}
                 ]
               )

      assert {:ok, _} = Drone.Swarm.connect_sdk(swarm)
      assert {:ok, _} = Drone.Swarm.takeoff(swarm)

      good =
        Mission.new()
        |> Mission.move(:forward, 40)

      bad =
        Mission.new()
        |> Mission.move(:up, 200)

      assert {:error, :partial, results} = Drone.Swarm.run(swarm, %{a => good, b => bad})
      assert match?({:ok, _}, results[a]) or results[a] == :ok
      assert match?({:error, {:safety, :max_altitude}}, results[b])

      assert {:ok, _} = Drone.Swarm.land(swarm)
      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "runs custom function" do
      {swarm, a, b} = start_pair()
      assert {:ok, _} = Drone.Swarm.connect_sdk(swarm)

      assert {:ok, _} =
               Drone.Swarm.run(swarm, fn members ->
                 assert Map.has_key?(members, a)
                 assert Map.has_key?(members, b)
                 :ok
               end)

      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "rejects separation at plan time" do
      {swarm, _a, _b} = start_pair(spacing_cm: 40, min_separation_cm: 80)
      assert {:ok, _} = Drone.Swarm.connect_sdk(swarm)
      assert {:ok, _} = Drone.Swarm.takeoff(swarm)
      assert {:error, :separation_violation} = Drone.Swarm.run(swarm, :front)
      assert :ok = Drone.Swarm.stop(swarm)
    end
  end
end
