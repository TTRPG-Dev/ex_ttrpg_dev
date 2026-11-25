defmodule ExTTRPGDev.RuleSystems.StoreAdapterTest do
  # Not async: configures the global `:rule_system_store` application env.
  use ExUnit.Case
  import ExUnit.CaptureLog

  alias ExTTRPGDev.RuleSystem.Store
  alias ExTTRPGDev.RuleSystem.Store.Entry
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.RuleSystems.{Bundled, LoadedSystem}

  @bundled "dnd_5e_srd"

  defmodule InMemory do
    @moduledoc false
    # A minimal non-filesystem adapter: {entry, source} pairs keyed by
    # {slug, version} in an Agent. Unlike the filesystem adapter, it files
    # every version separately, even for non-canonical systems.
    @behaviour ExTTRPGDev.RuleSystem.Store

    def start_link(_), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

    def child_spec(arg), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [arg]}}

    @impl true
    def list_entries do
      {:ok, Agent.get(__MODULE__, fn rows -> Enum.map(Map.values(rows), &elem(&1, 0)) end)}
    end

    @impl true
    def fetch(slug, version) do
      case Agent.get(__MODULE__, &Map.fetch(&1, {slug, version})) do
        {:ok, {_entry, source}} -> {:ok, source}
        :error -> {:error, :not_found}
      end
    end

    @impl true
    def put(entry, source, overwrite) do
      key = {entry.slug, entry.version}

      Agent.get_and_update(__MODULE__, fn rows ->
        if Map.has_key?(rows, key) and not overwrite,
          do: {{:error, :already_exists}, rows},
          else: {:ok, Map.put(rows, key, {entry, source})}
      end)
    end

    @impl true
    def delete(slug, version) do
      Agent.get_and_update(__MODULE__, fn rows ->
        if Map.has_key?(rows, {slug, version}),
          do: {:ok, Map.delete(rows, {slug, version})},
          else: {{:error, :not_found}, rows}
      end)
    end
  end

  defmodule LosesRace do
    @moduledoc false
    # InMemory, except every non-overwriting put finds that another writer
    # stored the same entry just before it: the race between a create's
    # collision check and its write.
    @behaviour ExTTRPGDev.RuleSystem.Store

    @impl true
    defdelegate list_entries(), to: InMemory
    @impl true
    defdelegate fetch(slug, version), to: InMemory
    @impl true
    defdelegate delete(slug, version), to: InMemory

    @impl true
    def put(entry, source, false) do
      :ok = InMemory.put(entry, source, false)
      {:error, :already_exists}
    end

    def put(entry, source, true), do: InMemory.put(entry, source, true)
  end

  setup do
    start_supervised!(InMemory)
    previous_root = Application.fetch_env!(:ex_ttrpg_dev, :local_system_configs_path)
    Application.put_env(:ex_ttrpg_dev, :rule_system_store, InMemory)

    # Point the filesystem store somewhere fresh, to prove nothing lands there.
    dir =
      Path.join(System.tmp_dir!(), "ex_ttrpg_rs_adapter_#{System.unique_integer([:positive])}")

    Application.put_env(:ex_ttrpg_dev, :local_system_configs_path, dir)

    on_exit(fn ->
      Application.delete_env(:ex_ttrpg_dev, :rule_system_store)
      Application.put_env(:ex_ttrpg_dev, :local_system_configs_path, previous_root)
      File.rm_rf(dir)
    end)

    {:ok, bundled} = Bundled.fetch(@bundled)
    {:ok, bundled: bundled, fs_root: dir}
  end

  defp homebrew(bundled, slug) do
    bundled
    |> put_in([Access.key(:module), "module", "slug"], slug)
    |> put_in([Access.key(:module), "module", "version"], "0.1.0")
    |> update_in([Access.key(:module), "module"], &Map.delete(&1, "library_requirement"))
  end

  test "the configured adapter is the one in use" do
    assert Store.adapter() == InMemory
  end

  test "a system held only by the adapter loads unchanged", %{bundled: bundled, fs_root: root} do
    source = homebrew(bundled, "homebrew")
    :ok = InMemory.put(Entry.from_source(source, true), source, false)

    assert "homebrew" in RuleSystems.list_systems()
    assert RuleSystems.local_system?("homebrew")

    assert {:ok, %LoadedSystem{module: %{slug: "homebrew", version: "0.1.0"}}} =
             RuleSystems.load_system("homebrew")

    refute File.exists?(root)
  end

  test "bundled systems seed into the configured adapter", %{fs_root: root} do
    capture_log(fn -> assert {:ok, %LoadedSystem{}} = RuleSystems.load_system(@bundled) end)

    assert {:ok, [%Entry{slug: @bundled, is_modifiable: false}]} = InMemory.list_entries()
    refute File.exists?(root)
  end

  test "cloning and updating write through the adapter", %{fs_root: root} do
    capture_log(fn -> assert {:ok, "my_srd"} = RuleSystems.clone_system(@bundled, "my_srd") end)

    assert :ok =
             RuleSystems.update_system("my_srd", fn source ->
               put_in(source.module["module"]["version"], "homebrew-2")
             end)

    {:ok, entries} = InMemory.list_entries()

    assert [%Entry{version: "homebrew-2", is_modifiable: true}] =
             Enum.filter(entries, &(&1.slug == "my_srd"))

    refute File.exists?(root)
  end

  test "a create that loses a race for its slug is :slug_taken, not :slug_occupied" do
    Application.put_env(:ex_ttrpg_dev, :rule_system_store, LosesRace)

    assert {:error, {:slug_taken, "homebrew"}} =
             RuleSystems.create_system(%{"name" => "Homebrew"})
  end
end
