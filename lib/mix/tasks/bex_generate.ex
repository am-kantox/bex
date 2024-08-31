defmodule Mix.Tasks.Bex.Generate do
  @shortdoc "Generates the behaviour and the default implementation scaffold for the given module/function"
  @moduledoc """
  Mix task to generate the `Bex` wrapping behaviour scaffold.

  By running `mix bex.generate --module ModuleToConvert` or
  `mix bex.generate --function Module.function_to_convert/arity`
  two modules are to be generated:

  - behaviour module for the functions(s)
  - default implementation module, wrapping the original function(s)

  ### Allowed arguments

  - **`--module: :string`** _or_ **`--function: :string`** __[mandatory]__ the name of the module
    or the function to convert to behaviour implementation
  - **`--dir: :string`** __[optional, default: `lib/bex`]__ the target directory for generated
    modules
  - **`--patch`** __[optional, default: `true`] if `false`, no attempt to patch found occurences
    of calls to the behavioured function(s) would be made

  ### Example

  ```sh
  mix bex.generate --function Process.send_after/4 --no-patch
  ```
  """

  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity

  use Mix.Task

  @bex_default_path "lib/bex"

  @impl Mix.Task
  @doc false
  def run(args) do
    Mix.Task.run("compile")

    {opts, _pass_thru, []} =
      OptionParser.parse(args,
        strict: [
          module: :string,
          function: [:string, :keep],
          patch: :boolean,
          dir: :string
        ]
      )

    {mod, funs} =
      [:module, :function]
      |> Enum.map(&Keyword.fetch(opts, &1))
      |> case do
        [:error, :error] ->
          report_error(:required)

        [{:ok, module}, {:ok, function}] ->
          report_error({:both, module, function})

        [{:ok, module}, :error] ->
          with mod <- Module.concat([module]),
               {:module, ^mod} <- Code.ensure_compiled(mod),
               [_ | _] = funs <- mod.__info__(:functions),
               do: {mod, funs},
               else: (error -> report_error({:module, module, error}))

        [:error, {:ok, function}] ->
          with [mod_fun, arity] <- String.split(function, "/"),
               {mod, [fun]} <- mod_fun |> String.split(".") |> Enum.split(-1),
               mod <- Module.concat(mod),
               # don’t raise with `String.to_existing_atom/1`, it’s safe
               fun <- String.to_atom(fun),
               {arity, ""} when is_integer(arity) and arity >= 0 <- Integer.parse(arity),
               {:module, ^mod} <- Code.ensure_compiled(mod),
               true <- function_exported?(mod, fun, arity),
               do: {mod, [{fun, arity}]},
               else: (error -> report_error({:function, function, error}))
      end

    with [{_fun, _arity} | _] <- funs do
      {inner_dir, [file_base]} = mod |> Macro.underscore() |> Path.split() |> Enum.split(-1)
      target_dir = Path.join(Keyword.get(opts, :dir, @bex_default_path), inner_dir)
      File.mkdir_p!(target_dir)
      target_file = Path.join([target_dir, file_base <> ".ex"])

      behaviour_module = Module.concat([Bex.Behaviours, mod])
      behaviour_impl_module = Module.concat([Bex.Behaviours.Impls, mod])

      locations =
        Mix.Project.config()
        |> Keyword.get(:elixirc_paths, ["lib"])
        |> Enum.map(&Path.wildcard(&1 <> "/**/*.ex"))
        |> Enum.reduce(&Kernel.++/2)
        |> Kernel.--([target_file])
        |> Enum.flat_map(&locations_to_report(&1, mod, funs))

      Mix.Generator.copy_template(
        Path.expand("bex_template.eex", __DIR__),
        target_file,
        behaviour_module: behaviour_module,
        behaviour_impl_module: behaviour_impl_module,
        module: mod,
        funs: funs
      )

      File.write!(target_file, Code.format_file!(target_file))

      Mix.shell().info([
        [:bright, :blue, "✓ #{inspect(mod)}", :reset],
        " has been created in ",
        [:blue, "#{target_file}", :reset]
      ])

      for {file, file_ast, locations} <- locations do
        for {meta, ast, new_ast} <- locations do
          line = Keyword.get(meta, :line, "??")

          Mix.shell().info([
            "✓ Suggested change: ",
            [:bright, :blue, file, :reset],
            [:blue, ":#{line}", :reset],
            "\n",
            [:red, Bex.io_diff(ast, :delete), :reset],
            "\n",
            [:green, Bex.io_diff(new_ast, :add), :reset]
          ])
        end

        if Keyword.get(opts, :patch, true) and
             Mix.shell().yes?("Apply changes to ‹" <> file <> "›?") do
          with {:error, error} <- File.cp(file, file <> ".bex") do
            Mix.shell().error([
              [:bright, :red, "✗ Error ", :reset],
              [:bright, :yellow, inspect(error), :reset],
              [:bright, :red, " trying to create a backup copy ", :reset],
              [:bright, :blue, file <> ".bex", :reset]
            ])
          end

          case File.write(file, Sourceror.to_string(file_ast)) do
            :ok ->
              Mix.shell().info([
                "✓ File ",
                [:bright, :blue, file, :reset],
                " amended successfully"
              ])

            {:error, error} ->
              _ = File.rm(file <> ".bex")

              Mix.shell().error([
                [:bright, :red, "✗ Error ", :reset],
                [:bright, :yellow, inspect(error), :reset],
                [:bright, :red, " amending ", :reset],
                [:bright, :blue, file, :reset]
              ])
          end
        end
      end
    end
  end

  defp locations_to_report(file, mod, funs) when is_binary(file) do
    file
    |> File.read!()
    |> Sourceror.parse_string()
    |> case do
      {:ok, term} -> locations_to_report(term, file, mod, funs)
      {:error, error} -> report_error({:sourceror, file, error})
    end
  end

  defp locations_to_report(term, file, mod, funs) do
    alias = mod |> Module.split() |> Enum.map(&String.to_atom/1)
    bex_alias = [:Bex, :Behaviours | alias]

    {ast, acc} =
      Macro.postwalk(term, %{calls: [], aliases: %{alias => alias}}, fn
        {:alias, _meta, [{:__aliases__, _mods_meta, mods}]} = ast, acc ->
          {ast, put_in(acc, [:aliases, [List.last(mods)]], mods)}

        {:alias, _meta,
         [
           {:__aliases__, _mods_meta, mods},
           [{{:__block__, _block_meta, [:as]}, {:__aliases__, _aliases_meta, aliases}}]
         ]} = ast,
        acc ->
          {ast, put_in(acc, [:aliases, aliases], mods)}

        {{:., meta_call,
          [
            {:__aliases__, meta_aliases, alias},
            fun
          ]}, meta, args} = ast,
        %{aliases: aliases} = acc
        when is_map_key(aliases, alias) ->
          if {fun, length(args)} in funs do
            new_ast =
              {{:., meta_call,
                [
                  {:__aliases__, meta_aliases, bex_alias},
                  fun
                ]}, meta, args ++ [{:__ENV__, [], nil}]}

            {new_ast, %{acc | calls: [{meta_call, ast, new_ast} | acc.calls]}}
          else
            {ast, acc}
          end

        ast, acc ->
          {ast, acc}
      end)

    case acc.calls do
      [] -> []
      list -> [{file, ast, list}]
    end
  end

  defp report_error(:required) do
    Mix.shell().error([
      [:bright, :red, "✗ Either ", :reset],
      [:bright, :yellow, "--module", :reset],
      [:bright, :red, " or ", :reset],
      [:bright, :yellow, "--function", :reset],
      [:bright, :red, " argument is required.\n→ Exiting.", :reset]
    ])

    {nil, []}
  end

  defp report_error({:both, module, function}) do
    Mix.shell().error([
      [:bright, :red, "✗ Either ", :reset],
      [:bright, :yellow, "--module", :reset],
      [:bright, :red, " or ", :reset],
      [:bright, :yellow, "--function", :reset],
      [:bright, :red, " argument is required. Both given:\n  ", :reset],
      [:blue, "--module #{module} --function #{function}", :reset],
      [:bright, :red, "\n→ Exiting.", :reset]
    ])

    {module, []}
  end

  defp report_error({:module, module, {:error, error}}) do
    Mix.shell().error([
      [:bright, :red, "✗ The given module ", :reset],
      [:bright, :yellow, module, :reset],
      [:bright, :red, " is not accessible by compiler.\n  Error: ", :reset],
      [:bright, :yellow, inspect(error), :reset],
      [:bright, :red, "\n→ Exiting.", :reset]
    ])

    {module, []}
  end

  defp report_error({:module, module, []}) do
    Mix.shell().error([
      [:bright, :red, "✗ The given module ", :reset],
      [:bright, :yellow, module, :reset],
      [:bright, :red, " does not export any function.\n→ Exiting: ", :reset]
    ])

    {module, []}
  end

  defp report_error({:function, function, false}) do
    Mix.shell().error([
      [:bright, :red, "✗ The given function ", :reset],
      [:bright, :yellow, function, :reset],
      [:bright, :red, " is not exported or does not exist.\n→ Exiting.", :reset]
    ])

    {nil, []}
  end

  defp report_error({:function, function, _error}) do
    Mix.shell().error([
      [:bright, :red, "✗ The given function ", :reset],
      [:bright, :yellow, function, :reset],
      [:bright, :red, " is malformed.\n  Expected format: ", :reset],
      [:blue, "Module.function/arity", :reset],
      [:bright, :red, " e.g. ", :reset],
      [:blue, "Process.send_after/4", :reset],
      [:bright, :red, "\n→ Exiting.", :reset]
    ])

    {nil, []}
  end

  defp report_error({:sourceror, file, error}) do
    Mix.shell().error([
      [:bright, :red, "✗ Failed to suggest changes to file ", :reset],
      [:bright, :yellow, file, :reset],
      [:bright, :red, ". Error reported by sourceror:\n", :reset],
      [:blue, inspect(error), :reset],
      [:bright, :red, "\n→ Skipping.", :reset]
    ])

    {nil, []}
  end
end
