defmodule Legend.ErrorHandler do
  @moduledoc """
  """

  alias Legend.{Event, Hook, Utils}

  # @stacktrace_modules_blacklist []
  # @stacktrace_functions_whitelist []

  @typedoc """
  """
  @type accumulator :: %{
    effects_so_far: Legend.effects,
    reason: term,
  }

  @typedoc """
  """
  @type error_reason ::
    {:raise, Exception.t, Exception.stacktrace} |
    {:exit, reason :: term} |
    {:throw, value :: term}

  @doc """
  """
  @callback handle_error(error_reason, Legend.full_name, Legend.effects) ::
    error_reason | {:ok, valid_result :: term}

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Legend.ErrorHandler

      @impl Legend.ErrorHandler
      def handle_error(reason, _location, _effects_so_far) do
        {:error, reason}
      end

      defoverridable [handle_error: 3]
    end
  end

  @doc """
  """
  @spec step(Legend.stage, Event.t, accumulator, BaseStage.execute_opts) :: {Event.t, accumulator} | no_return
  def step(stage, event, state, opts \\ [])
  def step(stage, %Event{name: [:starting, :error_handler]} = e, acc, opts) do
    {originating_event, _} = e.context
    event = execute_error_handler(stage, originating_event, acc, opts)
    {event, %{acc | hooks_left: Hook.merge_hooks(stage, opts)}}
  end
  def step(stage, %Event{name: [:completed, :error_handler]} = e, state, opts) do
    case e.context do
      {origin, {:ok, result}} ->
        {Event.update(origin, context: result),
         %{state | hooks_left: Hook.merge_hooks(stage, opts), reason: nil}}
      {_, {:raise, error, stacktrace}} ->
        filter_and_reraise(error, stacktrace)
      {_, {:throw, value}} ->
        throw value
      {_, {:exit, reason}} ->
        exit reason
    end
  end

  @doc false
  @spec maybe_execute_error_handler(Legend.stage, Event.t, accumulator, BaseStage.execute_opts) :: Event.t
  def maybe_execute_error_handler(stage, event, acc, opts) do
    result = if Keyword.get(opts, :dry_run?, false) do
      Keyword.get(opts, :dry_run_result, {:throw, :default})
    else
      execute_error_handler(stage, event, acc, opts)
    end

    Event.update(event, name: [:completed, :error_handler],
                        context: {event, result})
  end

  @doc """
  """
  @spec execute_error_handler(Legend.stage, Event.t, accumulator, BaseStage.execute_opts) ::
    error_reason | {:ok, valid_result :: term} | no_return
  def execute_error_handler(stage, event, acc, opts \\ []) do
    %{effects_so_far: effects_so_far, reason: reason} = acc
    timeout = Keyword.get(opts, :timeout, :infinity)
    case Utils.execute(get_error_handler(stage), [reason, event.stage_name, effects_so_far], timeout) do
      {:error, {:raise, error, stacktrace}} -> {:raise, error, stacktrace}
      {:raise, error, stacktrace} -> {:raise, error, stacktrace}
      {:error, {:throw, value}} -> {:throw, value}
      {:throw, value} -> {:throw, value}
      {:error, {:exit, reason}} -> {:exit, reason}
      {:ok, result} -> {:ok, result}
      # TODO: this should return {:raise, Legend.InvalidHandlerResponseError(...), stacktrace}
      #otherwise -> {:error, {:unsupported_error_handler_result_form, otherwise}}
    end
  end

  @doc false
  @spec get_error_handler(Legend.stage) :: (error_reason, Legend.full_name, Legend.effects -> error_reason | {:ok, valid_result :: term})
  defp get_error_handler(stage) when is_list(stage) do
    Keyword.get(stage, :error_handler)
  end
  defp get_error_handler(stage) when is_atom(stage) do
    &stage.error_handler/3
  end

  # TODO: implement filtering for stacktraces...
  @doc false
  @spec filter_and_reraise(Exception.t, Exception.stacktrace) :: no_return
  defp filter_and_reraise(exception, stacktrace) do
    #stacktrace =
    #  Enum.reject(stacktrace, &match?({mod, fun, _, _} when mod in @stacktrace_modules_blacklist and
    #                                                        fun not in @stacktrace_functions_whitelist, &1))

    reraise(exception, stacktrace)
  end
end

defmodule Legend.RaiseErrorHandler do
  @moduledoc """
  """

  use Legend.ErrorHandler
end
