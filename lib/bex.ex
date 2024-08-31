defmodule Bex do
  @moduledoc """
  `Bex` internals and helpers.
  """

  @doc """
  Retrieves `mfa` tuple from `Macro.Env`

  ## Examples

      iex> Bex.mfa()
      :world

  """
  def mfa(%Macro.Env{module: mod, function: {fun, arity}}),
    do: {mod, fun, arity}

  @doc """
  Builds a `telemetry` event base name from `Macro.Env`
  """
  @spec telemetry_event_base(Macro.Env.t() | mfa()) :: :telemetry.event_name()
  def telemetry_event_base(%Macro.Env{} = env),
    do: env |> mfa() |> telemetry_event_base()

  def telemetry_event_base({mod, fun, arity}) do
    mod
    |> Module.split()
    |> Enum.map(&(&1 |> String.downcase() |> String.to_atom()))
    |> Kernel.++([:"#{fun}_#{arity}"])
  end

  @doc """
  Standard `:telemetry.span/3`-like measurements
  """
  @spec telemetry_measurements_base(map() | keyword()) :: %{
          :system_time => integer(),
          :monotonic_time => integer(),
          optional(atom()) => any()
        }
  def telemetry_measurements_base(additional_measurements \\ %{})

  def telemetry_measurements_base(additional_measurements)
      when additional_measurements == %{} or additional_measurements == [],
      do: %{system_time: :erlang.system_time(), monotonic_time: :erlang.monotonic_time()}

  def telemetry_measurements_base(additional_measurements) when is_map(additional_measurements),
    do: [] |> telemetry_measurements_base() |> Map.merge(additional_measurements)

  def telemetry_measurements_base(additional_measurements) when is_list(additional_measurements),
    do: [] |> telemetry_measurements_base() |> Map.merge(Map.new(additional_measurements))
end
