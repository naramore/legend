defmodule Legend.BaseStage do
  @moduledoc """
  """

  alias Legend.{Event, Hook}

  @typedoc """
  """
  @type hook_opts :: [
    {:override, boolean} |
    {:cascade_depth, non_neg_integer | :infinity}
  ]

  @typedoc """
  """
  @type execute_opts :: [
    {:dry_run?, boolean} |
    {:dry_run_result, term} |
    {:timeout, timeout} |
    {:hooks, [Hook.t | {Hook.t, hook_opts}]} |
    {:retry_updates, [module]} |
    {:subscribers, [Process.dest]} |
    {:parent_id, Legend.id} |
    {:parent_full_name, Legend.full_name}
  ]

  @doc """
  """
  @callback step(Legend.stage, Event.t, accumulator, execute_opts) ::
    Legend.stage_result | {Event.t, accumulator}
    when accumulator: term

  @doc """
  """
  @callback execute(Legend.stage, effects_so_far :: Legend.effects, execute_opts) ::
    {Event.t, accumulator :: term}

  @doc """
  """
  @callback compensate(Legend.stage, {:error | :abort, reason :: term}, effects_so_far :: Legend.effects, execute_opts) ::
    {Event.t, accumulator :: term}

  # TODO: add @callback create(Keyword.t) :: {:ok, Keyword.t} | {:error, reason :: term}

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Legend.BaseStage
      alias Legend.BaseStage
    end
  end

  # TODO: add sematics to run/4 for starting in the middle, given {Event.t, accumulator} | [Event.t]
  # TODO: add sematics to run/4 for stopping in the middle, given (Event.t, accumulator -> boolean)

  @doc """
  """
  @spec run(Legend.stage, Legend.stage_result, effects_so_far :: Legend.effects, execute_opts) :: Legend.stage_result
  def run(_stage, _result, _effects_so_far, _opts \\ []) do
    {:error, :not_implemented}
  end
end
