defmodule ExRPGTest.RuleSystems do
  use ExUnit.Case
  alias ExRPG.RuleSystems

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
end
