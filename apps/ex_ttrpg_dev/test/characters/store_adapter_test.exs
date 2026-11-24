defmodule ExTTRPGDevTest.Characters.StoreAdapter do
  # Not async: configures the global `:characters_store` application env.
  use ExUnit.Case

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.{Character, Metadata, Store}

  defmodule InMemory do
    @moduledoc false
    # A minimal non-filesystem adapter: characters held as JSON in an Agent.
    @behaviour ExTTRPGDev.Characters.Store

    alias ExTTRPGDev.Characters.Character

    def start_link(_), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

    def child_spec(arg), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [arg]}}

    @impl true
    def character_exists?(slug), do: Agent.get(__MODULE__, &Map.has_key?(&1, slug))

    @impl true
    def save_character(%Character{metadata: %{slug: slug}} = character, overwrite) do
      json = Jason.encode!(Character.to_json_map(character))

      Agent.get_and_update(__MODULE__, fn rows ->
        if Map.has_key?(rows, slug) and not overwrite,
          do: {{:error, :already_exists}, rows},
          else: {:ok, Map.put(rows, slug, json)}
      end)
    end

    @impl true
    def delete_character(slug) do
      Agent.get_and_update(__MODULE__, fn rows ->
        if Map.has_key?(rows, slug),
          do: {:ok, Map.delete(rows, slug)},
          else: {{:error, :not_found}, rows}
      end)
    end

    @impl true
    def list_characters, do: {:ok, Agent.get(__MODULE__, &Map.keys/1)}

    @impl true
    def load_character(slug) do
      case Agent.get(__MODULE__, &Map.fetch(&1, slug)) do
        {:ok, json} -> Character.from_json(json)
        :error -> {:error, :not_found}
      end
    end

    def put_raw(slug, json), do: Agent.update(__MODULE__, &Map.put(&1, slug, json))
  end

  setup do
    start_supervised!(InMemory)
    Application.put_env(:ex_ttrpg_dev, :characters_store, InMemory)

    # Point the filesystem adapter somewhere fresh, to prove nothing lands there.
    tmp_dir =
      Path.join(System.tmp_dir!(), "ex_ttrpg_dev_adapter_#{System.unique_integer([:positive])}")

    Application.put_env(:ex_ttrpg_dev, :characters_path, tmp_dir)

    on_exit(fn ->
      Application.delete_env(:ex_ttrpg_dev, :characters_store)
      Application.delete_env(:ex_ttrpg_dev, :characters_path)
      File.rm_rf(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  defp character(slug, rule_system \\ "sys", version \\ "1.0.0") do
    %Character{
      name: "Character #{slug}",
      generated_values: %{{"ability", "strength", "score"} => 12},
      metadata: %Metadata{slug: slug, rule_system: rule_system, rule_system_version: version}
    }
  end

  test "the configured adapter is the one in use" do
    assert Store.adapter() == InMemory
  end

  test "the public API round-trips a character through the adapter", %{tmp_dir: tmp_dir} do
    hero = character("hero")

    refute Characters.character_exists?(hero)
    assert :ok = Characters.save_character(hero)
    assert Characters.character_exists?(hero)
    assert Characters.character_exists?("hero")
    assert {:ok, ^hero} = Characters.load_character("hero")
    assert Characters.load_character!("hero") == hero
    assert {:ok, ["hero"]} = Characters.list_characters()
    assert Characters.list_characters!() == ["hero"]

    refute File.exists?(tmp_dir)
  end

  test "save_character/2 respects overwrite" do
    assert :ok = Characters.save_character(character("hero"))
    assert {:error, :already_exists} = Characters.save_character(character("hero"))
    assert :ok = Characters.save_character(%{character("hero") | name: "Renamed"}, true)
    assert Characters.load_character!("hero").name == "Renamed"
  end

  test "bang variants raise on adapter errors" do
    Characters.save_character!(character("hero"))

    assert_raise RuntimeError, ~r/already exists/, fn ->
      Characters.save_character!(character("hero"))
    end

    assert_raise RuntimeError, ~r/:not_found/, fn -> Characters.load_character!("nobody") end
  end

  test "delete_character/1 removes the character, then reports :not_found" do
    Characters.save_character!(character("hero"))

    assert :ok = Characters.delete_character("hero")
    refute Characters.character_exists?("hero")
    assert {:error, :not_found} = Characters.delete_character("hero")
    assert {:error, :not_found} = Characters.load_character("hero")
  end

  test "characters_depending_on/2 works against the adapter" do
    Characters.save_character!(character("on_line", "sys", "1.2.0"))
    Characters.save_character!(character("next_major", "sys", "2.0.0"))
    Characters.save_character!(character("elsewhere", "other", "1.2.0"))

    assert {:ok, ["on_line"]} = Characters.characters_depending_on("sys", "1.0.0")

    InMemory.put_raw("corrupt", "not json")

    assert {:error, {:unreadable_characters, [{"corrupt", {:invalid_character_data, _}}]}} =
             Characters.characters_depending_on("sys", "1.0.0")
  end
end
