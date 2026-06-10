defmodule Drone.Supervisor do
  @moduledoc """
  Dynamic supervisor for drone vehicle processes.

  Each drone is started as a child `Drone.Vehicle` process under this
  supervisor. Processes are looked up by name via the `Drone.Vehicle.Registry`.
  """

  use DynamicSupervisor

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec start_vehicle(keyword()) :: Supervisor.on_start_child()
  def start_vehicle(opts) do
    spec = {Drone.Vehicle, opts}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @spec stop_vehicle(atom()) :: :ok | {:error, :not_found}
  def stop_vehicle(name) do
    case Drone.Vehicle.whereis(name) do
      nil -> {:error, :not_found}
      pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end
end
