defmodule Bex do
  @moduledoc """
  `Bex` internals and helpers.
  """

  @doc """
  Retrieves `mfa` tuple from `Macro.Env`

  ## Examples

      iex> Bex.mfa(__ENV__)
      {BexTest, :"doctest Bex.mfa/1 (1)", 1}
  """
  def mfa(%Macro.Env{module: mod, function: {fun, arity}}),
    do: {mod, fun, arity}

  @doc """
  Builds a `telemetry` event base name from `Macro.Env`

  ## Examples

      iex> Bex.telemetry_event_base(__ENV__)
      [:bextest, :"doctest Bex.telemetry_event_base/1 (2)_1"]
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

  ## Examples

      iex> measurements = Bex.telemetry_measurements_base(%{foo: :bar})
      ...> match?(%{monotonic_time: _, system_time: _, foo: :bar}, measurements)
      true
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

  @doc """
  IO formatter for diffs

  ### Examples

      iex> Bex.io_diff("foo", :delete)
      "- foo"
      iex> Bex.io_diff("foo", :add)
      "+ foo"
      iex> Bex.io_diff("foo", "→")
      "→ foo"
  """
  @spec io_diff(ast :: Macro.t() | String.t(), leader :: :delete | :add | String.t()) ::
          String.t()
  def io_diff(ast, :delete), do: io_diff(ast, "-")
  def io_diff(ast, :add), do: io_diff(ast, "+")

  def io_diff(ast, leader) when is_binary(ast) do
    ast
    |> String.split("\n")
    |> Enum.map_join("\n", &(leader <> " " <> &1))
  end

  def io_diff(ast, leader) do
    ast
    |> Sourceror.to_string()
    |> io_diff(leader)
  end

  @doc """
  Fetches the spec from BEAM file generated for a module

  ## Example

      iex> Bex.fetch_spec Process, :send_after, 4
      {:ok, "send_after(pid() | atom(), term(), non_neg_integer(), [option]) :: reference() when option: var"}
  """
  @spec fetch_spec(module(), atom(), arity()) :: {:ok, String.t()} | {:error, any()}
  def fetch_spec(mod, fun, arity) do
    with {:ok, core} <- mod |> :code.which() |> :dialyzer_utils.get_core_from_beam(),
         {:ok, rec_dict} <- :dialyzer_utils.get_record_and_type_info(core),
         {:ok, spec_info, %{}} <- :dialyzer_utils.get_spec_info(mod, core, rec_dict),
         {:ok, {{_file, _line}, {_tmp_contract, [_fun], type}, []}} <-
           fetch_spec_info(spec_info, {mod, fun, arity}),
         do: {:ok, type_to_string(fun, type)}
  end

  defp fetch_spec_info(spec_info, {mod, fun, arity}) do
    with :error <- Map.fetch(spec_info, {mod, fun, arity}), do: {:error, :no_mfa_info}
  end

  defp type_to_quoted(fun, type) do
    for {{:type, _, _, _} = type, _} <- type do
      Code.Typespec.spec_to_quoted(fun, type)
    end
  end

  defp type_to_string(fun, type) do
    fun
    |> type_to_quoted(type)
    |> Enum.map_join(" ", &Macro.to_string/1)
  end
end
