defmodule Drone.Swarm.Supervisor do
  @moduledoc """
  Dynamic supervisor for `Drone.Swarm` coordinator processes.

  Vehicles remain under `Drone.Supervisor`. This supervisor only owns
  swarm coordinators so a swarm crash does not restart vehicle children
  (and vice versa).

  Started automatically by `Drone.Application` as `Drone.Swarm.Supervisor`.

  ## Example

  Prefer `Drone.Swarm.start/1`, which uses this supervisor:

      {:ok, swarm} =
        Drone.Swarm.start(
          name: :demo,
          members: [{:a, adapter: :sim}, {:b, adapter: :sim}]
        )
  """

  use DynamicSupervisor

  @doc """
  Starts the swarm dynamic supervisor (named `Drone.Swarm.Supervisor`).

  ## Parameters

    * `opts` (`keyword()`) — passed to `DynamicSupervisor.start_link/3`
      (normally unused; the process is named)

  ## Returns

  Standard `GenServer.on_start()` result.

  ## Example

      # Called from Drone.Application children:
      # {Drone.Swarm.Supervisor, []}
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initializes the supervisor with a `:one_for_one` strategy.

  ## Parameters

    * `_opts` (`term()`) — start options (ignored)

  ## Returns

  `{:ok, DynamicSupervisor.sup_flags()}`
  """
  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a `Drone.Swarm` child under this supervisor.

  Prefer `Drone.Swarm.start/1`, which wraps this call and returns a
  swarm handle (`name` or `pid`).

  ## Parameters

    * `opts` (`keyword()`) — normalized swarm options including `:members`

  ## Returns

  `DynamicSupervisor.on_start_child()` — typically `{:ok, pid}` or
  `{:error, reason}`.

  ## Example

      {:ok, pid} =
        Drone.Swarm.Supervisor.start_swarm(
          name: :patrol,
          members: [{:a, adapter: :sim}, {:b, adapter: :sim}]
        )
  """
  @spec start_swarm(keyword()) :: DynamicSupervisor.on_start_child()
  def start_swarm(opts) when is_list(opts) do
    DynamicSupervisor.start_child(__MODULE__, {Drone.Swarm, opts})
  end

  @doc """
  Terminates a swarm coordinator by pid.

  Because the swarm traps exits, termination runs `Drone.Swarm` cleanup and
  disconnects members by default (same as `Drone.Swarm.stop/1`). Prefer
  `Drone.Swarm.stop/2` when you need `disconnect: false`.

  ## Parameters

    * `pid` (`pid()`) — swarm process id

  ## Returns

    * `:ok`
    * `{:error, :not_found}`

  ## Example

      :ok = Drone.Swarm.Supervisor.stop_swarm(pid)
  """
  @spec stop_swarm(pid()) :: :ok | {:error, :not_found}
  def stop_swarm(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
