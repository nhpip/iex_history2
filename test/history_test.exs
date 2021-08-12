defmodule HistoryTest do
  use ExUnit.Case
  doctest History

  test "greets the world" do
    assert History.hello() == :world
  end
end
