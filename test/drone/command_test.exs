defmodule Drone.CommandTest do
  use ExUnit.Case, async: true

  alias Drone.Command

  describe "new/2" do
    test "creates a command with type and args" do
      cmd = Command.new(:move, direction: :forward, distance: 100)
      assert cmd.type == :move
      assert cmd.args == [direction: :forward, distance: 100]
    end

    test "creates a command with no args" do
      cmd = Command.new(:takeoff)
      assert cmd.type == :takeoff
      assert cmd.args == []
    end
  end

  describe "convenience constructors" do
    test "sdk_mode/0" do
      assert %Command{type: :sdk_mode, args: []} = Command.sdk_mode()
    end

    test "takeoff/0" do
      assert %Command{type: :takeoff, args: []} = Command.takeoff()
    end

    test "land/0" do
      assert %Command{type: :land, args: []} = Command.land()
    end

    test "emergency/0" do
      assert %Command{type: :emergency, args: []} = Command.emergency()
    end

    test "move/2" do
      cmd = Command.move(:forward, 100)
      assert cmd.type == :move
      assert cmd.args == [direction: :forward, distance: 100]
    end

    test "rotate/2" do
      cmd = Command.rotate(:cw, 90)
      assert cmd.type == :rotate
      assert cmd.args == [direction: :cw, degrees: 90]
    end

    test "flip/1" do
      cmd = Command.flip(:left)
      assert cmd.type == :flip
      assert cmd.args == [direction: :left]
    end

    test "hover/1" do
      cmd = Command.hover(5)
      assert cmd.type == :hover
      assert cmd.args == [seconds: 5]
    end

    test "speed/1" do
      cmd = Command.speed(50)
      assert cmd.type == :speed
      assert cmd.args == [speed: 50]
    end

    test "stop/0" do
      assert %Command{type: :stop, args: []} = Command.stop()
    end

    test "query/1" do
      cmd = Command.query(:battery)
      assert cmd.type == :query
      assert cmd.args == [type: :battery]
    end
  end

  describe "predicate functions" do
    test "emergency?/1 returns true for emergency commands" do
      assert Command.emergency?(Command.emergency())
      refute Command.emergency?(Command.takeoff())
    end

    test "movement?/1 returns true for movement commands" do
      assert Command.movement?(Command.move(:up, 50))
      assert Command.movement?(Command.rotate(:cw, 90))
      assert Command.movement?(Command.flip(:left))
      refute Command.movement?(Command.takeoff())
      refute Command.movement?(Command.query(:battery))
    end

    test "query?/1 returns true for query commands" do
      assert Command.query?(Command.query(:battery))
      refute Command.query?(Command.takeoff())
    end

    test "requires_flying?/1 returns true for flight-required commands" do
      assert Command.requires_flying?(Command.move(:forward, 100))
      assert Command.requires_flying?(Command.rotate(:cw, 90))
      assert Command.requires_flying?(Command.flip(:left))
      assert Command.requires_flying?(Command.land())
      refute Command.requires_flying?(Command.takeoff())
      refute Command.requires_flying?(Command.query(:battery))
    end

    test "safe_to_retry?/1 returns true for query and sdk_mode" do
      assert Command.safe_to_retry?(Command.query(:battery))
      assert Command.safe_to_retry?(Command.sdk_mode())
      refute Command.safe_to_retry?(Command.takeoff())
      refute Command.safe_to_retry?(Command.move(:up, 50))
    end
  end

  describe "types/0" do
    test "returns all valid command types" do
      types = Command.types()
      assert :sdk_mode in types
      assert :takeoff in types
      assert :land in types
      assert :emergency in types
      assert :move in types
      assert :rotate in types
      assert :flip in types
      assert :hover in types
      assert :speed in types
      assert :stop in types
      assert :query in types
    end
  end
end
