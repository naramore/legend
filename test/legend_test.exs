defmodule LegendTest do
  use ExUnit.Case
  doctest Legend
end

# TODO: PropCheck generators for Legend.{Stage, Hook, ErrorHandler, Retry}
#       in test/support/generators.ex
# TODO: create functions that will do fake, repeatable, work w/o :time.sleep/1
# TODO: benchfella micro-benchmarking of piped/with-clause functions vs Legend
#       then similar tests w/ retrying and/or hooks

defmodule Legend.StageTest do
  use ExUnit.Case
  doctest Legend.Stage
end

defmodule Legend.HookTest do
  use ExUnit.Case
  doctest Legend.Hook
end

defmodule Legend.ErrorHandlerTest do
  use ExUnit.Case
  doctest Legend.ErrorHandler
end

defmodule Legend.RetryTest do
  use ExUnit.Case
  doctest Legend.Retry
end
