defmodule BexTest do
  use ExUnit.Case
  doctest Bex

  test "greets the world" do
    assert Bex.hello() == :world
  end
end
