defmodule Legend.MapperStage do
  @moduledoc """
  """

  use Legend.BaseStage
  alias Legend.Event

  @impl Legend.BaseStage
  def execute(_stage, _effects_so_far, _opts \\ []) do
    {%Event{}, nil}
  end

  @impl Legend.BaseStage
  def compensate(_stage, {status, _reason}, _effects_so_far, _opts \\ [])
    when status in [:error, :abort] do
      {%Event{}, nil}
  end

  @impl Legend.BaseStage
  def step(stage, event, state, opts \\ [])
  def step(_stage, %Event{} = _event, _state, _opts) do
    {:error, :notimplemented}
  end
end
