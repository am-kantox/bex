# Bex

**The set of mix tasks to help dealing with behaviours and mocks**

## Installation

```elixir
def deps do
  [
    {:bex, "~> 0.1", runtime: false}
  ]
end
```

## Usage

```elixir
mix bex.generate --function Process.send_after/4
```

The above will generate the behaviour module `Bex.Behaviours.Process` and its default
implementation which should be called instead of a direct call to the original function.

Also `Mox` scaffold and `telemetry` call will be generated.

## [Documentation](https://hexdocs.pm/bex)

