defmodule Drone.SupervisorTest do
  use ExUnit.Case, async: false

  alias Drone.{Supervisor, Vehicle}

  describe "start_vehicle/1" do
    test "starts a vehicle process" do
      name = :"sup_start_#{System.unique_integer([:positive])}"
      opts = [name: name, adapter: :sim]

      assert {:ok, pid} = Supervisor.start_vehicle(opts)
      assert is_pid(pid)
      assert Vehicle.whereis(name) == pid

      # Cleanup
      Supervisor.stop_vehicle(name)
    end

    test "returns error when vehicle already exists" do
      name = :"sup_dup_#{System.unique_integer([:positive])}"
      opts = [name: name, adapter: :sim]

      {:ok, _pid} = Supervisor.start_vehicle(opts)
      assert {:error, {:already_started, _}} = Supervisor.start_vehicle(opts)

      # Cleanup
      Supervisor.stop_vehicle(name)
    end
  end

  describe "stop_vehicle/1" do
    test "stops a running vehicle" do
      name = :"sup_stop_#{System.unique_integer([:positive])}"
      opts = [name: name, adapter: :sim]

      {:ok, pid} = Supervisor.start_vehicle(opts)
      assert :ok = Supervisor.stop_vehicle(name)
      
      # Wait for process to actually terminate
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000
      
      assert Vehicle.whereis(name) == nil
    end

    test "returns error when vehicle not found" do
      assert {:error, :not_found} = Supervisor.stop_vehicle(:nonexistent_drone)
    end
  end
end
