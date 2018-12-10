defmodule Legend.Retry do
  @moduledoc """
  """

  # TODO: retries: isolated (i.e. named by stage.full_name) or shared (i.e. named by retry module)
  #       retry state updating may be updated via `Legend.Retry.update/?` from root to leaf
  # TODO: shared retry state across async & mapper children? maybe an agent?
  #       and as a followup -> hook_state across the same?

  @typedoc """
  """
  @type retry_opts :: Keyword.t

  @typedoc """
  """
  @type retry_state :: term

  @typedoc """
  """
  @type wait :: {non_neg_integer, System.time_unit}

  @doc """
  """
  @callback init() :: {:ok, retry_state}

  @doc """
  """
  @callback handle_retry(retry_state, Keyword.t) ::
    {:retry, wait, new_retry_state} |
    {:noretry, new_retry_state} when new_retry_state: retry_state

  @doc """
  """
  @callback update() :: term

  defmacro __using__(opts) do
    shared_state? = Keyword.get(opts, :shared_state?, true)
    quote do
      @behaviour Legend.Retry
      @shared_state? unquote(shared_state?)
      alias Legend.Retry

      @spec shared_state?() :: boolean
      def shared_state?(), do: @shared_state?

      @impl Retry
      def update() do
      end
    end
  end

  # handle_compensation_retry/4
  # step/4
  # maybe_execute_retry/4
  # execute_retry/4

  # execute/3 | compensate/4 -> retry_init -> w/e they are now...
  # 1. retry requested from compensation -> [:starting, :retry_handler]
  # 2. hooks...
  # 3. run handler -> [:completed, :retry_handler]
  # 4. hooks...
  # 5. Enum.reduce/3 over opts[:retry_updates] -> [:starting, :retry_update]
  # 6. hooks..
  # 7.                          execute update -> [:completed, :retry_update]
  # 8. hooks...
  # 9. done -> return to calling env with retry success/failure

  # [:starting, :retry_init], nil
  # [:completed, :retry_init], retry_init_result
  # [:starting, :retry_handler], retry_state, retry_opts
  # [:completed, :retry_handler], retry_handler_result
  # [:starting, :retry_update], ???
  # [:completed, :retry_update], retry_update_result

  #@doc """
  #"""
  #@spec step(Legend.stage, Event.t, accumulator, Stage.step_options) :: Legend.stage_result | {Event.t, accumulator}
  #def step(_stage, %Event{name: [:starting, :sync, :retry]} = e, %{hooks_left: []} = s, _opts) do
  #  # execute retry handler
  #  # next event -> [:completed, :sync, :retry]
  #  {e, s}
  #end
  #def step(_stage, %Event{name: [:completed, :sync, :retry]} = e, %{hooks_left: []} = s, _opts) do
  #  # if retry -> update state; wait; [:starting, :sync, :transaction]
  #  # if noretry -> :done, {:error, reason}
  #  {e, s}
  #end

  @doc """
  """
  @spec get_retry_state(module, Legend.full_name, Legend.effects) :: retry_state
  def get_retry_state(mod, name, effects_so_far) do
    if mod.shared_state?() do
      get_in(effects_so_far, [:__retry__, mod])
    else
      name
    end
  end
end

defmodule Legend.RetryWithExpoentialBackoff do
  use Legend.Retry
  require Logger

  @typedoc """
  """
  @type retry_opt :: {:retry_limit, pos_integer() | nil} |
                     {:base_backoff, pos_integer() | nil} |
                     {:min_backoff, non_neg_integer() | nil} |
                     {:max_backoff, pos_integer()} |
                     {:enable_jitter, boolean()}

  @typedoc """
  """
  @type retry_opts :: [retry_opt]

  @typedoc """
  """
  @type parsed_retry :: {pos_integer | nil, pos_integer | nil, pos_integer, boolean}

  @impl Legend.Retry
  def init do
    {:ok, 1}
  end

  @impl Legend.Retry
  def handle_retry(count, opts) do
    parsed_opts = parse_opts(opts)
    case retry(count, parsed_opts) do
      {nil, state} -> {:noretry, state}
      {wait, state} -> {:retry, wait, state}
    end
  end

  @spec retry(Retry.retry_state, parsed_retry) :: {pos_integer | nil, Retry.retry_state}
  defp retry(count, {nil, _base, _max, _jitter?}),
    do: {nil, count + 1}
  defp retry(count, {limit, base, max, jitter?})
    when limit > count do
      backoff = get_backoff(count, base, max, jitter?)
      {backoff, count + 1}
  end
  defp retry(count, _parsed_opts),
    do: {nil, count + 1}

  @spec parse_opts(retry_opts) :: parsed_retry
  defp parse_opts(opts) do
    limit = Keyword.get(opts, :retry_limit)
    base_backoff = Keyword.get(opts, :base_backoff)
    max_backoff = Keyword.get(opts, :max_backoff, 5_000)
    jitter_enabled? = Keyword.get(opts, :enable_jitter, true)

    {limit, base_backoff, max_backoff, jitter_enabled?}
  end

  @spec get_backoff(pos_integer, pos_integer | nil, pos_integer, boolean) :: non_neg_integer
  def get_backoff(_count, nil, _max_backoff, _jitter_enabled?), do: 0
  def get_backoff(count, base_backoff, max_backoff, true)
    when is_integer(base_backoff) and base_backoff >= 1 and
         is_integer(max_backoff) and max_backoff >= 1,
      do: random(calculate_backoff(count, base_backoff, max_backoff))
  def get_backoff(count, base_backoff, max_backoff, _jitter_enabled?)
    when is_integer(base_backoff) and base_backoff >= 1 and
         is_integer(max_backoff) and max_backoff >= 1,
      do: calculate_backoff(count, base_backoff, max_backoff)
  def get_backoff(_count, base_backoff, max_backoff, _jitter_enabled?) do
    _ = Logger.warn(fn ->
      "Ignoring retry backoff options, expected base_backoff and max_backoff to be integer and >= 1, got: " <>
        "base_backoff: #{inspect(base_backoff)}, max_backoff: #{inspect(max_backoff)}"
    end)
    0
  end

  @spec calculate_backoff(pos_integer, pos_integer, pos_integer) :: pos_integer
  defp calculate_backoff(count, base_backoff, max_backoff),
    do: min(max_backoff, trunc(:math.pow(base_backoff * 2, count)))

  @spec random(integer) :: integer
  defp random(n) when is_integer(n) and n > 0, do: :rand.uniform(n) - 1
  defp random(n) when is_integer(n), do: 0
end
