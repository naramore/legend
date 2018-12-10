defmodule Legend.Utils do
  @moduledoc """
  """

  @typedoc """
  """
  @type f :: function | mfa | {module, atom}

  @typedoc """
  """
  @type execute_error_reason ::
    {:raise, Exception.t, Exception.stacktrace} |
    {:throw, value :: term} |
    {:exit, reason :: term} |
    reason :: term

  @doc """
  """
  @spec get_local_metadata() :: Keyword.t
  def get_local_metadata() do
    [
      application: (case :application.get_application() do
        :undefined -> nil
        otherwise -> otherwise
      end),
      module: __ENV__.module,
      function: __ENV__.function,
      line: __ENV__.line,
      file: __ENV__.file,
      pid: self(),
    ]
  end

  @doc """
  """
  @spec execute(f, [term], timeout) ::
    {:error, execute_error_reason} |
    result :: term
  def execute(fun, args, timeout \\ :infinity) do
    try do
      Task.Supervisor.async_nolink(
        Legend.TaskSupervisor,
        fn -> execute!(fun, args) end
      )
      |> Task.yield(timeout)
      |> case do
        nil -> {:error, {:timeout, timeout}}
        {:exit, reason} -> {:error, {:exit, reason}}
        {:ok, result} -> result
      end
    rescue
      error -> {:error, {:raise, error, __STACKTRACE__}}
    catch
      value -> {:error, {:throw, value}}
    end
  end

  @doc """
  """
  @spec execute(function | mfa | {module, atom}, [term]) :: term | no_return
  def execute!(fun, args) when is_function(fun), do: apply(fun, args)
  def execute!({mod, fun, _}, args), do: apply(mod, fun, args)
  def execute!({mod, fun}, args), do: apply(mod, fun, args)
end
