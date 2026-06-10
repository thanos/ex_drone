defmodule Drone.Adapters.Sim do
  @moduledoc """
  Simulator adapter for ex_drone.

  The simulator adapter implements `Drone.Adapter` with an in-process state
  machine. It requires no hardware, no network, and no external dependencies.

  This is the primary adapter for development, testing, and education. It
  enforces the same state machine and command protocol as the Tello adapter,
  but uses pure Elixir state instead of UDP communication.

  ## Usage

      {:ok, drone} = Drone.connect(:sim, name: :test)
      Drone.connect_sdk(drone)
      Drone.takeoff(drone)
      Drone.move(drone, :forward, 100)
      Drone.land(drone)
      Drone.disconnect(drone)

  ## Failure Injection

  The simulator can be configured to inject failures for testing error handling:

      {:ok, drone} = Drone.connect(:sim,
        name: :test,
        failure_rate: 1.0,        # always fail
        fail_commands: [:takeoff]  # only fail takeoff
      )

  ## Battery Simulation

  Battery drains at configurable rates per command. Set `battery: 50` to start
  with 50% battery.

      {:ok, drone} = Drone.connect(:sim, name: :test, battery: 30)
  """

  @behaviour Drone.Adapter

  alias Drone.{Adapters.Sim.State, Command, Geometry}

  @impl Drone.Adapter
  def connect(opts) do
    sim_opts =
      Keyword.take(opts, [
        :battery,
        :battery_drain_per_move,
        :battery_drain_per_takeoff,
        :battery_drain_per_land,
        :battery_drain_per_query,
        :failure_rate,
        :fail_commands
      ])

    {:ok, State.new(sim_opts)}
  end

  @impl Drone.Adapter
  def command(%State{} = state, %Command{type: :emergency}) do
    new_state = %{state | mode: :emergency, flying: false}
    {:ok, :ok, State.push_command(new_state, Command.emergency())}
  end

  def command(%State{} = state, %Command{} = cmd) do
    with :ok <- check_failure(state, cmd),
         :ok <- check_mode(state, cmd),
         {:ok, reply, new_state} <- execute(state, cmd) do
      {:ok, reply, new_state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  @impl Drone.Adapter
  def telemetry(%State{} = state) do
    {:ok,
     %{
       x: state.x,
       y: state.y,
       z: state.z,
       yaw: state.yaw,
       battery: trunc(state.battery),
       speed: state.speed,
       flying: state.flying,
       mode: state.mode,
       last_command: state.last_command,
       command_count: length(state.command_history)
     }, state}
  end

  @impl Drone.Adapter
  def disconnect(%State{}), do: :ok

  defp check_failure(%State{config: config}, %Command{type: type}) do
    cond do
      type in config.fail_commands ->
        {:error, :simulated_failure}

      config.failure_rate > 0 and :rand.uniform() < config.failure_rate ->
        {:error, :simulated_failure}

      true ->
        :ok
    end
  end

  defp check_mode(%State{mode: :idle}, %Command{type: :sdk_mode}), do: :ok
  defp check_mode(%State{mode: :idle}, _cmd), do: {:error, :not_in_sdk_mode}
  defp check_mode(%State{mode: :emergency}, _cmd), do: {:error, :emergency_active}
  defp check_mode(%State{mode: :sdk_mode}, %Command{type: :takeoff}), do: :ok
  defp check_mode(%State{mode: :sdk_mode}, %Command{type: :query}), do: :ok
  defp check_mode(%State{mode: :sdk_mode}, %Command{type: :speed}), do: :ok
  defp check_mode(%State{mode: :flying}, _cmd), do: :ok
  defp check_mode(%State{mode: :sdk_mode}, _cmd), do: {:error, :not_flying}

  defp execute(%State{} = state, %Command{type: :sdk_mode}) do
    new_state = %{state | mode: :sdk_mode} |> State.push_command(Command.sdk_mode())
    {:ok, :ok, new_state}
  end

  defp execute(%State{} = state, %Command{type: :takeoff}) do
    new_state =
      %{state | z: 30, flying: true, mode: :flying, speed: 0}
      |> State.push_command(Command.takeoff())
      |> State.drain_battery(state.config.battery_drain_per_takeoff)
      |> State.add_flight_time(3)

    {:ok, :ok, new_state}
  end

  defp execute(%State{} = state, %Command{type: :land}) do
    new_state =
      %{state | z: 0, flying: false, mode: :sdk_mode, speed: 0}
      |> State.push_command(Command.land())
      |> State.drain_battery(state.config.battery_drain_per_land)
      |> State.add_flight_time(3)

    {:ok, :ok, new_state}
  end

  defp execute(%State{} = state, %Command{type: :move, args: args}) do
    direction = Keyword.fetch!(args, :direction)
    distance = Keyword.fetch!(args, :distance)
    {dx, dy, dz} = Geometry.move_delta(direction, distance, state.yaw)

    new_state =
      %{state | x: state.x + dx, y: state.y + dy, z: max(0, state.z + dz)}
      |> State.push_command(Command.move(direction, distance))
      |> State.drain_battery(state.config.battery_drain_per_move)
      |> State.add_flight_time(2)

    {:ok, :ok, new_state}
  end

  defp execute(%State{} = state, %Command{type: :rotate, args: args}) do
    direction = Keyword.fetch!(args, :direction)
    degrees = Keyword.fetch!(args, :degrees)
    new_yaw = Geometry.rotate_yaw(direction, state.yaw, degrees)

    new_state =
      %{state | yaw: new_yaw}
      |> State.push_command(Command.rotate(direction, degrees))
      |> State.drain_battery(state.config.battery_drain_per_move)
      |> State.add_flight_time(2)

    {:ok, :ok, new_state}
  end

  defp execute(%State{} = state, %Command{type: :flip, args: args}) do
    direction = Keyword.fetch!(args, :direction)
    {dx, dy} = Geometry.flip_delta(direction)

    new_state =
      %{state | x: state.x + dx, y: state.y + dy}
      |> State.push_command(Command.flip(direction))
      |> State.drain_battery(state.config.battery_drain_per_move)
      |> State.add_flight_time(2)

    {:ok, :ok, new_state}
  end

  defp execute(%State{} = state, %Command{type: :hover, args: args}) do
    seconds = Keyword.get(args, :seconds, 1)

    new_state =
      state
      |> State.push_command(Command.hover(seconds))
      |> State.add_flight_time(seconds)

    {:ok, :ok, new_state}
  end

  defp execute(%State{} = state, %Command{type: :speed, args: args}) do
    speed = Keyword.fetch!(args, :speed)
    new_state = %{state | speed: speed} |> State.push_command(Command.speed(speed))
    {:ok, :ok, new_state}
  end

  defp execute(%State{} = state, %Command{type: :stop}) do
    new_state = %{state | speed: 0} |> State.push_command(Command.stop())
    {:ok, :ok, new_state}
  end

  defp execute(%State{} = state, %Command{type: :query, args: args}) do
    query_type = Keyword.fetch!(args, :type)

    value =
      case query_type do
        :battery -> trunc(state.battery)
        :height -> state.z
        :speed -> state.speed
        :time -> state.flight_time_seconds
        :wifi -> "sim_wifi"
        :sdk_version -> "sim_1.0"
        :serial_number -> "SIM001"
      end

    new_state =
      state
      |> State.push_command(Command.query(query_type))
      |> State.drain_battery(state.config.battery_drain_per_query)

    {:ok, value, new_state}
  end
end
