defmodule Legend.Digraph do
  @moduledoc """
  """
  # TODO: Legend.Digraph.Server & Legend.Digraph.Registry
  # TODO: create server(s) to translate async deps -> :digraph -> Legend.Digraph.t
  #       purpose -> control the creation of :digraph's so as to not overwhelm ETS
  #       basically: create :digraph, run analytics, turn into struct, delete it
  #                  be able to take the struct again to re-build if necessary
  #                  this way we can control the total # of :digraphs in the system at once
end

defmodule Legend.AsyncStage do
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
