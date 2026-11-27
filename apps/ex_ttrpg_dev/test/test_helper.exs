# Rule systems are installed into a store rooted at local_system_configs_path,
# and loading a bundled system seeds it there. Point it at a per-run temp
# directory so test runs never write into the working tree. The directory
# keeps the default's basename, which some tests assert on.
test_systems_root =
  Path.join([
    System.tmp_dir!(),
    "ex_ttrpg_dev_test_#{System.unique_integer([:positive])}",
    "local_system_configs"
  ])

Application.put_env(:ex_ttrpg_dev, :local_system_configs_path, test_systems_root)
ExUnit.after_suite(fn _ -> File.rm_rf(Path.dirname(test_systems_root)) end)

Code.require_file("support/class_levels_fixture.exs", __DIR__)

ExUnit.start()
