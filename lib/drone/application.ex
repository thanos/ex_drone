defmodule Drone.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Drone.Vehicle.Registry},
      Drone.Supervisor
    ]

    opts = [strategy: :one_for_one, name: Drone.Supervisor.Root]
    Supervisor.start_link(children, opts)
  end
end
