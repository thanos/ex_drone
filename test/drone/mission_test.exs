defmodule Drone.MissionTest do
  use ExUnit.Case, async: false

  alias Drone.Mission

  describe "building missions" do
    test "creates an empty mission" do
      mission = Mission.new()
      assert Mission.length(mission) == 0
    end

    test "adds commands to mission" do
      mission =
        Mission.new()
        |> Mission.sdk_mode()
        |> Mission.takeoff()
        |> Mission.hover(seconds: 3)
        |> Mission.land()

      assert Mission.length(mission) == 4
    end

    test "adds movement commands" do
      mission =
        Mission.new()
        |> Mission.move(:forward, 100)
        |> Mission.rotate(:cw, 90)

      assert Mission.length(mission) == 2
    end

    test "named mission" do
      mission = Mission.new(name: "test mission")
      assert mission.name == "test mission"
    end
  end

  describe "running missions" do
    test "runs mission against simulator" do
      name = :"mission_run_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)

      mission =
        Mission.new()
        |> Mission.sdk_mode()
        |> Mission.takeoff()
        |> Mission.move(:up, 20)
        |> Mission.land()

      assert {:ok, results} = Mission.run(mission, name)
      assert Enum.count(results) == 4
    end

    test "mission stops on safety rejection" do
      name = :"mission_safe_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name, safety: [max_altitude_cm: 50])

      mission =
        Mission.new()
        |> Mission.sdk_mode()
        |> Mission.takeoff()
        |> Mission.move(:up, 200)

      assert {:error, _cmd, {:safety, :max_altitude}} = Mission.run(mission, name)
    end
  end
end
