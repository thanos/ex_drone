defmodule Drone.Adapters.Tello.Parser do
  @moduledoc """
  Parses Tello UDP response strings into structured responses.

  Tello responses are plain ASCII: `ok`, `error`, or numeric values
  for query commands.
  """

  @type parse_result ::
          {:ok, :ok}
          | {:ok, integer()}
          | {:ok, String.t()}
          | {:error, :command_error}
          | {:error, :timeout}
          | {:error, :socket_error}

  @spec parse(binary()) :: parse_result()
  def parse(response) when is_binary(response) do
    trimmed = String.trim(response)

    cond do
      trimmed == "ok" -> {:ok, :ok}
      trimmed == "error" -> {:error, :command_error}
      match = Regex.run(~r/^(\d+)$/, trimmed) -> {:ok, String.to_integer(Enum.at(match, 1))}
      byte_size(trimmed) > 0 -> {:ok, trimmed}
      true -> {:error, :command_error}
    end
  end

  def parse(nil), do: {:error, :timeout}
  def parse(:timeout), do: {:error, :timeout}
end
