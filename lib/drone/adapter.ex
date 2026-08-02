defmodule Drone.Adapter do
  @moduledoc """
  Behaviour definition for drone adapters.

  Every drone adapter must implement this behaviour. The adapter is responsible
  for all communication with the physical (or simulated) drone. The
  `Drone.Vehicle` GenServer calls adapter callbacks, passing opaque adapter
  state.

  Built-in adapters: `Drone.Adapters.Sim`, `Drone.Adapters.Tello`,
  `Drone.Adapters.Crazyflie`.

  ## Implementing an Adapter

      defmodule Drone.Adapters.FakeDrone do
        @behaviour Drone.Adapter

        defstruct [:connected, battery: 100, z: 0, flying: false, mode: :idle]

        @impl Drone.Adapter
        def connect(opts) do
          battery = Keyword.get(opts, :battery, 100)
          {:ok, %__MODULE__{connected: true, battery: battery}}
        end

        @impl Drone.Adapter
        def command(%__MODULE__{} = state, %Drone.Command{type: :sdk_mode}) do
          {:ok, :ok, %{state | mode: :sdk_mode}}
        end

        def command(%__MODULE__{mode: :sdk_mode} = state, %Drone.Command{type: :takeoff}) do
          {:ok, :ok, %{state | flying: true, z: 30, mode: :flying}}
        end

        def command(%__MODULE__{} = state, %Drone.Command{type: :land}) do
          {:ok, :ok, %{state | flying: false, z: 0, mode: :sdk_mode}}
        end

        def command(%__MODULE__{} = state, %Drone.Command{type: :emergency}) do
          {:ok, :ok, %{state | flying: false, mode: :emergency}}
        end

        def command(state, %Drone.Command{type: :query, args: args}) do
          value =
            case Keyword.fetch!(args, :type) do
              :battery -> state.battery
              :height -> state.z
              other -> {:unsupported_query, other}
            end

          {:ok, value, state}
        end

        def command(state, _cmd), do: {:error, :unsupported_command, state}

        @impl Drone.Adapter
        def telemetry(%__MODULE__{} = state) do
          {:ok,
           %{
             x: 0,
             y: 0,
             z: state.z,
             yaw: 0,
             battery: state.battery,
             flying: state.flying,
             mode: state.mode
           }, state}
        end

        @impl Drone.Adapter
        def disconnect(%__MODULE__{}), do: :ok
      end

      {:ok, drone} = Drone.connect(Drone.Adapters.FakeDrone, name: :fake)

  See `docs/adapter_authoring.md` for a complete guide.
  """

  alias Drone.Adapter.Capabilities

  @typedoc """
  Opaque adapter state held by `Drone.Vehicle`.

  Each adapter defines its own representation. It may be a map, struct, or
  any term. The Vehicle never inspects it except to pass it back into
  callbacks.

  ## Examples

      %{socket: port(), drone_ip: {192, 168, 10, 1}}
      %Drone.Adapters.Sim.State{x: 0, y: 0, z: 30, battery: 98}
  """
  @type state :: term()

  @doc """
  Opens a connection and returns initial adapter state.

  Called once when `Drone.connect/2` starts the vehicle.

  ## Parameters

    * `opts` (`keyword()`) — adapter-specific options from `Drone.connect/2`
      after `:name`, `:adapter`, and `:safety` are stripped. Examples:
      * Sim: `:battery`, `:initial_x`, `:initial_y`, `:failure_rate`, ...
      * Tello: `:drone_ip`, `:command_port`, `:timeout`, ...

  ## Returns

    * `{:ok, state()}` — connected; state is stored on the Vehicle
    * `{:error, term()}` — connection failed (vehicle exits)

  ## Example implementation

      @impl Drone.Adapter
      def connect(opts) do
        ip = Keyword.get(opts, :drone_ip, {192, 168, 10, 1})
        {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
        {:ok, %{socket: socket, ip: ip}}
      end
  """
  @callback connect(opts :: keyword()) ::
              {:ok, state()}
              | {:error, term()}

  @doc """
  Executes a single command against the drone.

  The Vehicle calls this only after safety approval (except emergency,
  which bypasses safety but still uses this callback).

  ## Parameters

    * `state` (`t:state/0`) — current adapter state
    * `command` (`Drone.Command.t()`) — normalized command struct

  ## Returns

    * `{:ok, reply, new_state}` — `reply` is typically `:ok` or a query value
    * `{:error, reason, new_state}` — command failed; state may still update

  ## Example implementation

      @impl Drone.Adapter
      def command(state, %Drone.Command{type: :takeoff}) do
        :ok = send_udp(state, "takeoff")
        {:ok, :ok, %{state | flying: true}}
      end

      def command(state, %Drone.Command{type: :query, args: [type: :battery]}) do
        {:ok, percent} = send_udp_query(state, "battery?")
        {:ok, percent, state}
      end
  """
  @callback command(state :: state(), command :: Drone.Command.t()) ::
              {:ok, reply :: term(), new_state :: state()}
              | {:error, reason :: term(), new_state :: state()}

  @doc """
  Returns a telemetry snapshot from the adapter.

  Used to seed and refresh vehicle state (position, battery, mode).

  ## Parameters

    * `state` (`t:state/0`) — current adapter state

  ## Returns

    * `{:ok, map(), state()}` — map should include keys like `:x`, `:y`, `:z`,
      `:yaw`, `:battery`, `:flying`, `:mode` when available
    * `{:error, term(), state()}` — snapshot failed

  ## Example implementation

      @impl Drone.Adapter
      def telemetry(state) do
        {:ok,
         %{
           x: state.x,
           y: state.y,
           z: state.z,
           yaw: state.yaw,
           battery: trunc(state.battery),
           flying: state.flying,
           mode: state.mode
         }, state}
      end
  """
  @callback telemetry(state :: state()) ::
              {:ok, map(), state()}
              | {:error, term(), state()}

  @doc """
  Closes the adapter connection and releases resources.

  Optional callback — if omitted, disconnect is a no-op at the behaviour
  level (Vehicle still stops).

  ## Parameters

    * `state` (`t:state/0`) — final adapter state

  ## Returns

  Always `:ok`.

  ## Example implementation

      @impl Drone.Adapter
      def disconnect(%{socket: socket}) do
        :gen_udp.close(socket)
        :ok
      end
  """
  @callback disconnect(state :: state()) :: :ok

  @doc """
  Returns capability metadata for the connected adapter.

  Optional. When omitted, callers treat the adapter as Tello-shaped
  (`Drone.Adapter.Capabilities.tello_like/0`).

  ## Parameters

    * `state` (`t:state/0`) — current adapter state

  ## Returns

  `Drone.Adapter.Capabilities.t()`.

  ## Example implementation

      @impl Drone.Adapter
      def capabilities(%__MODULE__{positioning: positioning}) do
        Drone.Adapter.Capabilities.crazyflie(positioning: positioning)
      end
  """
  @callback capabilities(state :: state()) :: Capabilities.t()

  @optional_callbacks [disconnect: 1, capabilities: 1]

  @doc """
  Returns the adapter module for a given adapter identifier.

  ## Parameters

    * `adapter` (`atom() | module()`) — `:sim`, `:tello`, `:crazyflie`, or a
      module that implements this behaviour

  ## Returns

    * `{:ok, module()}` — resolved module
    * `{:error, :unknown_adapter}` — reserved for future use; bare atoms that
      are not built-in keys are currently treated as modules

  ## Examples

      {:ok, Drone.Adapters.Sim} = Drone.Adapter.resolve(:sim)
      {:ok, Drone.Adapters.Tello} = Drone.Adapter.resolve(:tello)
      {:ok, Drone.Adapters.Crazyflie} = Drone.Adapter.resolve(:crazyflie)
      {:ok, MyApp.DroneAdapter} = Drone.Adapter.resolve(MyApp.DroneAdapter)
  """
  @spec resolve(atom() | module()) :: {:ok, module()} | {:error, :unknown_adapter}
  def resolve(:sim), do: {:ok, Drone.Adapters.Sim}
  def resolve(:tello), do: {:ok, Drone.Adapters.Tello}
  def resolve(:crazyflie), do: {:ok, Drone.Adapters.Crazyflie}
  def resolve(module) when is_atom(module), do: {:ok, module}
  def resolve(_), do: {:error, :unknown_adapter}

  @doc """
  Returns capabilities for an adapter state, with a Tello-like default.

  ## Parameters

    * `module` (`module()`) — adapter module
    * `state` (`t:state/0`) — adapter state from `connect/1`

  ## Returns

  `Drone.Adapter.Capabilities.t()`.

  ## Examples

      caps = Drone.Adapter.capabilities(Drone.Adapters.Sim, sim_state)
      :required = caps.sdk_mode
  """
  @spec capabilities(module(), state()) :: Capabilities.t()
  def capabilities(module, state) when is_atom(module) do
    if function_exported?(module, :capabilities, 1) do
      module.capabilities(state)
    else
      Capabilities.tello_like()
    end
  end
end
