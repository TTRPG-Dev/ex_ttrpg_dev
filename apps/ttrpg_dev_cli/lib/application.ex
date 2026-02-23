defmodule TtrpgDevCli.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    args = Burrito.Util.Args.get_arguments()

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
