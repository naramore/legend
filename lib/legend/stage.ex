defmodule Legend.Stage do
  @moduledoc """
  """

  use Legend.BaseStage
  alias Legend.{ErrorHandler, Event, Hook, Retry, Utils}

  @typedoc """
  """
  @type accumulator :: %{
    hooks_left: [Hook.t],
    effects_so_far: Legend.effects,
    abort?: boolean,
    reason: term,
  }

  @typedoc """
  """
  @type transaction_result :: {:ok, Legend.effect} |
                              {:error, reason :: term} |
                              {:abort, reason :: term}

  @typedoc """
  """
  @type compensation_result :: :ok |
                               :abort |
                               {:retry, Retry.retry_opts} |
                               {:continue, Legend.effect}

  @doc """
  """
  @callback transaction(effects_so_far :: Legend.effects) :: transaction_result

  @doc """
  """
  @callback compensation(reason :: term, effect_to_compensate :: Legend.effect, effects_so_far :: Legend.effects) :: compensation_result

  @doc false
  defmacro __using__(opts) do
    opts = [
      name: __MODULE__,
      hooks: [],
      on_retry: Legend.RetryWithExpoentialBackoff,
      on_compensation_error: Legend.RaiseCompensationErrorHandler,
    ] |> Keyword.merge(opts)
    quote do
      @behaviour Legend.Stage
      @stage_opts unquote(opts)
      alias Legend.Stage

      @spec name() :: Legend.name
      def name(), do: @stage_opts[:name]

      @spec list_hooks() :: [Legend.Hook.t]
      def list_hooks(), do: @stage_opts[:hooks]

      @spec on_retry() :: module
      def on_retry(), do: @stage_opts[:on_retry]

      @spec on_compensation_error() :: module
      def on_compensation_error(), do: @stage_opts[:on_compensation_error]

      @impl Stage
      def compensation(_reason, _effect_to_compensate, _effects_so_far) do
        :ok
      end

      defoverridable [compensation: 2]
    end
  end

  @impl Legend.BaseStage
  def execute(stage, effects_so_far, opts \\ []) do
    full_name = get_full_name(stage, Keyword.get(opts, :parent_full_name, []))
    event = Event.create(
      id: Keyword.get(opts, :id),
      stage_name: full_name,
      name: [:starting, :transaction],
      context: effects_so_far
    )
    {event, %{hooks_left: Hook.merge_hooks(stage, opts),
              effects_so_far: effects_so_far,
              abort?: false,
              reason: nil}}
  end

  @impl Legend.BaseStage
  def compensate(stage, {status, reason}, effects_so_far, opts \\ [])
    when status in [:error, :abort] do
      full_name = get_full_name(stage, Keyword.get(opts, :parent_full_name, []))
      effect = get_in(effects_so_far, tl(full_name))
      event = Event.create(
        id: Keyword.get(opts, :id),
        stage_name: full_name,
        name: [:starting, :compensation],
        context: {reason, effect, effects_so_far}
      )
      abort? = if status == :abort, do: true, else: false
      {event, %{hooks_left: Hook.merge_hooks(stage, opts),
                effects_so_far: effects_so_far,
                abort?: abort?,
                reason: nil}}
  end

  @impl Legend.BaseStage
  def step(stage, event, state, opts \\ [])
  def step(stage, %Event{name: [_, :hook, _]} = event, state, opts) do
    case Hook.step(event, state, opts) do
      {nil, new_state} -> step(stage, event, new_state, opts)
      {next_event, new_state} -> {next_event, new_state}
    end
  end
  def step(_stage, %Event{name: [_, :retry]} = _event, %{hooks_left: []} = _s, _opts) do
    # TODO: hook into Legend.Retry.step/3
    {:error, :not_implemented}
  end
  def step(stage, %Event{name: [_, :error_handler]} = event, %{hooks_left: []} = s, opts) do
    {e, _} = event.context
    ErrorHandler.step(stage, e, s, opts)
  end
  def step(stage, %Event{name: [:starting, :transaction]} = e, %{hooks_left: []} = s, opts) do
    event = maybe_execute_transaction(stage, e, s, opts)
    {event, %{s | hooks_left: Hook.merge_hooks(stage, opts)}}
  end
  def step(stage, %Event{name: [:completed, :transaction]} = e, %{hooks_left: []} = s, opts) do
    case e.context do
      {:ok, result} -> {:ok, result}
      {status, reason} when status in [:error, :abort] ->
        %{effects_so_far: effects_so_far} = s
        event = Event.update(e, name: [:starting, :compensation],
                                context: {{status, reason},
                                          Event.get_effect(e, effects_so_far),
                                          effects_so_far})
        s = if status == :abort, do: %{s | abort?: true}, else: s
        {event, %{s | hooks_left: Hook.merge_hooks(stage, opts)}}
    end
  end
  def step(stage, %Event{name: [:starting, :compensation]} = e, %{hooks_left: []} = s, opts) do
    event = maybe_execute_compensation(stage, e, s, opts)
    %Event{context: {reason, _, _}} = e
    {event, %{s | hooks_left: Hook.merge_hooks(stage, opts), reason: reason}}
  end
  def step(stage, %Event{name: [:completed, :compensation]} = e, %{hooks_left: []} = s, opts) do
    case e.context do
      :ok -> {:error, Map.get(s, :reason)}
      :abort -> {:abort, Map.get(s, :reason)}
      {:retry, retry_opts} ->
        # TODO: maybe this logic should also move over to Legend.Retry?
        %{effects_so_far: effects_so_far} = s
        retry_handler = get_retry_handler(stage)
        retry_state = Retry.get_retry_state(retry_handler, e.stage_name, effects_so_far)
        event = Event.update(e, name: [:starting, :retry],
                                context: {retry_state,
                                          retry_opts})
        {event, %{s | hooks_left: Hook.merge_hooks(stage, opts), reason: nil}}
      {:continue, effect} -> {:ok, effect}
      {:error, _reason} ->
        %{effects_so_far: effects_so_far} = s
        event = Event.update(e, name: [:starting, :error_handler],
                                context: {e, effects_so_far})
        # TODO: reason might not want to be nullified here...
        {event, %{s | hooks_left: Hook.merge_hooks(stage, opts)}}
    end
  end
  def step(_stage, event, %{hooks_left: [h|hs]} = state, opts) do
    {Hook.maybe_execute_hook(h, event, state, opts), %{state | hooks_left: hs}}
  end

  @doc false
  @spec maybe_execute_transaction(Legend.stage, Event.t, accumulator, BaseStage.execute_opts) :: Event.t
  defp maybe_execute_transaction(stage, event, acc, opts) do
    result = if Keyword.get(opts, :dry_run?, false) do
      Keyword.get(opts, :dry_run_result, {:ok, nil})
    else
      execute_transaction(stage, acc, opts)
    end

    Event.update(event, name: [:completed, :transaction],
                        context: result)
  end

  @doc """
  """
  @spec execute_transaction(Legend.stage, accumulator, BaseStage.execute_opts) :: transaction_result
  def execute_transaction(stage, acc, opts \\ []) do
    %{effects_so_far: effects_so_far} = acc
    timeout = Keyword.get(opts, :timeout, :infinity)
    case Utils.execute(get_transaction(stage), [effects_so_far], timeout) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
      {:abort, reason} -> {:abort, reason}
      otherwise -> {:error, {:unsupported_transaction_result_form, otherwise}}
    end
  end

  @doc false
  @spec maybe_execute_compensation(Legend.stage, Event.t, accumulator, BaseStage.execute_opts) :: Event.t
  defp maybe_execute_compensation(stage, event, acc, opts) do
    result = if Keyword.get(opts, :dry_run?, false) do
      Keyword.get(opts, :dry_run_result, :ok)
    else
      execute_compensation(stage, acc, opts)
    end

    Event.update(event, name: [:completed, :compensation],
                        context: result)
  end

  @doc """
  """
  @spec execute_compensation(Legend.stage, accumulator, BaseStage.execute_opts) :: compensation_result
  def execute_compensation(stage, acc, opts \\ []) do
    %{effects_so_far: effects_so_far} = acc
    timeout = Keyword.get(opts, :timeout, :infinity)
    case Utils.execute(get_compensation(stage), [effects_so_far], timeout) do
      :ok -> :ok
      :abort -> :abort
      {:retry, retry_opts} -> {:retry, retry_opts}
      {:continue, effect} -> {:continue, effect}
      otherwise -> {:error, {:unsupported_compensation_result_form, otherwise}}
    end
  end

  @doc false
  @spec get_full_name(Legend.stage, Legend.full_name) :: Legend.full_name
  defp get_full_name(stage, parent_full_name) when is_list(stage) do
    parent_full_name ++ Keyword.get(stage, :name)
  end
  defp get_full_name(stage, parent_full_name) when is_atom(stage) do
    parent_full_name ++ stage.name()
  end

  @doc false
  @spec get_transaction(Legend.stage) :: (Legend.effects -> transaction_result)
  defp get_transaction(stage) when is_list(stage) do
    Keyword.get(stage, :transaction)
  end
  defp get_transaction(stage) when is_atom(stage) do
    &stage.transaction/1
  end

  @doc false
  @spec get_compensation(Legend.stage) :: (reason :: term, Legend.effect, Legend.effects -> compensation_result)
  defp get_compensation(stage) when is_list(stage) do
    Keyword.get(stage, :compensation)
  end
  defp get_compensation(stage) when is_atom(stage) do
    &stage.compensation/3
  end

  @doc false
  @spec get_retry_handler(Legend.stage) :: module
  defp get_retry_handler(stage) when is_list(stage) do
    Keyword.get(stage, :on_retry, Legend.RetryWithExpoentialBackoff)
  end
  defp get_retry_handler(stage) when is_atom(stage) do
    stage.on_retry
  end
end
