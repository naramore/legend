defmodule Legend.Event do
  @moduledoc """
  All: id, [{Legend.full_name, non_neg_integer, {Node.t, DateTime.t}}, ...], Legend.full_name, event, context, Logger.metadata()
  Legend.Hook:
    [:completed, :hook, name], event, hook_result
    [:skipped, :hook, :name], event
  Legend.Stage.Sync:
    [:starting, :sync, :transaction], effects_so_far
    [:completed, :sync, :transaction], transaction_result
    [:starting, :sync, :compensation], error_to_compensate, effect_to_compensate, effects_so_far
    [:completed, :sync, :compensation], compensation_result
    [:starting, :sync, :retry], retry_state, retry_opts
    [:completed, :sync, :retry], retry_result
    [:starting, :sync, :compensation, :error_handler, handler_name], error
    [:completed, :sync, :compensation, :error_handler, handler_name], compensation_error_handler_result
  Legend.Stage.Async:
    [:starting, :async, :transaction], effects_so_far
    [:completed, :async, :transaction] %{name => transaction_result}
    [:starting, :async, :compensation], errors_to_compensate, effects_to_compensate, effects_so_far
    [:completed, :async, :compensation] %{name => compensation_result}
    [:dependency_waiting, :async, :transactions], %{name => waiting_deps}
    [:starting, :async, :transactions] %{name => async_opts}
    [:started, :async, :transactions] %{name => Task.t}
    [:completed, :async, :transactions] %{name => task_result}
    [:dependency_waiting, :async, :compensations], %{name => waiting_deps}
    [:starting, :async, :compensations] %{name => async_opts}
    [:started, :async, :compensations] %{name => Task.t}
    [:completed, :async, :compensations] %{name => task_result}
  Legend.Stage.Mapper:
    [:starting, :mapper, :decomposer], effects_so_far, async_opts
    [:completed, :mapper, :decomposer], decomposer_result
    [:starting, :mapper, :stages], [{name, decomposer_effects, async_opts}]
    [:completed, :mapper, :stages], %{name => stage_result}
    [:starting, :mapper, :recomposer], mapper_effects
    [:completed, :mapper, :recomposer], recomposer_result
  Legend.Stage.Feedback:
    [:starting, :feedback, :init], effects_so_far, feedback_opts
    [:completed, :feedback, :init], feedback_init_result
    [:starting, :feedback, :transaction, :check], effects_so_far, feedback_state
    [:completed, :feedback, :transaction, :check], :continue | :complete, feedback_state
    [:starting, :feedback, :compensation, :check], effects_so_far, feedback_state
    [:completed, :feedback, :compensation, :check], :continue | :complete, feedback_state
    [:starting, :feedback, :transaction], effects_so_far
    [:completed, :feedback, :transaction], transaction_result
    [:starting, :feedback, :compensation], error_to_compensate, effect_to_compensate, effects_so_far
    [:completed, :feedback, :compensation], compensation_result
  Legend:
    [:starting, :legend], initial_effects, legend_opts
    [:starting, :legend, :transaction, name], effects_so_far
    [:completed, :legend, :transaction, name], transaction_result
    [:starting, :legend, :compensation, name], error_to_compensate, effect_to_compensate, effects_so_far
    [:completed, :legend, :compensation, name], compensation_result
    [:complete, :legend], legend_result
  """

  alias Legend.Utils

  @typedoc """
  """
  @type t :: %__MODULE__{
    id: Legend.id,
    #timestamp: [{Legend.full_name, non_neg_integer, {Node.t, DateTime.t}}, ...],
    timestamp: {Node.t, DateTime.t},
    stage_name: Legend.full_name,
    name: [atom],
    context: term,
    metadata: Keyword.t
  }

  defstruct [
    id: nil,
    timestamp: nil,
    stage_name: nil,
    name: nil,
    context: nil,
    metadata: nil
  ]

  @spec defaults() :: Keyword.t
  def defaults() do
    [
      timestamp: {Node.self(), DateTime.utc_now()},
      metadata: Utils.get_local_metadata()
    ]
  end

  @spec create(Keyword.t) :: t
  def create(opts \\ []) do
    defaults()
    |> Keyword.merge(opts)
    |> (&struct(__MODULE__, &1)).()
  end

  @spec update(t, Keyword.t) :: t
  def update(event, opts \\ []) do
    defaults()
    |> Keyword.merge(opts)
    |> Enum.reduce(event, fn {k, v}, e ->
      if Map.has_key?(e, k) do
        Map.put(e, k, v)
      else
        e
      end
    end)
  end

  @spec get_effect(t, Legend.effects) :: Legend.effect | nil
  def get_effect(event, effects) do
    get_in(effects, tl(event.stage_name))
  end
end
