defmodule Bex.Test.Process do
  @moduledoc false

  # import Process, only: [send_after: 4]

  alias Elixir.Process, as: P1
  alias Process, as: P2
  alias Task.Supervisor

  def schedule_without_as do
    Supervisor.start_link([])
  end

  def schedule(interval) do
    Process.send_after(self(), :schedule, interval, [])
  end

  def schedule_with_fq_alias do
    P1.send_after(self(), :schedule, 1_000, [])
  end

  def schedule_with_alias do
    P2.send_after(self(), :schedule, 1_000, [])
  end
end
