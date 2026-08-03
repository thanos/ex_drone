defmodule Drone.Vehicle do
  @moduledoc """
  Supervised GenServer that manages a single drone connection.

  Each `Drone.Vehicle` process represents one drone. It holds the adapter
  state, safety policy, and vehicle state. All commands flow through
  the safety pipeline before reaching the adapter.

  Drivers should not call `Drone.Vehicle` directly. Use the `Drone`
  public API module instead.

  ## Examples

      # Prefer the public API:
      {:ok, drone} = Drone.connect(:sim, name: :alpha)

      # Low-level (tests / supervision trees):
      {:ok, pid} =
        Drone.Vehicle.start_link(
          name: :alpha,
          adapter: :sim,
          safety: [max_altitude_cm: 200]
        )
  """

  use GenServer

  alias Drone.{Adapter, Command, Geometry, Safety, Safety.Policy, Telemetry}

  @default_vehicle_state %{
    x: 0,
    y: 0,
    z: 0,
    yaw: 0,
    battery: 100,
    speed: 0,
    flying: false,
    mode: :idle,
    estimator_ready: true,
    takeoff_height_cm: 30,
    telemetry_at: nil,
    last_command: nil,
    command_history: []
  }

  @typedoc """
  Internal GenServer state for one vehicle process.

  | Field | Type | Meaning |
  | --- | --- | --- |
  | `:name` | `atom()` | Registry name for this vehicle |
  | `:adapter_module` | `module()` | Resolved `Drone.Adapter` implementation |
  | `:adapter_state` | `term()` | Opaque adapter state |
  | `:safety_policy` | `Drone.Safety.Policy.t()` | Active safety policy |
  | `:vehicle_state` | `map()` | Kinematics + mode used by safety / telemetry |

  `:vehicle_state` keys include `:x`, `:y`, `:z`, `:yaw` (cm / degrees),
  `:battery`, `:speed`, `:flying`, `:mode` (`:idle` \\| `:sdk_mode` \\|
  `:flying` \\| `:emergency`), `:estimator_ready`, `:telemetry_at`,
  `:last_command`, and `:command_history`.

  ## Example

      %Drone.Vehicle{
        name: :alpha,
        adapter_module: Drone.Adapters.Sim,
        safety_policy: %Drone.Safety.Policy{max_altitude_cm: 300},
        vehicle_state: %{x: 0, y: 0, z: 50, mode: :flying, flying: true, battery: 98}
      }
  """
  @type state :: %{
          name: atom(),
          adapter_module: module(),
          adapter_state: term(),
          safety_policy: Policy.t(),
          vehicle_state: %{
            x: integer(),
            y: integer(),
            z: integer(),
            yaw: integer(),
            battery: integer(),
            speed: integer(),
            flying: boolean(),
            mode: :idle | :sdk_mode | :flying | :emergency,
            last_command: Command.t() | nil,
            command_history: [Command.t()]
          }
        }

  defstruct [
    :name,
    :adapter_module,
    :adapter_state,
    :safety_policy,
    vehicle_state: @default_vehicle_state
  ]

  @doc """
  Child specification for starting under a supervisor.

  Restart strategy is `:temporary` so a crashed vehicle is not restarted
  automatically by a static supervisor (callers reconnect explicitly).

  ## Parameters

    * `opts` (`keyword()`) — same options as `start_link/1`

  ## Returns

  A child specification map suitable for supervisors.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  @doc """
  Starts a vehicle GenServer registered under `opts[:name]`.

  ## Parameters

    * `opts` (`keyword()`) — required:
      * `:name` (`atom()`) — unique vehicle name in `Drone.Vehicle.Registry`
      * `:adapter` (`atom()` \\| `module()`) — `:sim`, `:tello`, `:crazyflie`, or a module
      Optional:
      * `:safety` (`keyword()`) — passed to `Drone.Safety.Policy.new/1`
      * remaining keys — forwarded to `adapter.connect/1`

  ## Returns

  `GenServer.on_start()` (`{:ok, pid}` \\| `{:error, reason}`).

  ## Examples

      {:ok, _pid} =
        Drone.Vehicle.start_link(
          name: :cf_1,
          adapter: :crazyflie,
          uri: "mock://ready"
        )
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(name))
  end

  @doc """
  Builds a `:via` tuple for the vehicle registry.

  ## Parameters

    * `name` (`atom()`) — vehicle name

  ## Returns

  `{:via, Registry, {Drone.Vehicle.Registry, name}}`.

  ## Examples

      {:via, Registry, {Drone.Vehicle.Registry, :alpha}} =
        Drone.Vehicle.via_tuple(:alpha)
  """
  @spec via_tuple(atom()) :: {:via, Registry, {Drone.Vehicle.Registry, atom()}}
  def via_tuple(name) do
    {:via, Registry, {Drone.Vehicle.Registry, name}}
  end

  @doc """
  Looks up a running vehicle pid by name.

  ## Parameters

    * `name` (`atom()`) — vehicle name registered at `start_link/1`

  ## Returns

    * `pid()` — when registered
    * `nil` — when no process is registered under that name

  ## Examples

      pid = Drone.Vehicle.whereis(:alpha)
      true = is_pid(pid) or is_nil(pid)
  """
  @spec whereis(atom()) :: pid() | nil
  def whereis(name) do
    case Registry.lookup(Drone.Vehicle.Registry, name) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @impl GenServer
  def init(opts) do
    adapter_key = Keyword.fetch!(opts, :adapter)
    name = Keyword.fetch!(opts, :name)
    safety_opts = Keyword.get(opts, :safety, [])
    adapter_opts = Keyword.drop(opts, [:name, :adapter, :safety])

    case Adapter.resolve(adapter_key) do
      {:ok, adapter_module} ->
        init_with_adapter(adapter_key, name, adapter_module, adapter_opts, safety_opts)

      {:error, :unknown_adapter} = err ->
        {:stop, err}
    end
  end

  @impl GenServer
  def terminate(_reason, %__MODULE__{adapter_module: mod, adapter_state: as} = state) do
    try do
      Telemetry.emit_disconnect(adapter_key_from_module(mod), state.name)
      mod.disconnect(as)
    rescue
      _ -> :ok
    end

    :ok
  end

  @impl GenServer
  def handle_call({:command, %Command{} = cmd}, _from, %__MODULE__{} = state) do
    adapter_key = adapter_key_from_module(state.adapter_module)

    case Safety.check(cmd, state.safety_policy, state.vehicle_state) do
      {:error, :safety, reason} ->
        Telemetry.emit_safety_reject(adapter_key, state.name, cmd.type, reason)
        {:reply, {:error, :safety, reason}, state}

      {:ok, cmd} ->
        execute_command(cmd, state, [])

      {:ok, cmd, warnings} ->
        for warning <- warnings do
          Telemetry.emit_safety_warning(adapter_key, state.name, cmd.type, warning)
        end

        execute_command(cmd, state, warnings)
    end
  end

  def handle_call(:emergency, _from, %__MODULE__{} = state) do
    adapter_key = adapter_key_from_module(state.adapter_module)
    Telemetry.emit_emergency(adapter_key, state.name)

    cmd = Command.emergency()
    start_time = System.monotonic_time()

    case state.adapter_module.command(state.adapter_state, cmd) do
      {:ok, _reply, new_adapter_state} ->
        duration = System.monotonic_time() - start_time
        Telemetry.emit_command_stop(adapter_key, state.name, :emergency, :ok, duration)

        new_vehicle_state = %{state.vehicle_state | mode: :emergency, flying: false}
        new_state = %{state | adapter_state: new_adapter_state, vehicle_state: new_vehicle_state}
        {:reply, :ok, new_state}

      {:error, reason, new_adapter_state} ->
        duration = System.monotonic_time() - start_time
        Telemetry.emit_command_error(adapter_key, state.name, :emergency, reason, duration)
        {:reply, {:error, reason}, %{state | adapter_state: new_adapter_state}}
    end
  end

  def handle_call(:telemetry, _from, %__MODULE__{} = state) do
    adapter_key = adapter_key_from_module(state.adapter_module)

    case state.adapter_module.telemetry(state.adapter_state) do
      {:ok, adapter_telemetry, new_adapter_state} ->
        Telemetry.emit_telemetry_update(adapter_key, state.name, adapter_telemetry)
        merged = Map.merge(state.vehicle_state, adapter_telemetry)
        {:reply, {:ok, merged}, %{state | adapter_state: new_adapter_state}}

      {:error, reason, new_adapter_state} ->
        {:reply, {:error, reason}, %{state | adapter_state: new_adapter_state}}
    end
  end

  def handle_call(:disconnect, _from, %__MODULE__{} = state) do
    # Cleanup (adapter disconnect + telemetry) is performed in terminate/2,
    # which always runs on a :normal stop. Doing it here too would close the
    # adapter twice.
    {:stop, :normal, :ok, state}
  end

  def handle_call(:get_state, _from, %__MODULE__{} = state) do
    {:reply, state.vehicle_state, state}
  end

  def handle_call(:get_policy, _from, %__MODULE__{} = state) do
    {:reply, state.safety_policy, state}
  end

  def handle_call(:capabilities, _from, %__MODULE__{} = state) do
    caps = Adapter.capabilities(state.adapter_module, state.adapter_state)
    {:reply, caps, state}
  end

  defp execute_command(%Command{} = cmd, %__MODULE__{} = state, _warnings) do
    adapter_key = adapter_key_from_module(state.adapter_module)

    if state.safety_policy.dry_run do
      new_vehicle_state = update_vehicle_state(state.vehicle_state, cmd, :dry_run)
      start_time = System.monotonic_time()
      Telemetry.emit_command_start(adapter_key, state.name, cmd)
      duration = System.monotonic_time() - start_time
      Telemetry.emit_command_stop(adapter_key, state.name, cmd.type, :dry_run, duration)
      {:reply, {:ok, :dry_run}, %{state | vehicle_state: new_vehicle_state}}
    else
      start_time = System.monotonic_time()
      Telemetry.emit_command_start(adapter_key, state.name, cmd)

      case state.adapter_module.command(state.adapter_state, cmd) do
        {:ok, reply, new_adapter_state} ->
          duration = System.monotonic_time() - start_time
          Telemetry.emit_command_stop(adapter_key, state.name, cmd.type, :ok, duration)

          vehicle_state = update_vehicle_state(state.vehicle_state, cmd, reply)

          {new_vehicle_state, synced_adapter_state} =
            maybe_sync_adapter_pose(vehicle_state, state.adapter_module, new_adapter_state)

          new_state = %{
            state
            | adapter_state: synced_adapter_state,
              vehicle_state: new_vehicle_state
          }

          {:reply, {:ok, reply}, new_state}

        {:error, reason, new_adapter_state} ->
          duration = System.monotonic_time() - start_time
          Telemetry.emit_command_error(adapter_key, state.name, cmd.type, reason, duration)
          {:reply, {:error, reason}, %{state | adapter_state: new_adapter_state}}
      end
    end
  end

  defp init_with_adapter(adapter_key, name, adapter_module, adapter_opts, safety_opts) do
    Telemetry.emit_connect_start(adapter_key, name)

    case adapter_module.connect(adapter_opts) do
      {:ok, adapter_state} ->
        safety_policy = build_policy(safety_opts)

        {initial_vehicle_state, adapter_state} =
          fetch_initial_vehicle_state(adapter_module, adapter_state)

        state = %__MODULE__{
          name: name,
          adapter_module: adapter_module,
          adapter_state: adapter_state,
          safety_policy: safety_policy,
          vehicle_state: initial_vehicle_state
        }

        Telemetry.emit_connect_stop(adapter_key, name, 0)
        {:ok, state}

      {:error, reason} ->
        Telemetry.emit_connect_error(adapter_key, name, reason)
        {:stop, reason}
    end
  end

  # The :safety option accepts either a keyword list (built into a policy via
  # Policy.new/1) or an already-constructed %Policy{} struct.
  defp build_policy(%Policy{} = policy), do: policy
  defp build_policy(opts) when is_list(opts), do: Policy.new(opts)

  defp fetch_initial_vehicle_state(adapter_module, adapter_state) do
    caps = Adapter.capabilities(adapter_module, adapter_state)
    takeoff_height = Map.get(caps, :takeoff_height_cm, 30)

    case adapter_module.telemetry(adapter_state) do
      {:ok, telemetry, new_adapter_state} ->
        vs = %{
          x: Map.get(telemetry, :x, 0),
          y: Map.get(telemetry, :y, 0),
          z: Map.get(telemetry, :z, 0),
          yaw: Map.get(telemetry, :yaw, 0),
          battery: Map.get(telemetry, :battery, 100),
          speed: Map.get(telemetry, :speed, 0),
          flying: Map.get(telemetry, :flying, false),
          mode: Map.get(telemetry, :mode, :idle),
          estimator_ready: Map.get(telemetry, :estimator_ready, true),
          takeoff_height_cm: Map.get(telemetry, :takeoff_height_cm, takeoff_height),
          telemetry_at: Map.get(telemetry, :telemetry_at),
          last_command: nil,
          command_history: []
        }

        {vs, new_adapter_state}

      {:error, _, new_adapter_state} ->
        {Map.put(@default_vehicle_state, :takeoff_height_cm, takeoff_height), new_adapter_state}
    end
  end

  defp update_vehicle_state(vehicle_state, %Command{type: :sdk_mode}, _reply) do
    %{vehicle_state | mode: :sdk_mode}
  end

  defp update_vehicle_state(vehicle_state, %Command{type: :takeoff}, _reply) do
    height = Map.get(vehicle_state, :takeoff_height_cm, 30)
    %{vehicle_state | z: height, flying: true, mode: :flying, speed: 0}
  end

  defp update_vehicle_state(vehicle_state, %Command{type: :land}, _reply) do
    %{vehicle_state | z: 0, flying: false, mode: :sdk_mode, speed: 0}
  end

  defp update_vehicle_state(vehicle_state, %Command{type: :emergency}, _reply) do
    %{vehicle_state | mode: :emergency, flying: false}
  end

  defp update_vehicle_state(vehicle_state, %Command{type: :move, args: args} = cmd, _reply) do
    direction = Keyword.fetch!(args, :direction)
    distance = Keyword.fetch!(args, :distance)
    {dx, dy, dz} = Geometry.move_delta(direction, distance, vehicle_state.yaw)

    vehicle_state
    |> Map.merge(%{
      x: vehicle_state.x + dx,
      y: vehicle_state.y + dy,
      z: max(0, vehicle_state.z + dz)
    })
    |> add_to_history(cmd)
  end

  defp update_vehicle_state(vehicle_state, %Command{type: :rotate, args: args} = cmd, _reply) do
    direction = Keyword.fetch!(args, :direction)
    degrees = Keyword.fetch!(args, :degrees)
    new_yaw = Geometry.rotate_yaw(direction, vehicle_state.yaw, degrees)

    %{vehicle_state | yaw: new_yaw}
    |> add_to_history(cmd)
  end

  defp update_vehicle_state(vehicle_state, %Command{type: :flip, args: args} = cmd, _reply) do
    direction = Keyword.fetch!(args, :direction)
    {dx, dy} = Geometry.flip_delta(direction)

    %{vehicle_state | x: vehicle_state.x + dx, y: vehicle_state.y + dy}
    |> add_to_history(cmd)
  end

  defp update_vehicle_state(vehicle_state, %Command{type: :speed, args: args} = cmd, _reply) do
    speed = Keyword.fetch!(args, :speed)

    %{vehicle_state | speed: speed}
    |> add_to_history(cmd)
  end

  defp update_vehicle_state(vehicle_state, %Command{type: :stop}, _reply) do
    %{vehicle_state | speed: 0}
  end

  defp update_vehicle_state(vehicle_state, %Command{type: :hover} = cmd, _reply) do
    add_to_history(vehicle_state, cmd)
  end

  defp update_vehicle_state(vehicle_state, %Command{type: :query, args: args} = cmd, reply) do
    query_type = Keyword.fetch!(args, :type)

    vehicle_state =
      case query_type do
        :battery -> %{vehicle_state | battery: reply}
        :height -> %{vehicle_state | z: reply}
        :speed -> %{vehicle_state | speed: reply}
        _ -> vehicle_state
      end

    add_to_history(vehicle_state, cmd)
  end

  defp add_to_history(vehicle_state, cmd) do
    %{vehicle_state | last_command: cmd, command_history: [cmd | vehicle_state.command_history]}
  end

  defp maybe_sync_adapter_pose(vehicle_state, adapter_module, adapter_state) do
    caps = Adapter.capabilities(adapter_module, adapter_state)

    if Map.get(caps, :pose_source) == :adapter or Map.get(caps, :requires_estimator, false) do
      case adapter_module.telemetry(adapter_state) do
        {:ok, telem, new_adapter_state} ->
          vs =
            vehicle_state
            |> Map.put(:x, Map.get(telem, :x, vehicle_state.x))
            |> Map.put(:y, Map.get(telem, :y, vehicle_state.y))
            |> Map.put(:z, Map.get(telem, :z, vehicle_state.z))
            |> Map.put(:yaw, Map.get(telem, :yaw, vehicle_state.yaw))
            |> maybe_put(:battery, Map.get(telem, :battery))
            |> maybe_put(:estimator_ready, Map.get(telem, :estimator_ready))
            |> Map.put(:telemetry_at, Map.get(telem, :telemetry_at))
            |> Map.put(
              :takeoff_height_cm,
              Map.get(telem, :takeoff_height_cm, vehicle_state.takeoff_height_cm)
            )

          {vs, new_adapter_state}

        _ ->
          {vehicle_state, adapter_state}
      end
    else
      {vehicle_state, adapter_state}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp adapter_key_from_module(Drone.Adapters.Sim), do: :sim
  defp adapter_key_from_module(Drone.Adapters.Tello), do: :tello
  defp adapter_key_from_module(Drone.Adapters.Crazyflie), do: :crazyflie
  defp adapter_key_from_module(mod), do: mod
end
