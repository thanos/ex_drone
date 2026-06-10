defmodule Drone.AdapterTest do
  use ExUnit.Case, async: true

  alias Drone.Adapter

  describe "resolve/1" do
    test "resolves :sim to Drone.Adapters.Sim" do
      assert {:ok, Drone.Adapters.Sim} = Adapter.resolve(:sim)
    end

    test "resolves :tello to Drone.Adapters.Tello" do
      assert {:ok, Drone.Adapters.Tello} = Adapter.resolve(:tello)
    end

    test "passes through module atoms" do
      assert {:ok, MyCustomAdapter} = Adapter.resolve(MyCustomAdapter)
    end

    test "returns error for unknown adapter" do
      assert {:error, :unknown_adapter} = Adapter.resolve("not an atom")
    end
  end
end
