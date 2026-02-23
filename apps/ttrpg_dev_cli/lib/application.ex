defmodule TtrpgDevCli.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # Burrito.Util.Args is only injected into the runtime inside a wrapped binary,
    # so we resolve it dynamically to avoid a compile-time undefined-function warning.
    args =
      if Code.ensure_loaded?(Burrito.Util.Args) do
        apply(Burrito.Util.Args, :argv, [])
      else
        []
      end

    children = [
      {Task,
       fn ->
         ExTTRPGDev.CLI.main(args)
         System.halt(0)
       end}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
