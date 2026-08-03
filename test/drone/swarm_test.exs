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
      Drone.Swarm.start(
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

  describe "start/1" do
    test "starts named swarm with member list sugar" do
      a = uniq("m")
      b = uniq("n")

      assert {:ok, swarm} =
               Drone.Swarm.start([
                 {a, adapter: :sim, initial_x: -50},
                 {b, adapter: :sim, initial_x: 50}
               ])

      assert is_pid(swarm)
      assert {:ok, [^a, ^b]} = Drone.Swarm.members(swarm)
      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "whereis finds named swarm" do
      name = uniq("named_swarm")
      a = uniq("wa")
      b = uniq("wb")

      assert {:ok, ^name} =
               Drone.Swarm.start(
                 name: name,
                 members: [{a, adapter: :sim}, {b, adapter: :sim}]
               )

      assert is_pid(Drone.Swarm.whereis(name))
      assert :ok = Drone.Swarm.stop(name)
    end

    test "rolls back connected members when a later member fails to connect" do
      a = uniq("rb_a")
      b = uniq("rb_b")

      assert {:ok, ^b} = Drone.connect(:sim, name: b)

      assert {:error, {^b, :name_already_taken}} =
               Drone.Swarm.start([
                 {a, adapter: :sim},
                 {b, adapter: :sim}
               ])

      assert Drone.Vehicle.whereis(a) == nil
      assert is_pid(Drone.Vehicle.whereis(b))
      assert :ok = Drone.disconnect(b)
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

    test "fail_fast stops issuing commands after the first failure" do
      a = uniq("ff_a")
      b = uniq("ff_b")
      c = uniq("ff_c")

      {:ok, swarm} =
        Drone.Swarm.start([
          {a, adapter: :sim},
          {b, adapter: :sim, fail_commands: [:takeoff]},
          {c, adapter: :sim}
        ])

      assert {:ok, _} = Drone.Swarm.connect_sdk(swarm)
      assert {:error, :partial, results} = Drone.Swarm.takeoff(swarm)

      assert results[a] == :ok
      assert match?({:error, _}, results[b])
      refute Map.has_key?(results, c)

      assert {:ok, tel} = Drone.Swarm.telemetry(swarm)
      refute tel[c].flying

      assert {:ok, _} = Drone.Swarm.emergency(swarm)
      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "emergency reaches every member even when one fails" do
      a = uniq("em_a")
      b = uniq("em_b")
      c = uniq("em_c")

      {:ok, swarm} =
        Drone.Swarm.start([
          {a, adapter: :sim},
          {b, adapter: :sim, fail_commands: [:emergency]},
          {c, adapter: :sim}
        ])

      assert {:ok, _} = Drone.Swarm.connect_sdk(swarm)
      assert {:ok, _} = Drone.Swarm.takeoff(swarm)

      assert {:ok, results} = Drone.Swarm.emergency(swarm)
      assert results[a] == :ok
      assert match?({:error, _}, results[b])
      assert results[c] == :ok

      assert {:ok, tel} = Drone.Swarm.telemetry(swarm)
      refute tel[a].flying
      refute tel[c].flying

      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "emergency preempts an in-flight run" do
      {swarm, a, _b} = start_pair()
      pid = Drone.Swarm.whereis(swarm)
      assert {:ok, _} = Drone.Swarm.connect_sdk(swarm)
      assert {:ok, _} = Drone.Swarm.takeoff(swarm)

      spawn(fn ->
        Drone.Swarm.run(swarm, fn _ ->
          Process.sleep(2_000)
          :ok
        end)
      end)

      Process.sleep(100)

      t0 = System.monotonic_time(:millisecond)
      assert {:ok, _} = Drone.Swarm.emergency(swarm)
      elapsed = System.monotonic_time(:millisecond) - t0

      assert elapsed < 500, "emergency blocked for #{elapsed}ms behind run/2"

      assert {:ok, tel} = Drone.Swarm.telemetry(swarm)
      refute tel[a].flying

      # Avoid waiting for the sleeping run/2 still holding the mailbox.
      Process.exit(pid, :kill)
      Process.sleep(50)
    end
  end

  describe "run/2" do
    test "runs front formation from shared origin" do
      {swarm, a, b} = start_pair()
      assert {:ok, _} = Drone.Swarm.connect_sdk(swarm)
      assert {:ok, _} = Drone.Swarm.takeoff(swarm)

      assert {:ok, _} = Drone.Swarm.run(swarm, :front)

      assert {:ok, tel} = Drone.Swarm.telemetry(swarm)
      xs = [tel[a].x, tel[b].x] |> Enum.sort()
      assert abs(Enum.at(xs, 0) - -50) <= 5
      assert abs(Enum.at(xs, 1) - 50) <= 5

      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "runs formation with options via run/3" do
      {swarm, a, b} = start_pair()
      assert {:ok, _} = Drone.Swarm.connect_sdk(swarm)
      assert {:ok, _} = Drone.Swarm.takeoff(swarm)

      assert {:ok, _} = Drone.Swarm.run(swarm, :echelon, side: :left, heading_deg: 0)

      assert {:ok, tel} = Drone.Swarm.telemetry(swarm)
      # left echelon: trailing member steps to -X relative to first
      assert tel[b].x < tel[a].x

      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "runs per-drone missions with partial safety failure" do
      a = uniq("good")
      b = uniq("bad")
      swarm = uniq("advisors")

      assert {:ok, ^swarm} =
               Drone.Swarm.start(
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
      assert match?({:ok, _}, results[a])
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

    test "rejects invalid custom function results" do
      {swarm, _a, _b} = start_pair()

      assert {:error, {:invalid_run_result, :error}} =
               Drone.Swarm.run(swarm, fn _ -> :error end)

      assert {:error, {:safety, :max_altitude}} =
               Drone.Swarm.run(swarm, fn _ -> {:error, :safety, :max_altitude} end)

      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "rejects a bare mission struct without crashing the swarm" do
      {swarm, _a, _b} = start_pair()
      pid = Drone.Swarm.whereis(swarm)
      mission = Mission.new() |> Mission.move(:forward, 40)

      assert {:error, :unsupported_run_target} = Drone.Swarm.run(swarm, mission)
      assert Process.alive?(pid)
      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "rejects unknown members before flying anyone" do
      {swarm, a, _b} = start_pair()
      assert {:ok, _} = Drone.Swarm.connect_sdk(swarm)
      assert {:ok, _} = Drone.Swarm.takeoff(swarm)
      assert {:ok, before} = Drone.telemetry(a)

      m = Mission.new() |> Mission.move(:forward, 40)

      assert {:error, {:unknown_members, [:ghost]}} =
               Drone.Swarm.run(swarm, %{a => m, ghost: m})

      assert {:ok, now} = Drone.telemetry(a)
      assert {now.x, now.y} == {before.x, before.y}

      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "rejects separation at plan time" do
      {swarm, _a, _b} = start_pair(spacing_cm: 40, min_separation_cm: 80)
      assert {:ok, _} = Drone.Swarm.connect_sdk(swarm)
      assert {:ok, _} = Drone.Swarm.takeoff(swarm)
      assert {:error, :separation_violation} = Drone.Swarm.run(swarm, :front)
      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "returns not_found for unknown swarm" do
      assert {:error, :not_found} = Drone.Swarm.members(:no_such_swarm)
      assert {:error, :not_found} = Drone.Swarm.run(:no_such_swarm, :front)
      assert {:error, :not_found} = Drone.Swarm.emergency(:no_such_swarm)
    end

    test "starts from bare atom members and rejects duplicate names" do
      a = uniq("bare_a")
      b = uniq("bare_b")
      name = uniq("named_swarm")

      assert {:ok, swarm} = Drone.Swarm.start([a, b])
      assert {:ok, [^a, ^b]} = Drone.Swarm.members(swarm)
      assert :ok = Drone.Swarm.stop(swarm)

      assert {:ok, ^name} =
               Drone.Swarm.start(
                 name: name,
                 members: [{uniq("x"), adapter: :sim}, {uniq("y"), adapter: :sim}]
               )

      assert {:error, :name_already_taken} =
               Drone.Swarm.start(
                 name: name,
                 members: [{uniq("u"), adapter: :sim}, {uniq("v"), adapter: :sim}]
               )

      assert :ok = Drone.Swarm.stop(name)
    end

    test "custom fun may return {:ok, value}" do
      {swarm, _a, _b} = start_pair()

      assert {:ok, :done} = Drone.Swarm.run(swarm, fn _ -> {:ok, :done} end)
      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "rejects unsupported run targets" do
      {swarm, a, _b} = start_pair()

      assert {:error, :unsupported_run_target} = Drone.Swarm.run(swarm, "front")
      assert {:error, :unsupported_run_target} = Drone.Swarm.run(swarm, %{a => :not_a_mission})
      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "drops crashed members from membership" do
      {swarm, a, b} = start_pair()
      pid = Drone.Vehicle.whereis(a)
      Process.exit(pid, :kill)
      Process.sleep(50)

      assert {:ok, members} = Drone.Swarm.members(swarm)
      assert members == [b]
      refute a in members

      assert {:ok, _} = Drone.Swarm.emergency(swarm)
      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "ignores unknown handle_info messages" do
      {swarm, _a, _b} = start_pair()
      pid = Drone.Swarm.whereis(swarm)
      send(pid, :unexpected_noise)
      Process.sleep(20)
      assert Process.alive?(pid)
      assert :ok = Drone.Swarm.stop(swarm)
    end

    test "formation run fails when member telemetry errors" do
      a = uniq("ft_a")
      b = uniq("ft_b")

      assert {:ok, swarm} =
               Drone.Swarm.start(
                 members: [
                   {a, adapter: Drone.Adapters.FailingTelemAdapter, fail: :telemetry_error},
                   {b, adapter: :sim, initial_x: 100}
                 ]
               )

      assert {:ok, _} = Drone.Swarm.connect_sdk(swarm)
      assert {:error, {^a, :link_lost}} = Drone.Swarm.telemetry(swarm)
      assert {:error, {^a, :link_lost}} = Drone.Swarm.run(swarm, :front)
      assert :ok = Drone.Swarm.stop(swarm)
    end
  end

  describe "lifecycle" do
    test "members are reclaimed when the coordinator is shut down" do
      {swarm, a, b} = start_pair()
      pid = Drone.Swarm.whereis(swarm)

      assert :ok = Drone.Swarm.Supervisor.stop_swarm(pid)
      Process.sleep(100)

      refute Process.alive?(pid)
      assert Drone.Vehicle.whereis(a) == nil
      assert Drone.Vehicle.whereis(b) == nil
    end

    test "members are reclaimed when the coordinator is killed" do
      {swarm, a, b} = start_pair()
      pid = Drone.Swarm.whereis(swarm)

      Process.exit(pid, :kill)
      Process.sleep(100)

      refute Process.alive?(pid)
      assert Drone.Vehicle.whereis(a) == nil
      assert Drone.Vehicle.whereis(b) == nil
    end

    test "stop with disconnect: false leaves members alive" do
      {swarm, a, b} = start_pair()

      assert :ok = Drone.Swarm.stop(swarm, disconnect: false)
      Process.sleep(50)

      assert is_pid(Drone.Vehicle.whereis(a))
      assert is_pid(Drone.Vehicle.whereis(b))

      assert :ok = Drone.disconnect(a)
      assert :ok = Drone.disconnect(b)
    end

    test "emits swarm telemetry events" do
      ref = make_ref()
      parent = self()
      handler_id = "swarm-test-#{inspect(ref)}"

      :telemetry.attach_many(
        handler_id,
        [
          [:drone, :swarm, :start],
          [:drone, :swarm, :command, :stop],
          [:drone, :swarm, :stop]
        ],
        fn event, measurements, meta, _ ->
          send(parent, {ref, event, measurements, meta})
        end,
        nil
      )

      try do
        {swarm, a, b} = start_pair()

        assert_receive {^ref, [:drone, :swarm, :start], _, %{members: members}}
        assert Enum.sort(members) == Enum.sort([a, b])

        assert {:ok, _} = Drone.Swarm.connect_sdk(swarm)

        assert_receive {^ref, [:drone, :swarm, :command, :stop],
                        %{duration: d, command: :connect_sdk}, _meta}

        assert d >= 0

        assert :ok = Drone.Swarm.stop(swarm)

        assert_receive {^ref, [:drone, :swarm, :stop], _, %{reason: :normal}}
      after
        :telemetry.detach(handler_id)
      end
    end
  end
end
