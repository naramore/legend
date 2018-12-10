defmodule Legend.Generators do
  @moduledoc """
  Custom PropCheck generators for use in testing Legend.
  """

  use PropCheck

  @typedoc """
  Simple wrapper for PropCheck (and indirectly, PropEr) generators.
  """
  @type generator :: PropCheck.BasicTypes.type

  @doc """
  Naive `Enum.take/2` implemented for PropCheck / :proper
  generators (b/c implementing structs / records for PropEr's
  types seemed like a non-trivial undertaking).
  """
  @spec take(generator, pos_integer) :: [term]
  def take(generator, num \\ 10) do
    Enum.map(1..num, fn _ ->
      generator |> produce() |> elem(1)
    end)
  end
end
