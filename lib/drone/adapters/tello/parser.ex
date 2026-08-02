defmodule Drone.Adapters.Tello.Parser do
  @moduledoc """
  Parses Tello UDP response strings into structured replies.

  The Tello SDK replies with plain ASCII over UDP. Typical shapes:

  | Wire response | Parsed result |
  | --- | --- |
  | `"ok"` | `{:ok, :ok}` |
  | `"error"` | `{:error, :command_error}` |
  | `"87"` / `"-1"` | `{:ok, integer()}` (query values) |
  | `"TELLO-AB12CD"` | `{:ok, String.t()}` (non-numeric text such as serial) |
  | empty / unknown blank | `{:error, :command_error}` |
  | `nil` or `:timeout` | `{:error, :timeout}` |

  Whitespace around the payload is trimmed before classification.

  ## Examples

      {:ok, :ok} = Drone.Adapters.Tello.Parser.parse("ok")
      {:ok, 87} = Drone.Adapters.Tello.Parser.parse("87\\r\\n")
      {:error, :command_error} = Drone.Adapters.Tello.Parser.parse("error")
      {:error, :timeout} = Drone.Adapters.Tello.Parser.parse(:timeout)
  """

  @typedoc """
  Result of parsing a Tello UDP reply (or a timeout sentinel).

  | Variant | Meaning |
  | --- | --- |
  | `{:ok, :ok}` | Command acknowledged (`"ok"`) |
  | `{:ok, integer()}` | Numeric query reply (battery, height, …) |
  | `{:ok, String.t()}` | Non-numeric text reply (for example serial number) |
  | `{:error, :command_error}` | `"error"`, empty, or unusable payload |
  | `{:error, :timeout}` | No reply (`nil` / `:timeout` input) |
  | `{:error, :socket_error}` | Reserved for socket-layer failures mapped by callers |

  ## Examples

      {:ok, :ok}
      {:ok, 42}
      {:ok, "1.3"}
      {:error, :command_error}
      {:error, :timeout}
  """
  @type parse_result ::
          {:ok, :ok}
          | {:ok, integer()}
          | {:ok, String.t()}
          | {:error, :command_error}
          | {:error, :timeout}
          | {:error, :socket_error}

  @doc """
  Parses a Tello response payload into a structured result.

  Accepts the raw UDP binary (or charlist-converted binary), plus the
  timeout sentinels `nil` and `:timeout` used when no datagram arrives.

  ## Parameters

    * `response` (`binary()` \\| `nil` \\| `:timeout`) — UDP payload or timeout marker

  ## Returns

  `t:parse_result/0`.

  ## Examples

      iex> Drone.Adapters.Tello.Parser.parse("ok")
      {:ok, :ok}

      iex> Drone.Adapters.Tello.Parser.parse("  error  ")
      {:error, :command_error}

      iex> Drone.Adapters.Tello.Parser.parse("95")
      {:ok, 95}

      iex> Drone.Adapters.Tello.Parser.parse("-3")
      {:ok, -3}

      iex> Drone.Adapters.Tello.Parser.parse("0TO993FABCDE")
      {:ok, "0TO993FABCDE"}

      iex> Drone.Adapters.Tello.Parser.parse("")
      {:error, :command_error}

      iex> Drone.Adapters.Tello.Parser.parse(nil)
      {:error, :timeout}

      iex> Drone.Adapters.Tello.Parser.parse(:timeout)
      {:error, :timeout}
  """
  @spec parse(binary() | nil | :timeout) :: parse_result()
  def parse(response) when is_binary(response) do
    trimmed = String.trim(response)

    cond do
      trimmed == "ok" -> {:ok, :ok}
      trimmed == "error" -> {:error, :command_error}
      match = Regex.run(~r/^(-?\d+)$/, trimmed) -> {:ok, String.to_integer(Enum.at(match, 1))}
      byte_size(trimmed) > 0 -> {:ok, trimmed}
      true -> {:error, :command_error}
    end
  end

  def parse(nil), do: {:error, :timeout}
  def parse(:timeout), do: {:error, :timeout}
end
