[
  # The Task fn in TtrpgDevCli.Application always calls System.halt/1
  # after the CLI exits, which is intentional — the function is no_return by design.
  {"lib/application.ex", :no_return}
]
