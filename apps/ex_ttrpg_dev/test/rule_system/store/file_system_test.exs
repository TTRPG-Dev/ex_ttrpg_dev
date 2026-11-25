defmodule ExTTRPGDev.RuleSystem.Store.FileSystemTest do
  # Not async: overrides the global :local_system_configs_path app env.
  use ExUnit.Case
  import ExUnit.CaptureLog
  alias ExTTRPGDev.RuleSystem.Source
  alias ExTTRPGDev.RuleSystem.Store.{Entry, FileSystem}

  setup do
    root = Path.join(System.tmp_dir!(), "ex_ttrpg_store_#{System.unique_integer([:positive])}")
    previous = Application.fetch_env(:ex_ttrpg_dev, :local_system_configs_path)
    Application.put_env(:ex_ttrpg_dev, :local_system_configs_path, root)

    on_exit(fn ->
      case previous do
        {:ok, path} -> Application.put_env(:ex_ttrpg_dev, :local_system_configs_path, path)
        :error -> Application.delete_env(:ex_ttrpg_dev, :local_system_configs_path)
      end

      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  defp source(slug, version, requirement \\ nil) do
    module =
      %{"name" => slug, "slug" => slug, "version" => version}
      |> then(&if requirement, do: Map.put(&1, "library_requirement", requirement), else: &1)

    %Source{
      module: %{"module" => module},
      concepts: [{"concepts/a.toml", %{"ability" => %{"str" => %{"name" => "Str"}}}}]
    }
  end

  defp put(source, is_modifiable \\ true, overwrite \\ false) do
    FileSystem.put(Entry.from_source(source, is_modifiable), source, overwrite)
  end

  test "list_entries/0 is empty when the root doesn't exist" do
    assert {:ok, []} = FileSystem.list_entries()
  end

  test "canonical content is stored per version with its metadata", %{root: root} do
    assert :ok = put(source("sys", "1.0.0", "~> 0.15.0"), false)
    assert :ok = put(source("sys", "2.0.0", "~> 0.15.0"), false)

    assert File.regular?(Path.join(root, "sys/1.0.0/module.toml"))
    assert File.regular?(Path.join(root, "sys/2.0.0/module.toml"))

    assert {:ok,
            [
              %Entry{
                slug: "sys",
                version: "1.0.0",
                library_requirement: "~> 0.15.0",
                is_modifiable: false
              },
              %Entry{slug: "sys", version: "2.0.0", is_modifiable: false}
            ]} = FileSystem.list_entries()
  end

  test "non-canonical content is stored flat", %{root: root} do
    assert :ok = put(source("homebrew", "draft"))
    assert File.regular?(Path.join(root, "homebrew/module.toml"))

    assert {:ok, [%Entry{slug: "homebrew", version: "draft", is_modifiable: true}]} =
             FileSystem.list_entries()
  end

  test "a hand-authored directory without .store.toml is modifiable", %{root: root} do
    dir = Path.join(root, "handmade")
    :ok = Source.write(source("handmade", "0.1"), dir)

    assert {:ok, [%Entry{slug: "handmade", version: "0.1", is_modifiable: true}]} =
             FileSystem.list_entries()
  end

  test "an undecodable module.toml still lists, without a version", %{root: root} do
    dir = Path.join(root, "broken")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "module.toml"), "not = = toml")

    assert {:ok, [%Entry{slug: "broken", version: nil}]} = FileSystem.list_entries()
    assert {:error, {:module_parse_error, _}} = FileSystem.fetch("broken", nil)
  end

  test "a nested version whose module.toml disagrees with its directory is skipped", %{
    root: root
  } do
    :ok = put(source("sys", "1.0.0", "~> 0.15.0"))
    :ok = put(source("sys", "2.0.0", "~> 0.15.0"))

    module_path = Path.join(root, "sys/1.0.0/module.toml")
    File.write!(module_path, String.replace(File.read!(module_path), "1.0.0", "1.0.1"))

    log =
      capture_log(fn ->
        assert {:ok, [%Entry{version: "2.0.0"}]} = FileSystem.list_entries()
      end)

    assert log =~ "sys/1.0.0"
    assert log =~ ~s(declares version "1.0.1")
  end

  test "list_entries/0 fails, rather than omitting the slug, if a slug can't be read", %{
    root: root
  } do
    :ok = put(source("sys", "1.0.0", "~> 0.15.0"))
    slug_dir = Path.join(root, "sys")
    File.chmod!(slug_dir, 0o000)
    on_exit(fn -> File.chmod(slug_dir, 0o755) end)

    assert {:error, {"sys", :eacces}} = FileSystem.list_entries()
  end

  test "fetch/2 returns the stored content" do
    canonical = source("sys", "1.0.0", "~> 0.15.0")
    flat = source("homebrew", "draft")
    :ok = put(canonical)
    :ok = put(flat)

    assert {:ok, ^canonical} = FileSystem.fetch("sys", "1.0.0")
    assert {:ok, ^flat} = FileSystem.fetch("homebrew", "draft")
    assert {:error, :not_found} = FileSystem.fetch("sys", "9.9.9")
    assert {:error, :not_found} = FileSystem.fetch("homebrew", "other")
  end

  test "put/3 refuses to overwrite unless asked, and replaces when asked" do
    :ok = put(source("homebrew", "draft"))
    changed = %{source("homebrew", "draft") | concepts: []}

    assert {:error, :already_exists} = put(changed)
    assert :ok = put(changed, false, true)
    assert {:ok, ^changed} = FileSystem.fetch("homebrew", "draft")
    assert {:ok, [%Entry{is_modifiable: false}]} = FileSystem.list_entries()
  end

  test "put/3 leaves no temporary or aside directories behind", %{root: root} do
    :ok = put(source("homebrew", "draft"))
    :ok = put(source("homebrew", "draft"), true, true)
    assert File.ls!(root) == ["homebrew"]
  end

  test "concurrent non-overwriting puts: exactly one wins" do
    results =
      1..8
      |> Task.async_stream(fn _ -> put(source("sys", "1.0.0", "~> 0.15.0")) end)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == :ok)) == 1
    assert Enum.all?(results, &(&1 in [:ok, {:error, :already_exists}]))
  end

  test "delete/2 removes an entry and its slug directory once empty", %{root: root} do
    :ok = put(source("sys", "1.0.0", "~> 0.15.0"))
    :ok = put(source("sys", "2.0.0", "~> 0.15.0"))

    assert :ok = FileSystem.delete("sys", "1.0.0")
    assert {:ok, [%Entry{version: "2.0.0"}]} = FileSystem.list_entries()

    assert :ok = FileSystem.delete("sys", "2.0.0")
    refute File.exists?(Path.join(root, "sys"))
    assert {:error, :not_found} = FileSystem.delete("sys", "2.0.0")
  end

  test "slugs in any script are stored, listed and fetched" do
    unicode = source("règles_maison", "draft")
    :ok = put(unicode)

    assert {:ok, [%Entry{slug: "règles_maison"}]} = FileSystem.list_entries()
    assert {:ok, ^unicode} = FileSystem.fetch("règles_maison", "draft")
  end

  test "a decomposed directory name is listed only if its composed slug resolves", %{
    root: root
  } do
    :ok = put(source("zoë", "draft"))
    nfd = Path.join(root, "zoe\u0308")

    if File.dir?(nfd) do
      # HFS+-like: both forms name the one directory.
      assert {:ok, [%Entry{slug: "zoë"}]} = FileSystem.list_entries()
    else
      # ext4-like: an NFD twin is a separate directory. It can't be fetched
      # as "zoë", so only the composed one is listed.
      File.cp_r!(Path.join(root, "zoë"), nfd)
      assert {:ok, [%Entry{slug: "zoë"}]} = FileSystem.list_entries()

      File.rm_rf!(Path.join(root, "zoë"))
      assert {:ok, []} = FileSystem.list_entries()
    end
  end

  test "slugs and versions that could escape the root are rejected" do
    assert {:error, {:invalid_slug, "../x"}} = put(source("../x", "draft"))
    assert {:error, {:invalid_version, "../1"}} = put(source("sys", "../1", "~> 0.15.0"))
    assert {:error, {:invalid_slug, "../x"}} = FileSystem.fetch("../x", "draft")
  end
end
