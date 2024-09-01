# Bex

**The set of mix tasks to help dealing with behaviours and mocks**

## Objective

The goal of this library is to make planting better testing into a source code
as smoothly and fluently as possible. It’s barely needed for experienced developers,
but I always find myself struggling to recall all the places in the source code
I have to amend to convert a bare call into a behaviour-baked implementation.

The main task `Mix.Tasks.Bex.Generate` would do the following things:

- generate behaviour code for the function(s) given as an argument
- generate the default implementation for it, wrapping the call to the original code
  and [optionally] adding `:telemetry` events in the recommended `telemetry.span/3`
  flavored manner
- find all the occurrences of the behaviourized call(s) in the source code and patch
  them in-place (unless `--no-patch` flag is given)
- generate test(s) for the aforementioned functions, with proper `Mox` allowances
  (unless `--no-test` flag is given)
- prompt to amend `config/config.exs` file to use correct implementations in different
  environments

## Use-case

Consider the necessity to test the function that calls `Process.send_after/4` function
in your code. Assuming we trust that `Process.send_after/4` itself works, we’d like to
mock it and validate the proper call with proper arguments happened.

For that we might run `Mix.Tasks.Bex.Generate` task, review generated files, and voilà.
The next `mix test`, or `mix test test/bex` would execute the tests for the newly created
behaviour using `Mox`.
 
## Usage

```elixir
mix bex.generate --function Process.send_after/4
```

The above will generate the behaviour module `Bex.Behaviours.Process` and its default
implementation which should be called instead of a direct call to the original function.

Also `Mox` scaffold and `telemetry` call will be generated.

## Installation

```elixir
def deps do
  [
    {:bex, "~> 0.2"}
  ]
end
```

## [Documentation](https://hexdocs.pm/bex)

