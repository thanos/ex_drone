defmodule Drone.AdapterMockTest do
  use ExUnit.Case, async: false

  import Mox
  import Drone.Test.MoxHelpers

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    stub_healthy_adapter!()
    :ok
  end

  test "Drone API works against AdapterMock" do
    name = :"mox_drone_#{System.unique_integer([:positive])}"

    assert {:ok, ^name} = Drone.connect(Drone.AdapterMock, name: name)
    assert :ok = Drone.connect_sdk(name)
    assert {:ok, 100} = Drone.query(name, :battery)
    assert :ok = Drone.takeoff(name)
    assert :ok = Drone.move(name, :forward, 40)
    assert :ok = Drone.rotate(name, :cw, 90)
    assert :ok = Drone.hover(name)
    assert :ok = Drone.stop(name)
    assert :ok = Drone.land(name)
    assert :ok = Drone.disconnect(name)
  end

  test "mission runs against AdapterMock" do
    name = :"mox_mission_#{System.unique_integer([:positive])}"
    assert {:ok, ^name} = Drone.connect(Drone.AdapterMock, name: name)

    mission =
      Drone.Mission.new()
      |> Drone.Mission.sdk_mode()
      |> Drone.Mission.takeoff()
      |> Drone.Mission.move(:up, 40)
      |> Drone.Mission.land()

    assert {:ok, [_ | _] = results} = Drone.Mission.run(mission, name)
    assert match?([_, _, _, _], results)
    assert :ok = Drone.disconnect(name)
  end

  test "adapter command errors surface through Vehicle" do
    name = :"mox_err_#{System.unique_integer([:positive])}"

    expect(Drone.AdapterMock, :command, 2, fn
      s, %{type: :sdk_mode} -> {:ok, :ok, %{s | mode: :sdk_mode}}
      s, %{type: :takeoff} -> {:error, :simulated_failure, s}
    end)

    assert {:ok, ^name} = Drone.connect(Drone.AdapterMock, name: name)
    assert :ok = Drone.connect_sdk(name)
    assert {:error, :simulated_failure} = Drone.takeoff(name)
    assert :ok = Drone.disconnect(name)
  end

  test "emergency uses adapter mock bypass path" do
    name = :"mox_em_#{System.unique_integer([:positive])}"
    assert {:ok, ^name} = Drone.connect(Drone.AdapterMock, name: name)
    assert :ok = Drone.connect_sdk(name)
    assert :ok = Drone.takeoff(name)
    assert :ok = Drone.emergency(name)
    assert :ok = Drone.disconnect(name)
  end
end
