defmodule Drone.Adapter.Capabilities do
  @moduledoc """
  Adapter capability descriptors.

  Capabilities let missions and callers discover what an adapter supports
  without leaking vehicle-specific concepts into the public `Drone` API.
  Adapters may implement optional `c:Drone.Adapter.capabilities/1`; when
  omitted, `Drone.Adapter.capabilities/2` falls back to `tello_like/0`.

  ## Examples

      caps = Drone.Adapter.Capabilities.crazyflie(positioning: :flow)
      true = Drone.Adapter.Capabilities.supports_command?(caps, :takeoff)
      false = Drone.Adapter.Capabilities.supports_command?(caps, :flip)
  """

  @typedoc """
  Capability map advertised by an adapter.

  All keys are optional so adapters can publish only what they know. Extra
  adapter-specific atoms (for example `:requires_estimator`, `:link`) are
  allowed via `atom() => term()`.

  | Key | Possible values | Meaning |
  | --- | --- | --- |
  | `:sdk_mode` | `:required` \\| `:optional` \\| `:not_applicable` | Whether `connect_sdk` / `:sdk_mode` is mandatory before flight |
  | `:commands` | `[atom()]` | Command types supported by `Drone.Command` / the adapter |
  | `:queries` | `[atom()]` | Query types accepted by `:query` commands |
  | `:positioning` | `atom()` \\| `nil` | Positioning model (`:dead_reckoning`, `:flow`, `:lighthouse`, `:loco`, …) |
  | `:units` | map | Canonical units for distance / angle / duration |
  | `:maneuver_completion` | `:immediate` \\| `:awaited` \\| `:fire_and_forget` | How move completion is observed |
  | `:requires_estimator` | `boolean()` | Crazyflie: takeoff needs estimator ready |
  | `:link` | `atom()` | Physical link hint (`:crazyradio`, …) |

  `:units` map keys:

  | Key | Possible values |
  | --- | --- |
  | `:distance` | `:cm` |
  | `:angle` | `:degrees` |
  | `:duration` | `:milliseconds` \\| `:seconds` |

  ## Examples

      %{
        sdk_mode: :required,
        commands: [:takeoff, :land, :move, :query],
        queries: [:battery, :height],
        positioning: :dead_reckoning,
        units: %{distance: :cm, angle: :degrees, duration: :seconds},
        maneuver_completion: :awaited
      }

      %{
        sdk_mode: :optional,
        maneuver_completion: :fire_and_forget,
        requires_estimator: true,
        link: :crazyradio,
        positioning: :flow
      }
  """
  @type t :: %{
          optional(:sdk_mode) => :required | :optional | :not_applicable,
          optional(:commands) => [atom()],
          optional(:queries) => [atom()],
          optional(:positioning) => atom() | nil,
          optional(:units) => %{
            optional(:distance) => :cm,
            optional(:angle) => :degrees,
            optional(:duration) => :milliseconds | :seconds
          },
          optional(:maneuver_completion) => :immediate | :awaited | :fire_and_forget,
          atom() => term()
        }

  @default_commands [
    :sdk_mode,
    :takeoff,
    :land,
    :emergency,
    :move,
    :rotate,
    :flip,
    :hover,
    :speed,
    :stop,
    :query
  ]

  @default_queries [
    :battery,
    :height,
    :speed,
    :time,
    :wifi,
    :sdk_version,
    :serial_number
  ]

  @doc """
  Default capabilities for Tello-shaped adapters (Sim and Tello).

  SDK mode is required, maneuvers wait for completion, and positioning is
  dead-reckoning from commanded moves.

  ## Returns

  `t:t/0` capability map.

  ## Examples

      caps = Drone.Adapter.Capabilities.tello_like()
      :required = caps.sdk_mode
      :awaited = caps.maneuver_completion
      true = Drone.Adapter.Capabilities.supports_command?(caps, :flip)
  """
  @spec tello_like() :: t()
  def tello_like do
    %{
      sdk_mode: :required,
      commands: @default_commands,
      queries: @default_queries,
      positioning: :dead_reckoning,
      units: %{distance: :cm, angle: :degrees, duration: :seconds},
      maneuver_completion: :awaited
    }
  end

  @doc """
  Capabilities advertised by the Crazyflie adapter.

  SDK mode is optional (no-op for mission portability). Maneuvers are
  fire-and-forget at the CRTP layer. Flip is not listed.

  ## Parameters

    * `opts` (`keyword()`) — optional overrides:
      * `:positioning` (`atom()`) — defaults to `:flow`; also `:lighthouse`, `:loco`, …

  ## Returns

  `t:t/0` including Crazyflie extras `:requires_estimator` and `:link`.

  ## Examples

      caps = Drone.Adapter.Capabilities.crazyflie(positioning: :lighthouse)
      :optional = caps.sdk_mode
      :fire_and_forget = caps.maneuver_completion
      true = caps.requires_estimator
      :crazyradio = caps.link
      :lighthouse = caps.positioning
      false = Drone.Adapter.Capabilities.supports_command?(caps, :flip)
  """
  @spec crazyflie(keyword()) :: t()
  def crazyflie(opts \\ []) do
    positioning = Keyword.get(opts, :positioning, :flow)

    %{
      sdk_mode: :optional,
      commands: [
        :sdk_mode,
        :takeoff,
        :land,
        :emergency,
        :move,
        :rotate,
        :hover,
        :stop,
        :query
      ],
      queries: [:battery, :height, :sdk_version, :serial_number],
      positioning: positioning,
      units: %{distance: :cm, angle: :degrees, duration: :seconds},
      maneuver_completion: :fire_and_forget,
      requires_estimator: true,
      link: :crazyradio
    }
  end

  @doc """
  Returns whether `command_type` is listed as supported.

  When `:commands` is missing, the Tello default command list is used.

  ## Parameters

    * `caps` (`t:t/0`) — capability map
    * `command_type` (`atom()`) — for example `:takeoff`, `:flip`

  ## Returns

  `boolean()`.

  ## Examples

      caps = Drone.Adapter.Capabilities.tello_like()
      true = Drone.Adapter.Capabilities.supports_command?(caps, :takeoff)
      true = Drone.Adapter.Capabilities.supports_command?(caps, :flip)

      cf = Drone.Adapter.Capabilities.crazyflie()
      false = Drone.Adapter.Capabilities.supports_command?(cf, :flip)
  """
  @spec supports_command?(t(), atom()) :: boolean()
  def supports_command?(caps, type) when is_map(caps) and is_atom(type) do
    type in Map.get(caps, :commands, @default_commands)
  end

  @doc """
  Returns whether `query_type` is listed as supported.

  When `:queries` is missing, the Tello default query list is used.

  ## Parameters

    * `caps` (`t:t/0`) — capability map
    * `query_type` (`atom()`) — for example `:battery`, `:wifi`

  ## Returns

  `boolean()`.

  ## Examples

      caps = Drone.Adapter.Capabilities.crazyflie()
      true = Drone.Adapter.Capabilities.supports_query?(caps, :battery)
      false = Drone.Adapter.Capabilities.supports_query?(caps, :wifi)
  """
  @spec supports_query?(t(), atom()) :: boolean()
  def supports_query?(caps, type) when is_map(caps) and is_atom(type) do
    type in Map.get(caps, :queries, @default_queries)
  end
end
