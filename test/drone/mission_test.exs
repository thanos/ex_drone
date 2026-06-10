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

    test "adds all movement commands" do
      mission =
        Mission.new()
        |> Mission.move(:forward, 100)
        |> Mission.move(:back, 50)
        |> Mission.move(:left, 30)
        |> Mission.move(:right, 40)
        |> Mission.move(:up, 60)
        |> Mission.move(:down, 20)

      assert Mission.length(mission) == 6
    end

    test "adds rotation commands" do
      mission =
        Mission.new()
        |> Mission.rotate(:cw, 90)
        |> Mission.rotate(:ccw, 45)

      assert Mission.length(mission) == 2
    end

    test "adds flip command" do
      mission =
        Mission.new()
        |> Mission.flip(:left)
        |> Mission.flip(:right)
        |> Mission.flip(:forward)
        |> Mission.flip(:back)

      assert Mission.length(mission) == 4
    end

    test "adds emergency command" do
      mission =
        Mission.new()
        |> Mission.emergency()

      assert Mission.length(mission) == 1
    end

    test "adds speed command" do
      mission =
        Mission.new()
        |> Mission.speed(50)

      assert Mission.length(mission) == 1
    end

    test "adds stop command" do
      mission =
        Mission.new()
        |> Mission.stop()

      assert Mission.length(mission) == 1
    end

    test "adds query commands" do
      mission =
        Mission.new()
        |> Mission.query(:battery)
        |> Mission.query(:height)
        |> Mission.query(:speed)
        |> Mission.query(:time)

      assert Mission.length(mission) == 4
    end

    test "commands are returned in execution order" do
      mission =
        Mission.new()
        |> Mission.sdk_mode()
        |> Mission.takeoff()
        |> Mission.land()

      commands = Mission.commands(mission)
      assert Enum.at(commands, 0).type == :sdk_mode
      assert Enum.at(commands, 1).type == :takeoff
      assert Enum.at(commands, 2).type == :land
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

    test "mission returns error when drone not found" do
      mission =
        Mission.new()
        |> Mission.sdk_mode()

      assert {:error, _cmd, {:no_process, :nonexistent}} = Mission.run(mission, :nonexistent)
    end

    test "mission stops on command error" do
      name = :"mission_err_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)

      mission =
        Mission.new()
        |> Mission.takeoff()

      # Takeoff without SDK mode should fail
      assert {:error, _cmd, _reason} = Mission.run(mission, name)
    end
  end
end
