defmodule Drone.ErrorTest do
  use ExUnit.Case, async: true

  alias Drone.Error

  describe "safety/1" do
    test "creates a safety error tuple" do
      assert Error.safety(:max_altitude) == {:error, :safety, :max_altitude}
    end
  end

  describe "adapter/1" do
    test "creates an adapter error tuple" do
      assert Error.adapter(:timeout) == {:error, :timeout}
    end
  end

  describe "invalid_command/1" do
    test "creates an invalid command error tuple" do
      assert Error.invalid_command(:invalid_distance) ==
               {:error, :invalid_command, :invalid_distance}
    end
  end

  describe "predicates" do
    test "safety_error?/1 identifies safety errors" do
      assert Error.safety_error?({:error, :safety, :max_altitude})
      refute Error.safety_error?({:error, :timeout})
      refute Error.safety_error?({:error, :invalid_command, :bad})
    end

    test "adapter_error?/1 identifies adapter errors" do
      assert Error.adapter_error?({:error, :timeout})
      refute Error.adapter_error?({:error, :safety, :max_altitude})
    end

    test "invalid_command_error?/1 identifies invalid command errors" do
      assert Error.invalid_command_error?({:error, :invalid_command, :bad})
      refute Error.invalid_command_error?({:error, :timeout})
    end
  end

  describe "reason/1" do
    test "extracts reason from safety error" do
      assert Error.reason({:error, :safety, :max_altitude}) == :max_altitude
    end

    test "extracts reason from adapter error" do
      assert Error.reason({:error, :timeout}) == :timeout
    end

    test "extracts reason from invalid command error" do
      assert Error.reason({:error, :invalid_command, :bad}) == :bad
    end
  end
end
