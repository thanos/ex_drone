defmodule Drone.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    _ =
      :ets.new(Drone.Swarm.members_table(), [
        :named_table,
        :public,
        :set,
        read_concurrency: true
      ])

    children = [
      {Registry, keys: :unique, name: Drone.Vehicle.Registry},
      {Registry, keys: :unique, name: Drone.Swarm.Registry},
      Drone.Supervisor,
      Drone.Swarm.Supervisor
    ]

    opts = [strategy: :one_for_one, name: Drone.Supervisor.Root]
    Supervisor.start_link(children, opts)
  end
end
