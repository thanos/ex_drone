defmodule Drone.Adapters.Crazyflie.LinkURI do
  @moduledoc """
  Parses Crazyflie link URIs.

  Supported forms:

      radio://0/80/2M/E7E7E7E7E7
      radio://0/80/2M
      mock://default
      mock://ready

  Optional query parameters: `safelink=0|1`, `timeout=<ms>`.

  ## Examples

      {:ok, uri} = Drone.Adapters.Crazyflie.LinkURI.parse("radio://0/80/2M")
      :radio = uri.scheme
      80 = uri.channel
      :rate_2m = uri.datarate
  """

  @typedoc """
  Parsed link URI used by Crazyflie transports.

  | Field | Type | Meaning |
  | --- | --- | --- |
  | `:scheme` | `:radio` \\| `:mock` | Transport family |
  | `:radio_index` | `non_neg_integer()` \\| `nil` | Crazyradio device index (`radio://`) |
  | `:channel` | `0..125` \\| `nil` | RF channel (`radio://`) |
  | `:datarate` | `:rate_250k` \\| `:rate_1m` \\| `:rate_2m` \\| `nil` | Radio data rate |
  | `:address` | `binary()` \\| `nil` | 5-byte radio address (default `E7E7E7E7E7`) |
  | `:mock_profile` | `atom()` \\| `nil` | Mock profile (`:ready`, `:low_battery`, …) |
  | `:safelink` | `boolean()` | SafeLink framing (default `false`; enable with `?safelink=1`) |
  | `:timeout_ms` | `pos_integer()` | USB/IO timeout in milliseconds (default `1000`) |

  ## Examples

      %{
        scheme: :radio,
        radio_index: 0,
        channel: 80,
        datarate: :rate_2m,
        address: <<0xE7, 0xE7, 0xE7, 0xE7, 0xE7>>,
        mock_profile: nil,
        safelink: false,
        timeout_ms: 1000
      }

      %{
        scheme: :mock,
        mock_profile: :ready,
        radio_index: nil,
        channel: nil,
        datarate: nil,
        address: nil,
        safelink: false,
        timeout_ms: 500
      }
  """
  @type t :: %{
          scheme: :radio | :mock,
          radio_index: non_neg_integer() | nil,
          channel: 0..125 | nil,
          datarate: :rate_250k | :rate_1m | :rate_2m | nil,
          address: binary() | nil,
          mock_profile: atom() | nil,
          safelink: boolean(),
          timeout_ms: pos_integer()
        }

  @default_address <<0xE7, 0xE7, 0xE7, 0xE7, 0xE7>>

  @doc """
  Parses a URI string into a structured map.

  ## Parameters

    * `uri` (`String.t()`) — for example `"radio://0/80/2M"` or
      `"mock://ready?timeout=500"`

  ## Returns

    * `{:ok, t()}` — parsed URI
    * `{:error, term()}` — common reasons:
      * `:unsupported_scheme`, `:invalid_uri`
      * `:missing_radio_index`, `:invalid_radio_index`
      * `:missing_channel`, `:invalid_channel`
      * `:invalid_datarate`, `:invalid_address`, `:invalid_address_length`
      * `:invalid_safelink`, `:invalid_timeout`

  ## Examples

      {:ok, %{scheme: :mock, mock_profile: :ready}} =
        Drone.Adapters.Crazyflie.LinkURI.parse("mock://ready")

      {:ok, %{channel: 80, safelink: false, timeout_ms: 2000}} =
        Drone.Adapters.Crazyflie.LinkURI.parse(
          "radio://0/80/2M?safelink=0&timeout=2000"
        )

      {:error, :unsupported_scheme} =
        Drone.Adapters.Crazyflie.LinkURI.parse("usb://0")
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, term()}
  def parse(uri) when is_binary(uri) do
    uri = String.trim(uri)

    with {:ok, {scheme, rest}} <- split_scheme(uri),
         {:ok, {path, query}} <- split_query(rest),
         {:ok, base} <- parse_path(scheme, path),
         {:ok, opts} <- parse_query(query) do
      {:ok, Map.merge(base, opts)}
    end
  end

  def parse(_), do: {:error, :invalid_uri}

  defp split_scheme("radio://" <> rest), do: {:ok, {:radio, rest}}
  defp split_scheme("mock://" <> rest), do: {:ok, {:mock, rest}}
  defp split_scheme(_), do: {:error, :unsupported_scheme}

  defp split_query(rest) do
    case String.split(rest, "?", parts: 2) do
      [path] -> {:ok, {path, ""}}
      [path, query] -> {:ok, {path, query}}
    end
  end

  defp parse_path(:mock, path) do
    case mock_profile(String.trim(path)) do
      {:ok, profile} ->
        {:ok,
         %{
           scheme: :mock,
           radio_index: nil,
           channel: nil,
           datarate: nil,
           address: nil,
           mock_profile: profile,
           safelink: false,
           timeout_ms: 1000
         }}

      {:error, _} = err ->
        err
    end
  end

  defp parse_path(:radio, path) do
    parts = path |> String.split("/", trim: true)

    with {:ok, index, rest} <- take_index(parts),
         {:ok, channel, rest} <- take_channel(rest),
         {:ok, datarate, rest} <- take_datarate(rest),
         {:ok, address} <- take_address(rest) do
      {:ok,
       %{
         scheme: :radio,
         radio_index: index,
         channel: channel,
         datarate: datarate,
         address: address,
         mock_profile: nil,
         # SafeLink defaults off; `?safelink=1` negotiates Bitcraze SafeLink on open.
         safelink: false,
         timeout_ms: 1000
       }}
    end
  end

  defp mock_profile(""), do: {:ok, :default}
  defp mock_profile("default"), do: {:ok, :default}
  defp mock_profile("ready"), do: {:ok, :ready}
  defp mock_profile("estimator_not_ready"), do: {:ok, :estimator_not_ready}
  defp mock_profile("low_battery"), do: {:ok, :low_battery}
  defp mock_profile("unplug"), do: {:ok, :unplug}
  defp mock_profile(_), do: {:error, :unknown_mock_profile}

  defp take_index([index | rest]) do
    case Integer.parse(index) do
      {n, ""} when n >= 0 -> {:ok, n, rest}
      _ -> {:error, :invalid_radio_index}
    end
  end

  defp take_index([]), do: {:error, :missing_radio_index}

  defp take_channel([channel | rest]) do
    case Integer.parse(channel) do
      {n, ""} when n in 0..125 -> {:ok, n, rest}
      _ -> {:error, :invalid_channel}
    end
  end

  defp take_channel([]), do: {:error, :missing_channel}

  defp take_datarate([rate | rest]) do
    case String.upcase(rate) do
      "250K" -> {:ok, :rate_250k, rest}
      "1M" -> {:ok, :rate_1m, rest}
      "2M" -> {:ok, :rate_2m, rest}
      _ -> {:error, :invalid_datarate}
    end
  end

  defp take_datarate([]), do: {:ok, :rate_2m, []}

  defp take_address([]), do: {:ok, @default_address}

  defp take_address([hex | _]) do
    cleaned = String.replace(hex, ~r/[^0-9A-Fa-f]/, "")

    case Base.decode16(cleaned, case: :mixed) do
      {:ok, <<_::binary-size(5)>> = addr} -> {:ok, addr}
      {:ok, _} -> {:error, :invalid_address_length}
      :error -> {:error, :invalid_address}
    end
  end

  defp parse_query(""), do: {:ok, %{}}

  defp parse_query(query) do
    opts =
      query
      |> Elixir.URI.decode_query()
      |> Enum.reduce_while(%{}, fn {k, v}, acc ->
        case normalize_opt(k, v) do
          {:ok, key, value} -> {:cont, Map.put(acc, key, value)}
          :skip -> {:cont, acc}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case opts do
      {:error, _} = err -> err
      map when is_map(map) -> {:ok, map}
    end
  end

  defp normalize_opt("safelink", "0"), do: {:ok, :safelink, false}
  defp normalize_opt("safelink", "1"), do: {:ok, :safelink, true}
  defp normalize_opt("safelink", _), do: {:error, :invalid_safelink}

  defp normalize_opt("timeout", value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> {:ok, :timeout_ms, n}
      _ -> {:error, :invalid_timeout}
    end
  end

  defp normalize_opt(_, _), do: :skip
end
