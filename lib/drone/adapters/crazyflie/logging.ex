defmodule Drone.Adapters.Crazyflie.Logging do
  @moduledoc """
  Pure CRTP logging (port 5) packet builders and parsers.

  Used to subscribe to battery and flight-readiness variables on a real
  Crazyflie via TOC download + log block create/start. Packet layouts follow
  the documented Bitcraze logging protocol (TOC V2 / control V2).

  ## Typical sequence

      reset = Drone.Adapters.Crazyflie.Logging.reset()
      info = Drone.Adapters.Crazyflie.Logging.get_toc_info()
      item = Drone.Adapters.Crazyflie.Logging.get_toc_item(0)
      create = Drone.Adapters.Crazyflie.Logging.create_block_v2(0, [{1, 10}, {1, 20}])
      start = Drone.Adapters.Crazyflie.Logging.start_block_v2(0, 100)

  Preferred variables:

  * `pm.batteryLevel` (uint8 %) — fallback `pm.vbat` (float volts → %)
  * `sys.canfly` (uint8) — non-zero means estimator / platform ready to fly
  """

  alias Drone.Adapters.Crazyflie.CRTP
  alias Drone.Adapters.Crazyflie.CRTP.Ports

  @toc_channel 0
  @control_channel 1
  @data_channel 2

  @get_item_v2 0x02
  @get_info_v2 0x03
  @reset 0x05
  @create_block_v2 0x06
  @start_block_v2 0x08

  @type_uint8 1
  @type_uint16 2
  @type_uint32 3
  @type_int8 4
  @type_int16 5
  @type_int32 6
  @type_float 7
  @type_fp16 8

  @default_block_id 0
  @default_period_ms 100

  @canfly_names [{"sys", "canfly"}]

  @typedoc "One TOC entry resolved from GET_ITEM_V2."
  @type toc_item :: %{
          id: non_neg_integer(),
          type: non_neg_integer(),
          group: String.t(),
          name: String.t()
        }

  @typedoc "Log block layout entry used when decoding data packets."
  @type layout_entry :: %{
          key: :battery | :estimator_ready | atom(),
          type: non_neg_integer(),
          id: non_neg_integer(),
          source: :battery_level | :vbat | :canfly
        }

  @doc "Default log block id used by the Crazyflie adapter (`0`)."
  @spec default_block_id() :: 0
  def default_block_id, do: @default_block_id

  @doc "Default log period in milliseconds (`100`)."
  @spec default_period_ms() :: 100
  def default_period_ms, do: @default_period_ms

  @doc "Log TOC channel (`0`)."
  @spec toc_channel() :: 0
  def toc_channel, do: @toc_channel

  @doc "Log control channel (`1`)."
  @spec control_channel() :: 1
  def control_channel, do: @control_channel

  @doc "Log data channel (`2`)."
  @spec data_channel() :: 2
  def data_channel, do: @data_channel

  @doc """
  Builds GET_INFO_V2 (TOC size / CRC / limits).
  """
  @spec get_toc_info() :: CRTP.packet()
  def get_toc_info do
    toc_packet(<<@get_info_v2>>)
  end

  @doc """
  Builds GET_ITEM_V2 for TOC entry `id`.
  """
  @spec get_toc_item(non_neg_integer()) :: CRTP.packet()
  def get_toc_item(id) when is_integer(id) and id >= 0 do
    toc_packet(<<@get_item_v2, id::little-16>>)
  end

  @doc """
  Builds RESET — deletes all log blocks.
  """
  @spec reset() :: CRTP.packet()
  def reset do
    control_packet(<<@reset>>)
  end

  @doc """
  Builds CREATE_BLOCK_V2.

  `ops` is a list of `{log_type, variable_id}` tuples.
  """
  @spec create_block_v2(byte(), [{byte(), non_neg_integer()}]) :: CRTP.packet()
  def create_block_v2(block_id, ops)
      when is_integer(block_id) and block_id in 0..255 and is_list(ops) do
    ops_bin =
      Enum.reduce(ops, <<>>, fn {type, var_id}, acc ->
        <<acc::binary, type, var_id::little-16>>
      end)

    control_packet(<<@create_block_v2, block_id, ops_bin::binary>>)
  end

  @doc """
  Builds START_BLOCK_V2 with period in milliseconds.
  """
  @spec start_block_v2(byte(), pos_integer()) :: CRTP.packet()
  def start_block_v2(block_id, period_ms)
      when is_integer(block_id) and block_id in 0..255 and is_integer(period_ms) and period_ms > 0 do
    control_packet(<<@start_block_v2, block_id, period_ms::little-16>>)
  end

  @doc """
  Parses GET_INFO_V2 reply payload (without CRTP header).
  """
  @spec parse_toc_info(binary()) :: {:ok, map()} | {:error, :invalid_toc_info}
  def parse_toc_info(<<@get_info_v2, len::little-16, crc::little-32, max_blocks, max_ops>>) do
    {:ok, %{count: len, crc: crc, max_blocks: max_blocks, max_ops: max_ops}}
  end

  def parse_toc_info(_), do: {:error, :invalid_toc_info}

  @doc """
  Parses GET_ITEM_V2 reply payload into a TOC item.
  """
  @spec parse_toc_item(binary()) :: {:ok, toc_item()} | {:error, term()}
  def parse_toc_item(<<@get_item_v2, id::little-16, type, rest::binary>>) do
    with {:ok, group, rest} <- take_cstring(rest),
         {:ok, name, _} <- take_cstring(rest) do
      {:ok, %{id: id, type: type, group: group, name: name}}
    else
      _ -> {:error, :invalid_toc_item}
    end
  end

  def parse_toc_item(<<@get_item_v2>>), do: {:error, :toc_id_out_of_range}
  def parse_toc_item(_), do: {:error, :invalid_toc_item}

  @doc """
  Parses a control-channel reply (`<<cmd, block_id, result>>`).
  """
  @spec parse_control_result(binary()) ::
          {:ok, %{command: byte(), block_id: byte(), result: byte()}} | {:error, term()}
  def parse_control_result(<<cmd, block_id, result>>) do
    {:ok, %{command: cmd, block_id: block_id, result: result}}
  end

  def parse_control_result(<<@reset, _unused, result>>) do
    {:ok, %{command: @reset, block_id: 0, result: result}}
  end

  def parse_control_result(_), do: {:error, :invalid_control_result}

  @doc """
  True when a control result indicates success (`result == 0`).
  """
  @spec control_ok?(map()) :: boolean()
  def control_ok?(%{result: 0}), do: true
  def control_ok?(_), do: false

  @doc """
  Finds battery and can-fly TOC entries and builds a decode layout.

  Prefers `pm.batteryLevel`, falls back to `pm.vbat`. Requires `sys.canfly`.
  """
  @spec resolve_layout([toc_item()]) :: {:ok, [layout_entry()]} | {:error, term()}
  def resolve_layout(items) when is_list(items) do
    by_name =
      Map.new(items, fn item ->
        {{item.group, item.name}, item}
      end)

    with {:ok, battery_entry} <- resolve_battery(by_name),
         {:ok, canfly} <- resolve_named(by_name, @canfly_names, :missing_sys_canfly) do
      {:ok,
       [
         battery_entry,
         %{
           key: :estimator_ready,
           type: canfly.type,
           id: canfly.id,
           source: :canfly
         }
       ]}
    end
  end

  @doc """
  Converts a layout into CREATE_BLOCK_V2 ops.
  """
  @spec layout_ops([layout_entry()]) :: [{byte(), non_neg_integer()}]
  def layout_ops(layout) when is_list(layout) do
    Enum.map(layout, fn entry -> {entry.type, entry.id} end)
  end

  @doc """
  Parses a log-data channel payload using a known layout.
  """
  @spec parse_data(binary(), [layout_entry()]) :: {:ok, map()} | {:error, term()}
  def parse_data(<<_block_id, _ts::little-24, values::binary>>, layout) when is_list(layout) do
    decode_values(values, layout, %{})
  end

  def parse_data(_, _), do: {:error, :invalid_log_data}

  @doc """
  Maps battery voltage in volts to an approximate charge percent.

  Crazyflie LiPo range used: 3.0 V (0%) … 4.2 V (100%).
  """
  @spec battery_percent_from_vbat(number()) :: 0..100
  def battery_percent_from_vbat(volts) when is_number(volts) do
    pct = (volts - 3.0) / (4.2 - 3.0) * 100.0
    pct |> round() |> max(0) |> min(100)
  end

  @doc "Byte size of a log type id."
  @spec type_size(non_neg_integer()) :: pos_integer() | {:error, :unknown_log_type}
  def type_size(@type_uint8), do: 1
  def type_size(@type_int8), do: 1
  def type_size(@type_uint16), do: 2
  def type_size(@type_int16), do: 2
  def type_size(@type_fp16), do: 2
  def type_size(@type_uint32), do: 4
  def type_size(@type_int32), do: 4
  def type_size(@type_float), do: 4
  def type_size(_), do: {:error, :unknown_log_type}

  defp resolve_battery(by_name) do
    cond do
      item = Map.get(by_name, {"pm", "batteryLevel"}) ->
        {:ok, %{key: :battery, type: item.type, id: item.id, source: :battery_level}}

      item = Map.get(by_name, {"pm", "vbat"}) ->
        {:ok, %{key: :battery, type: item.type, id: item.id, source: :vbat}}

      true ->
        {:error, :missing_battery_log_var}
    end
  end

  defp resolve_named(by_name, names, error) do
    Enum.find_value(names, fn key -> Map.get(by_name, key) end)
    |> case do
      nil -> {:error, error}
      item -> {:ok, item}
    end
  end

  defp decode_values(_rest, [], acc), do: {:ok, acc}

  defp decode_values(bin, [entry | rest], acc) do
    case type_size(entry.type) do
      size when is_integer(size) and byte_size(bin) >= size ->
        raw = :binary.part(bin, 0, size)
        next = :binary.part(bin, size, byte_size(bin) - size)

        case decode_typed(entry.type, raw) do
          {:ok, value} ->
            mapped = map_log_value(entry, value)
            decode_values(next, rest, Map.put(acc, entry.key, mapped))

          {:error, _} = err ->
            err
        end

      size when is_integer(size) ->
        {:error, :truncated_log_data}

      {:error, _} = err ->
        err
    end
  end

  defp map_log_value(%{source: :battery_level}, value) when is_integer(value) do
    value |> max(0) |> min(100)
  end

  defp map_log_value(%{source: :vbat}, value) when is_number(value) do
    battery_percent_from_vbat(value)
  end

  defp map_log_value(%{source: :canfly}, value) when is_integer(value), do: value != 0
  defp map_log_value(%{source: :canfly}, value) when is_number(value), do: value != 0.0
  defp map_log_value(_, value), do: value

  defp decode_typed(@type_uint8, <<v>>), do: {:ok, v}
  defp decode_typed(@type_int8, <<v::signed-8>>), do: {:ok, v}
  defp decode_typed(@type_uint16, <<v::little-16>>), do: {:ok, v}
  defp decode_typed(@type_int16, <<v::signed-little-16>>), do: {:ok, v}
  defp decode_typed(@type_uint32, <<v::little-32>>), do: {:ok, v}
  defp decode_typed(@type_int32, <<v::signed-little-32>>), do: {:ok, v}
  defp decode_typed(@type_float, <<v::little-float-32>>), do: {:ok, v}
  defp decode_typed(@type_fp16, _), do: {:error, :fp16_unsupported}
  defp decode_typed(_, _), do: {:error, :invalid_typed_value}

  defp take_cstring(bin) do
    case :binary.split(bin, <<0>>) do
      [str, rest] -> {:ok, str, rest}
      _ -> {:error, :missing_cstring}
    end
  end

  defp toc_packet(payload) do
    %{port: Ports.port(:logging), channel: @toc_channel, payload: payload}
  end

  defp control_packet(payload) do
    %{port: Ports.port(:logging), channel: @control_channel, payload: payload}
  end
end
