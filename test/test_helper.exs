ExUnit.start(exclude: [:pending], max_cases: 1)

case Application.ensure_all_started(:ex_drone) do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
  {:error, {:already_started, :ex_drone}} -> :ok
  _ -> :ok
end
