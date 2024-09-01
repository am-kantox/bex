defmodule Mix.Tasks.Bex.Config do
  @shortdoc "Amends `config/config.exs` with all the mocked by `bex` behaviours"

  @moduledoc """
  Collects the information about all bex-patched behaviours _and_ amends the config file

  ### Allowed arguments

  - **`--dir: :string`** _[optional, default: `lib/bex`]_ the directory where to look
    for generated modules
  - **`--patch`** _[optional, default: `true`]_ if `false`, no attempt to patch found occurences
    of calls to the behavioured function(s) would be made

  ### Example

  ```sh
  mix bex.config --no-patch
  ```
  """

  use Mix.Task

  @bex_default_path "lib/bex"
  @config_dir "config"
  @config_file Path.join(@config_dir, "config.exs")

  @impl Mix.Task
  @doc false
  def run(args) do
    {opts, _pass_thru, []} =
      OptionParser.parse(args,
        strict: [
          dir: :string,
          patch: :boolean
        ]
      )

    bex_modules =
      opts
      |> Keyword.get(:dir, @bex_default_path)
      |> Path.join("/**/*.ex")
      |> Path.wildcard()
      |> Enum.flat_map(&mocks_from_file/1)

    bex_mox_impls = Map.new(bex_modules, &{&1, Module.concat([:Bex, :Behaviours, &1, :Mox])})
    bex_impls = Map.new(bex_modules, &{&1, Module.concat([:Bex, :Behaviours, :Impls, &1])})

    bex_impls_ast =
      case bex_modules do
        [] ->
          []

        [_ | _] ->
          quote do
            config :bex,
                   :impls,
                   if(Mix.env() == :test,
                     do: unquote(Macro.escape(bex_mox_impls)),
                     else: unquote(Macro.escape(bex_impls))
                   )
          end
      end

    old_config_content =
      with true <- File.exists?(@config_file), do: File.read!(@config_file)

    config_content =
      if old_config_content do
        old_config_content
        |> Sourceror.parse_string!()
        |> Macro.postwalk(fn
          {:config, _meta_config,
           [
             {:__block__, _bex_meta, [:bex]},
             {:__block__, _impls_meta, [:impls]},
             _old_impls
           ]} ->
            bex_impls_ast

          ast ->
            ast
        end)
        |> Sourceror.to_string()
      else
        with true <- bex_impls_ast != [],
             do: Enum.join(["import Config", "", Sourceror.to_string(bex_impls_ast)], "\n")
      end

    if old_config_content != config_content do
      File.mkdir_p(@config_dir)
      File.write!(@config_file, config_content)

      Mix.shell().info([
        [:bright, :blue, "✓ #{@config_file}", :reset],
        " has been altered"
      ])
    else
      Mix.shell().info([
        [:blue, "✗ #{@config_file}", :reset],
        " has not been changed"
      ])
    end
  end

  defp mocks_from_file(file) when is_binary(file) do
    file
    |> File.read!()
    |> Sourceror.parse_string()
    |> case do
      {:ok, term} -> mocks_from_file(term)
      {:error, _error} -> []
    end
  end

  defp mocks_from_file(term) when is_tuple(term) do
    term
    |> Macro.prewalk([], fn
      {{:., _call_meta, [{:__aliases__, _mox_meta, [:Mox]}, :defmock]}, _meta,
       [
         [
           {{:__block__, _block_meta, [:for]},
            {:__aliases__, _aliases_meta, [:Bex, :Behaviours | aliases]}}
         ]
       ]} = ast,
      acc ->
        {ast, [Module.concat(aliases) | acc]}

      ast, acc ->
        {ast, acc}
    end)
    |> elem(1)
  end
end
