defmodule Drone.Supervisor do
  @moduledoc """
  Dynamic supervisor for drone vehicle processes.

  Each drone is started as a child `Drone.Vehicle` process under this
  supervisor. Processes are looked up by name via the `Drone.Vehicle.Registry`.

  Prefer `Drone.connect/2` / `Drone.disconnect/1` over calling this module
  directly unless you are embedding vehicles in a custom supervision tree.

  ## Examples

      {:ok, _pid} = Drone.Supervisor.start_link([])

      {:ok, _vehicle} =
        Drone.Supervisor.start_vehicle(
          name: :alpha,
          adapter: :sim
        )

      :ok = Drone.Supervisor.stop_vehicle(:alpha)
  """

  use DynamicSupervisor

  @doc """
  Starts the dynamic supervisor (named `Drone.Supervisor`).

  ## Parameters

    * `opts` (`keyword()`) — forwarded to `DynamicSupervisor.start_link/3`
      (usually empty; the process is registered as `__MODULE__`)

  ## Returns

  `GenServer.on_start()`.

  ## Examples

      {:ok, _pid} = Drone.Supervisor.start_link([])
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a `Drone.Vehicle` child under this supervisor.

  ## Parameters

    * `opts` (`keyword()`) — same options as `Drone.Vehicle.start_link/1`
      (`:name`, `:adapter`, `:safety`, plus adapter opts)

  ## Returns

  `Supervisor.on_start_child()` (`{:ok, pid}` \\| `{:error, reason}`).

  ## Examples

      {:ok, _pid} =
        Drone.Supervisor.start_vehicle(
          name: :sim_1,
          adapter: :sim,
          battery: 100
        )
  """
  @spec start_vehicle(keyword()) :: Supervisor.on_start_child()
  def start_vehicle(opts) do
    spec = {Drone.Vehicle, opts}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Terminates the vehicle registered under `name`.

  ## Parameters

    * `name` (`atom()`) — vehicle name from `start_vehicle/1`

  ## Returns

    * `:ok` — child terminated
    * `{:error, :not_found}` — no process registered under that name

  ## Examples

      :ok = Drone.Supervisor.stop_vehicle(:sim_1)
      {:error, :not_found} = Drone.Supervisor.stop_vehicle(:missing)
  """
  @spec stop_vehicle(atom()) :: :ok | {:error, :not_found}
  def stop_vehicle(name) do
    case Drone.Vehicle.whereis(name) do
      nil -> {:error, :not_found}
      pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end
end
