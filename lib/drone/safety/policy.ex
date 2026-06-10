defmodule Drone.Safety.Policy do
  @moduledoc """
  Safety policy struct and defaults.

  A policy defines the safety rules applied to every command before it
  reaches the drone adapter. Policies are configured at connection time
  and cannot be changed while a drone is connected.

  ## Presets

    - `Drone.Safety.Policy.default/0` -- safe defaults for outdoor flight
    - `Drone.Safety.Policy.indoor/0` -- tighter limits for indoor flight
    - `Drone.Safety.Policy.unrestricted/0` -- no safety limits (use with caution)

  ## Example

      policy = Drone.Safety.Policy.new(max_altitude_cm: 200, indoor: true)
      {:ok, drone} = Drone.connect(:sim, name: :test, safety: policy)
  """

  @type t :: %__MODULE__{
          max_altitude_cm: pos_integer() | nil,
          max_distance_cm: pos_integer() | nil,
          min_battery_percent: non_neg_integer(),
          battery_warning_percent: non_neg_integer(),
          allowlist: [atom()] | nil,
          dry_run: boolean(),
          indoor: boolean(),
          prop_guards: boolean(),
          geofence: Drone.Safety.Geofence.t() | nil
        }

  defstruct [
    :max_altitude_cm,
    :max_distance_cm,
    :geofence,
    min_battery_percent: 15,
    battery_warning_percent: 20,
    allowlist: nil,
    dry_run: false,
    indoor: false,
    prop_guards: false
  ]

  @doc """
  Creates a new policy with the given options.

  Options:

    - `:max_altitude_cm` -- maximum allowed altitude in cm (default: 300)
    - `:max_distance_cm` -- maximum distance from launch point in cm (default: 1000)
    - `:min_battery_percent` -- minimum battery for takeoff (default: 15)
    - `:battery_warning_percent` -- battery level for warnings (default: 20)
    - `:allowlist` -- list of allowed command types, or nil for all (default: nil)
    - `:dry_run` -- if true, commands pass safety but are not sent (default: false)
    - `:indoor` -- if true, applies indoor preset limits (default: false)
    - `:prop_guards` -- whether prop guards are installed (default: false)
    - `:geofence` -- a geofence to restrict flight area (default: nil)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    base = if Keyword.get(opts, :indoor, false), do: indoor(), else: default()

    policy = %__MODULE__{
      max_altitude_cm: Keyword.get(opts, :max_altitude_cm, base.max_altitude_cm),
      max_distance_cm: Keyword.get(opts, :max_distance_cm, base.max_distance_cm),
      min_battery_percent: Keyword.get(opts, :min_battery_percent, base.min_battery_percent),
      battery_warning_percent:
        Keyword.get(opts, :battery_warning_percent, base.battery_warning_percent),
      allowlist: Keyword.get(opts, :allowlist, base.allowlist),
      dry_run: Keyword.get(opts, :dry_run, base.dry_run),
      indoor: Keyword.get(opts, :indoor, base.indoor),
      prop_guards: Keyword.get(opts, :prop_guards, base.prop_guards),
      geofence: Keyword.get(opts, :geofence, base.geofence)
    }

    policy
  end

  @doc """
  Default safety policy for outdoor flight.

    - Max altitude: 300 cm (3 meters)
    - Max distance: 1000 cm (10 meters)
    - Min battery: 15%
    - Battery warning: 20%
  """
  @spec default() :: t()
  def default do
    %__MODULE__{
      max_altitude_cm: 300,
      max_distance_cm: 1000,
      min_battery_percent: 15,
      battery_warning_percent: 20,
      allowlist: nil,
      dry_run: false,
      indoor: false,
      prop_guards: false,
      geofence: nil
    }
  end

  @doc """
  Indoor safety policy with tighter limits.

    - Max altitude: 200 cm (2 meters)
    - Max distance: 500 cm (5 meters)
    - Min battery: 20%
    - Battery warning: 25%
    - Prop guards assumed: true
  """
  @spec indoor() :: t()
  def indoor do
    %__MODULE__{
      max_altitude_cm: 200,
      max_distance_cm: 500,
      min_battery_percent: 20,
      battery_warning_percent: 25,
      allowlist: nil,
      dry_run: false,
      indoor: true,
      prop_guards: true,
      geofence: nil
    }
  end

  @doc """
  Unrestricted safety policy with no limits.

  Use with extreme caution. This disables all altitude, distance,
  and battery checks. Emergency commands still work.
  """
  @spec unrestricted() :: t()
  def unrestricted do
    %__MODULE__{
      max_altitude_cm: nil,
      max_distance_cm: nil,
      min_battery_percent: 0,
      battery_warning_percent: 0,
      allowlist: nil,
      dry_run: false,
      indoor: false,
      prop_guards: true,
      geofence: nil
    }
  end
end
