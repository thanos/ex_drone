defmodule Drone.VehicleTest do
  use ExUnit.Case, async: false

  alias Drone.Safety.Policy
  alias Drone.Vehicle

  describe "connect and lifecycle" do
    test "starts a sim vehicle" do
      name = :"vehicle_start_#{System.unique_integer([:positive])}"
      assert {:ok, ^name} = Drone.connect(:sim, name: name)
      assert is_pid(Vehicle.whereis(name))
    end

    test "connects with safety options" do
      name = :"vehicle_safety_#{System.unique_integer([:positive])}"
      assert {:ok, ^name} = Drone.connect(:sim, name: name, safety: [indoor: true])
      policy = GenServer.call(Vehicle.whereis(name), :get_policy)
      assert policy.indoor == true
    end

    test "connects with a Policy struct as the safety option" do
      name = :"vehicle_policy_struct_#{System.unique_integer([:positive])}"
      policy = Policy.new(max_altitude_cm: 250, indoor: true)
      assert {:ok, ^name} = Drone.connect(:sim, name: name, safety: policy)
      stored = GenServer.call(Vehicle.whereis(name), :get_policy)
      assert stored == policy
      assert stored.max_altitude_cm == 250
    end

    test "rejects duplicate names" do
      name = :"vehicle_dup_#{System.unique_integer([:positive])}"
      assert {:ok, ^name} = Drone.connect(:sim, name: name)
      assert {:error, :name_already_taken} = Drone.connect(:sim, name: name)
    end
  end

  describe "command pipeline" do
    test "takes off" do
      name = :"cmd_takeoff_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)
      assert :ok = Drone.takeoff(name)
    end

    test "moves up" do
      name = :"cmd_up_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)
      :ok = Drone.takeoff(name)
      assert :ok = Drone.move(name, :up, 50)
    end

    test "lands" do
      name = :"cmd_land_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)
      :ok = Drone.takeoff(name)
      assert :ok = Drone.land(name)
    end

    test "rejects movement when not flying" do
      name = :"cmd_nofly_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)
      assert {:error, :safety, :not_flying} = Drone.move(name, :forward, 100)
    end
  end

  describe "safety pipeline" do
    test "rejects movement above max altitude" do
      name = :"safety_alt_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name, safety: [max_altitude_cm: 100])
      Drone.connect_sdk(name)
      :ok = Drone.takeoff(name)
      assert {:error, :safety, :max_altitude} = Drone.move(name, :up, 200)
    end
  end

  describe "emergency" do
    test "emergency bypasses safety" do
      name = :"emerg_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name, safety: [allowlist: [:sdk_mode, :takeoff]])
      Drone.connect_sdk(name)
      :ok = Drone.takeoff(name)
      assert :ok = Drone.emergency(name)
    end
  end

  describe "telemetry" do
    test "returns telemetry data" do
      name = :"tele_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)
      assert {:ok, telemetry} = Drone.telemetry(name)
      assert Map.has_key?(telemetry, :x)
      assert Map.has_key?(telemetry, :battery)
    end
  end

  describe "dry run mode" do
    test "dry run mode returns :ok for takeoff" do
      name = :"dryrun_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name, safety: [dry_run: true])
      Drone.connect_sdk(name)
      assert :ok = Drone.takeoff(name)
    end
  end

  describe "disconnect" do
    test "disconnects and stops process" do
      name = :"disconnect_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      assert is_pid(Vehicle.whereis(name))
      assert :ok = Drone.disconnect(name)
    end

    test "calls adapter disconnect exactly once" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)
      name = :"disconnect_once_#{System.unique_integer([:positive])}"

      {:ok, ^name} =
        Drone.connect(Drone.Adapters.CountingAdapter, name: name, counter: counter)

      pid = Vehicle.whereis(name)
      ref = Process.monitor(pid)

      :ok = Drone.disconnect(name)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

      assert Agent.get(counter, & &1) == 1
      Agent.stop(counter)
    end

    test "emits a disconnect telemetry event on termination" do
      handler = :"disconnect_tele_#{System.unique_integer([:positive])}"
      test_pid = self()

      :telemetry.attach(
        handler,
        [:drone, :disconnect],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:disconnected, metadata})
        end,
        nil
      )

      name = :"disconnect_tele_drone_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      :ok = Drone.disconnect(name)

      assert_receive {:disconnected, %{adapter: :sim, name: ^name}}
      :telemetry.detach(handler)
    end
  end
end
