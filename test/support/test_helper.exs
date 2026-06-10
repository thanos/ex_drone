defmodule Drone.TestHelper do
  @moduledoc false

  def setup_registry(_) do
    start_supervised!({Registry, keys: :unique, name: Drone.Vehicle.Registry})
    start_supervised!(Drone.Supervisor)
    :ok
  end

  def connect_sim(context) do
    name = context[:name] || :erlang.make_ref() |> :erlang.ref_to_list() |> List.to_atom()
    {:ok, drone} = Drone.connect(:sim, name: name)

    Drone.connect_sdk(drone)

    {:ok, drone: drone}
  end
end
