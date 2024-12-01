defmodule ExTTRPGDevTest.RuleSystems do
  use ExUnit.Case
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.Globals

  doctest ExTTRPGDev.RuleSystems,
    except: [
      is_local_system?: 1,
      system_path!: 1,
      load_system!: 1,
      save_system!: 1,
      save_system!: 2,
      gen_character!: 1
    ]

  def build_test_system do
    [system_slug | _tail] = RuleSystems.list_systems()

    %RuleSystems.RuleSystem{metadata: %RuleSystems.Metadata{} = metadata} =
      system = RuleSystems.load_system!(system_slug)

    sha = :crypto.hash(:sha, "#{DateTime.utc_now()}") |> Base.encode16() |> String.downcase()
    test_system_slug = "test_#{system_slug}_#{sha}"

    updated_metadata = Map.put(metadata, :slug, test_system_slug)
    Map.put(system, :metadata, updated_metadata)
  end

  def save_test_system do
    %RuleSystems.RuleSystem{metadata: %RuleSystems.Metadata{slug: system_slug}} =
      system = build_test_system()

    RuleSystems.save_system!(system)
    system_slug
  end

  def delete_test_system(system_slug) do
    first_five = String.slice(system_slug, 0..4)

    if first_five != "test_" do
      raise "Trying to delete a non 'test_' system '#{system_slug} during test"
    else
      system_path = RuleSystems.system_path!(system_slug)
      File.rm_rf!(system_path)
    end
  end

  test "load_system!/1 for bundled system" do
    [bundled_system_slug | _tail] = RuleSystems.list_bundled_systems()

    %RuleSystems.RuleSystem{metadata: %RuleSystems.Metadata{slug: loaded_slug}} =
      RuleSystems.load_system!(bundled_system_slug)

    assert loaded_slug == bundled_system_slug
  end

  test "load_system!/1 for custom system" do
    custom_slug = save_test_system()

    %RuleSystems.RuleSystem{metadata: %RuleSystems.Metadata{slug: loaded_slug}} =
      RuleSystems.load_system!(custom_slug)

    assert loaded_slug == custom_slug

    delete_test_system(custom_slug)
  end

  test "load_system!/1 for unconfigured system" do
    %RuleSystems.RuleSystem{metadata: %RuleSystems.Metadata{slug: custom_slug}} =
      build_test_system()

    assert_raise File.Error, fn -> RuleSystems.load_system!(custom_slug) end
  end

  test "system_path!/1" do
    [bundled_system_slug | _tail] = RuleSystems.list_bundled_systems()

    assert RuleSystems.system_path!(bundled_system_slug) ==
             Path.join([Globals.system_configs_path(), bundled_system_slug])

    custom_slug = "custom_system"

    assert RuleSystems.system_path!(custom_slug) ==
             Path.join([Globals.local_system_configs_path(), custom_slug])
  end

  test "is_local_system?/1" do
    assert not RuleSystems.is_local_system?("dnd_5e_srd")

    %RuleSystems.RuleSystem{metadata: %RuleSystems.Metadata{slug: system_slug}} =
      system = build_test_system()

    assert not RuleSystems.is_local_system?(system_slug)

    RuleSystems.save_system!(system)
    assert RuleSystems.is_local_system?(system_slug)
    delete_test_system(system_slug)
  end

  test "saving a system" do
    %RuleSystems.RuleSystem{metadata: %RuleSystems.Metadata{slug: system_slug}} =
      system = build_test_system()

    existing_systems = RuleSystems.list_systems()
    assert not Enum.member?(existing_systems, system_slug)

    RuleSystems.save_system!(system)

    existing_systems = RuleSystems.list_systems()
    assert Enum.member?(existing_systems, system_slug)

    delete_test_system(system_slug)
  end

  test "saving a system without override that already exists fails" do
    system_slug = save_test_system()

    existing_system = RuleSystems.load_system!(system_slug)
    assert_raise RuntimeError, fn -> RuleSystems.save_system!(existing_system) end

    delete_test_system(system_slug)
  end

  test "saving a system with override that already exists" do
    system_slug = save_test_system()

    existing_system = RuleSystems.load_system!(system_slug)
    RuleSystems.save_system!(existing_system, true)

    delete_test_system(system_slug)
  end

  test "saving a bundled system fails" do
    [bundled_system_slug | _tail] = RuleSystems.list_bundled_systems()
    bundled_system = RuleSystems.load_system!(bundled_system_slug)
    assert_raise RuntimeError, fn -> RuleSystems.save_system!(bundled_system) end
  end

  test "gen_character!/1" do
    dnd_5e_srd = RuleSystems.load_system!("dnd_5e_srd")
    generated_character = RuleSystems.RuleSystem.gen_character!(dnd_5e_srd)

    assert generated_character.name != nil
    assert generated_character.rule_system == dnd_5e_srd.metadata

    # Assert that each ability spec is found within the generated character's ability_scores
    dnd_5e_srd.abilities.specs
    |> Enum.each(fn spec ->
      score = Map.get(generated_character.ability_scores, spec.name)
      assert score != nil, "Could not find ability #{spec.name} on generated character"
    end)
  end
end
