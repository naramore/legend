defmodule Legend.Hook do
  @moduledoc """
  """

  alias Legend.{Event, Stage, Utils}

  @typedoc """
  """
  @type hook_state :: term

  @typedoc """
  """
  @type hook_result ::
    :ok |
    {:ok, hook_state} |
    {:error, reason :: term} |
    {:error, reason :: term, hook_state}

  @typedoc """
  """
  @type hook_context :: {Event.t, Hook.hook_result} | Event.t

  @typedoc """
  """
  @type accumulator :: %{
    hooks_left: [Hook.t],
    effects_so_far: Legend.effects,
  }

  @typedoc """
  """
  @type t :: %__MODULE__{
    name: Legend.name,
    filter: (Event.t, hook_state -> boolean) | nil,
    fun: (Event.t, hook_state -> hook_result)
  }

  defstruct [
    name: nil,
    filter: nil,
    fun: nil
  ]

  @doc """
  """
  @spec merge_hooks(Legend.stage, Stage.execute_opts) :: [t]
  def merge_hooks(stage, opts \\ [])
  def merge_hooks(stage, opts) when is_list(stage) do
    stage
    |> Keyword.get(:hooks, [])
    |> reduce_hooks(opts)
  end
  def merge_hooks(stage, opts) when is_atom(stage) do
    stage
    |> apply(:list_hooks, [])
    |> reduce_hooks(opts)
  end

  @doc false
  @spec reduce_hooks([t], Stage.execute_opts) :: [t]
  defp reduce_hooks(stage_hooks, opts) do
    opts
    |> Keyword.get(:hooks, [])
    |> Enum.reduce(stage_hooks, fn
      {h, hopts}, hs -> add_hook(h, hs, hopts)
      h, hs -> add_hook(h, hs)
    end)
  end

  @doc false
  @spec add_hook(t, [t], Stage.hook_opts) :: [t]
  defp add_hook(new_hook, hooks, opts \\ []) do
    with %__MODULE__{} <- Enum.find(hooks, fn h -> h.name == new_hook.name end),
         {false, _} <- Keyword.pop(opts, :override?, false) do
      hooks
    else
      _ -> [new_hook | hooks]
    end
  end

  @doc """
  """
  @spec step(Event.t, accumulator, Stage.step_options) :: {Event.t | nil, accumulator}
  def step(event, state, opts \\ [])
  def step(event, %{hooks_left: []} = s, opts) do
    case maybe_update_hook_state(event.context, s) do
      {:ok, new_state} ->
        {nil, new_state}
      {:error, _reason, new_state} ->
        handle_hook_error(event.context, new_state, opts)
    end
  end
  def step(event, %{hooks_left: [h|hs]} = s, opts) do
    case maybe_update_hook_state(event.context, s) do
      {:ok, new_state} ->
        {maybe_execute_hook(h, event, new_state, opts), %{new_state | hooks_left: hs}}
      {:error, _reason, new_state} ->
        handle_hook_error(event.context, new_state, opts)
    end
  end
  def step(_event, state, _opts), do: {nil, state}

  @doc false
  @spec maybe_update_hook_state(hook_context, accumulator) ::
    {:ok, accumulator} |
    {:error, reason :: term, accumulator}
  defp maybe_update_hook_state({_, hook_result}, state) do
    update_hook_state(hook_result, state)
  end
  defp maybe_update_hook_state(_, state), do: {:ok, state}

  @doc false
  @spec update_hook_state(hook_result, accumulator) ::
    {:ok, accumulator} |
    {:error, reason :: term, accumulator}
  defp update_hook_state(:ok, state), do: {:ok, state}
  defp update_hook_state({:ok, hook_state}, state) do
    {:ok, put_in(state, [:effects_so_far, :__hookstate__], hook_state)}
  end
  defp update_hook_state({:error, reason}, state),
    do: {:error, reason, state}
  defp update_hook_state({:error, reason, hook_state}, state) do
    {:error, reason, put_in(state, [:effects_so_far, :__hookstate__], hook_state)}
  end

  @doc false
  @spec handle_hook_error(hook_context, accumulator, Stage.step_options) ::
    {Event.t | nil, accumulator}
  defp handle_hook_error({event, {:error, reason, _}}, state, opts),
    do: handle_hook_error({event, {:error, reason}}, state, opts)
  defp handle_hook_error({%Event{name: [_, _, :compensation]}, _}, %{hooks_left: []} = state, _opts) do
    {nil, state}
  end
  defp handle_hook_error({%Event{name: [_, _, :compensation]} = e, _}, %{hooks_left: [h|hs]} = s, opts) do
    {maybe_execute_hook(h, e, s, opts), %{s | hooks_left: hs}}
  end
  defp handle_hook_error({event, {:error, reason}}, state, _opts) do
    %{effects_so_far: effects_so_far} = state
    # TODO: this needs to work for all stages, not just the leaves...
    #       probably need to change the spec to return an `error` response
    #       then have the calling code figure out what event that is...
    {
      Event.update(event, event: [:starting, :compensation],
                          context: {reason,
                                    Event.get_effect(event, effects_so_far),
                                    effects_so_far}),
      state
    }
  end

  @doc """
  """
  @spec maybe_execute_hook(t, Event.t, accumulator, Stage.step_options) :: Event.t
  def maybe_execute_hook(hook, event, state, opts) do
    hook_state = get_in(state, [:effects_so_far, :__hookstate__])
    case Utils.execute(hook.filter, [event, hook_state]) do
      {:ok, true} ->
        result = execute_hook(hook, [event, hook_state], opts)
        Event.update(event, name: [:completed, :hook, hook.name],
                            context: {event, result})
      _ ->
        Event.update(event, name: [:skipped, :hook, hook.name],
                            context: event)
    end
  end

  @doc """
  """
  @spec execute_hook(t, Event.t, hook_state, Stage.step_options) :: hook_result
  def execute_hook(hook, event, state, opts \\ []) do
    if Keyword.get(opts, :dry_run?, false) do
      Keyword.get(opts, :dry_run_result, :ok)
    else
      timeout = Keyword.get(opts, :timeout, :infinity)
      case Utils.execute(hook.fun, [event, state], timeout) do
        :ok -> :ok
        {:ok, hook_state} -> {:ok, hook_state}
        {:error, reason} -> {:error, reason}
        {:error, reason, hook_state} -> {:error, reason, hook_state}
        otherwise -> {:error, {:unsupported_hook_result_form, otherwise}}
      end
    end
  end
end
