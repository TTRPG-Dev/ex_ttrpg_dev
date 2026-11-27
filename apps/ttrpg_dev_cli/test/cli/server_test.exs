defmodule ExTTRPGDev.CLI.ServerTest do
  use ExUnit.Case, async: false

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.{Character, Metadata}
  alias ExTTRPGDev.CLI.Server
  alias ExTTRPGDev.RuleSystems

  @initial_state %{pending: %{}, next_id: 1}

  defp run(cmd), do: elem(Server.handle_command(cmd, @initial_state), 0)

  # ── roll ──────────────────────────────────────────────────────────────────────

  describe "roll" do
    test "returns correct spec and roll count for dice notation" do
      assert [%{spec: "2d6", rolls: [_, _]}] =
               run(%{"command" => "roll", "dice" => "2d6"}).data.results
    end

    test "dice total equals sum of individual rolls" do
      [%{rolls: rolls, total: total}] = run(%{"command" => "roll", "dice" => "2d6"}).data.results
      assert total == Enum.sum(rolls)
    end

    test "accepts multiple comma-separated specs" do
      assert [_, _] = run(%{"command" => "roll", "dice" => "1d4,1d8"}).data.results
    end
  end

  # ── systems ───────────────────────────────────────────────────────────────────

  describe "systems" do
    test "systems.list includes dnd_5e_srd" do
      assert "dnd_5e_srd" in run(%{"command" => "systems.list"}).data.systems
    end

    test "systems.show returns module metadata" do
      data = run(%{"command" => "systems.show", "system" => "dnd_5e_srd"}).data
      assert data.name == "Dungeons and Dragons 5th Edition SRD"
      assert data.slug == "dnd_5e_srd"
      assert data.version == "2.1.0"
    end

    test "systems.show returns concept list when concept_type given" do
      data =
        run(%{
          "command" => "systems.show",
          "system" => "dnd_5e_srd",
          "concept_type" => "skill"
        }).data

      assert data.concepts != []
      assert Enum.any?(data.concepts, &(&1.id == "acrobatics"))
    end

    test "systems.show errors for unknown system" do
      assert run(%{"command" => "systems.show", "system" => "nonexistent"}).status == "error"
    end
  end

  describe "systems.create" do
    setup do
      on_exit(fn -> RuleSystems.delete_system("my_fantasy_system") end)
    end

    test "creates a loadable local system and reports its module.toml path" do
      data =
        run(%{
          "command" => "systems.create",
          "name" => "My Fantasy System",
          "publisher" => "Acme Games",
          "family" => ""
        }).data

      assert data.created == "my_fantasy_system"
      assert data.version == "1.0.0"

      assert data.path ==
               Path.join([
                 ExTTRPGDev.Globals.local_system_configs_path(),
                 "my_fantasy_system",
                 "module.toml"
               ])

      assert {:ok, %{"module" => module}} = data.path |> File.read!() |> TomlElixir.decode()

      assert module == %{
               "name" => "My Fantasy System",
               "slug" => "my_fantasy_system",
               "version" => "1.0.0",
               "publisher" => "Acme Games"
             }

      assert run(%{"command" => "systems.show", "system" => "my_fantasy_system"}).status == "ok"
    end

    test "reports a given version" do
      data =
        run(%{"command" => "systems.create", "name" => "My Fantasy System", "version" => "0.1"}).data

      assert data.version == "0.1"
    end

    test "refuses a slug that's taken, including a bundled one" do
      response = run(%{"command" => "systems.create", "name" => "DnD 5e SRD"})
      assert response.message == ~s(a rule system with slug "dnd_5e_srd" already exists)
    end

    test "names a directory that occupies the slug without being a system" do
      dir = Path.join(ExTTRPGDev.Globals.local_system_configs_path(), "my_fantasy_system")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)

      response = run(%{"command" => "systems.create", "name" => "My Fantasy System"})

      assert response.message ==
               "something already exists at #{dir} (or a differently cased name) " <>
                 "that isn't a listed rule system, e.g. a directory with no module.toml. " <>
                 "Remove or rename it, or choose another name."

      assert File.ls!(dir) == []
    end

    test "explains a name that yields no slug" do
      response = run(%{"command" => "systems.create", "name" => "!!!"})
      assert response.message =~ ~s(can't derive a slug from name "!!!")
    end

    test "explains a name too long for a slug" do
      response = run(%{"command" => "systems.create", "name" => String.duplicate("a", 250)})

      assert response.message ==
               "the name is too long: its slug would be 250 bytes, " <>
                 "and the limit is 200. Try a shorter name."
    end

    test "requires a name" do
      response = run(%{"command" => "systems.create", "publisher" => "Acme"})
      assert response.message == "name is required"
    end

    test "rejects unknown fields" do
      response = run(%{"command" => "systems.create", "name" => "X", "bogus" => "y"})
      assert response.message == ~s(unknown rule system field: "bogus")
    end
  end

  describe "systems.copy" do
    setup do
      on_exit(fn ->
        for slug <- RuleSystems.list_local_systems!(), do: RuleSystems.delete_system(slug)
      end)
    end

    defp copy(cmd) do
      ExUnit.CaptureLog.capture_log(fn -> send(self(), {:copied, run(cmd)}) end)
      assert_received {:copied, response}
      response
    end

    test "copies to the given slug, naming the copy after the source" do
      data =
        copy(%{"command" => "systems.copy", "system" => "dnd_5e_srd", "slug" => "my_dnd"}).data

      assert data == %{
               copied: "dnd_5e_srd",
               created: "my_dnd",
               name: "Dungeons and Dragons 5th Edition SRD (copy)",
               path: Path.join(ExTTRPGDev.Globals.local_system_configs_path(), "my_dnd")
             }

      shown = run(%{"command" => "systems.show", "system" => "my_dnd"}).data
      assert shown.slug == "my_dnd"
      assert shown.name == data.name
    end

    test "without a slug, takes the first free <source>_copy_N" do
      created =
        for _ <- 1..2 do
          copy(%{"command" => "systems.copy", "system" => "dnd_5e_srd"}).data.created
        end

      assert created == ["dnd_5e_srd_copy_1", "dnd_5e_srd_copy_2"]
    end

    test "a null slug means none was given" do
      response = copy(%{"command" => "systems.copy", "system" => "dnd_5e_srd", "slug" => nil})
      assert response.data.created == "dnd_5e_srd_copy_1"
    end

    test "skips a _copy_N slug something that isn't a system occupies" do
      dir = Path.join(ExTTRPGDev.Globals.local_system_configs_path(), "dnd_5e_srd_copy_1")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      assert copy(%{"command" => "systems.copy", "system" => "dnd_5e_srd"}).data.created ==
               "dnd_5e_srd_copy_2"
    end

    test "refuses a given slug that is taken" do
      response =
        copy(%{"command" => "systems.copy", "system" => "dnd_5e_srd", "slug" => "dnd_5e_srd"})

      assert response.message == ~s(a rule system with slug "dnd_5e_srd" already exists)
    end

    test "refuses a malformed or too-long slug" do
      response =
        copy(%{"command" => "systems.copy", "system" => "dnd_5e_srd", "slug" => "My-DnD"})

      assert response.message =~ ~s(invalid slug "My-DnD")

      long = String.duplicate("a", 250)
      response = copy(%{"command" => "systems.copy", "system" => "dnd_5e_srd", "slug" => long})
      assert response.message == "the slug is too long: it's 250 bytes, and the limit is 200"
    end

    test "asks for a slug when the source's can't take a _copy_N suffix" do
      long = String.duplicate("a", 195)
      {:ok, ^long} = RuleSystems.create_system(%{"name" => "Long", "slug" => long})

      response = copy(%{"command" => "systems.copy", "system" => long})

      assert response.message ==
               ~s(can't derive a slug for the copy from "#{long}"; ) <>
                 "give one: systems copy #{long} <new_slug>"
    end

    test "copies a system whose content doesn't load" do
      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, "draft"} = RuleSystems.clone_system("dnd_5e_srd", "draft", name: "Draft")
      end)

      concepts = Path.join(ExTTRPGDev.Globals.local_system_configs_path(), "draft/concepts")
      File.mkdir_p!(concepts)

      File.write!(Path.join(concepts, "broken.toml"), """
      [ability.broken]
      name = "Broken"
      score.type = "formula"
      score.formula = "ability('nope').score"
      """)

      assert {:error, _} = RuleSystems.load_system("draft")

      data = copy(%{"command" => "systems.copy", "system" => "draft", "slug" => "draft_fix"}).data
      assert {data.created, data.name} == {"draft_fix", "Draft (copy)"}
    end

    test "refuses an unknown source" do
      response = copy(%{"command" => "systems.copy", "system" => "nonexistent"})
      assert response.message == ~s(rule system not found: "nonexistent")
    end

    test "rejects a slug that isn't a string" do
      response = run(%{"command" => "systems.copy", "system" => "dnd_5e_srd", "slug" => 7})
      assert response.status == "error"
      assert RuleSystems.list_local_systems!() == []
    end
  end

  describe "systems.concept_type.add" do
    setup do
      {:ok, "concept_type_test"} = RuleSystems.create_system(%{"name" => "Concept Type Test"})
      on_exit(fn -> RuleSystems.delete_system("concept_type_test") end)
    end

    defp add(fields),
      do: run(Map.merge(%{"command" => "systems.concept_type.add"}, fields))

    test "appends the type and reports its ID and module.toml" do
      data =
        add(%{
          "system" => "concept_type_test",
          "name" => "Feat",
          "display_template" => "{{name}} (Cost: {{cost}})"
        }).data

      path =
        Path.join([
          ExTTRPGDev.Globals.local_system_configs_path(),
          "concept_type_test",
          "module.toml"
        ])

      assert data == %{added: "feat", system: "concept_type_test", path: path}

      assert {:ok, %{"concept_type" => [concept_type]}} =
               path |> File.read!() |> TomlElixir.decode()

      assert concept_type == %{
               "id" => "feat",
               "name" => "Feat",
               "display" => %{"template" => "{{name}} (Cost: {{cost}})"}
             }
    end

    test "explains each refusal" do
      add(%{"system" => "concept_type_test", "name" => "Feat"})

      for {fields, message} <- [
            {%{"name" => "FEAT"},
             ~s(rule system "concept_type_test" already has a concept type "feat")},
            {%{"name" => " !! "},
             ~s(can't derive a concept type ID from name "!!": it needs at least one letter or digit)},
            {%{"name" => "  Über "},
             ~s{can't use "über" (from name "Über") as a concept type ID: } <>
               "formulas can only refer to IDs made of ASCII letters, digits and underscores"},
            {%{}, "name is required"},
            {%{"name" => "X", "id" => "x"}, ~s(unknown concept type field: "id")},
            {%{"name" => 7}, ~s(concept type field "name" must be a string)}
          ] do
        assert add(Map.put(fields, "system", "concept_type_test")).message == message
      end
    end

    test "refuses unknown and bundled systems" do
      assert add(%{"system" => "nope", "name" => "Feat"}).message ==
               ~s(rule system not found: "nope")

      ExUnit.CaptureLog.capture_log(fn ->
        send(self(), {:added, add(%{"system" => "dnd_5e_srd", "name" => "Feat"})})
      end)

      assert_received {:added, response}

      assert response.message ==
               ~s{rule system "dnd_5e_srd" is not modifiable (bundled systems can't be edited). } <>
                 "Copy it first: systems copy dnd_5e_srd"
    end

    test "refuses a missing or non-string system" do
      assert add(%{"name" => "Feat"}).message =~ "invalid arguments"
      assert add(%{"system" => 7, "name" => "Feat"}).message =~ "invalid arguments"
    end
  end

  describe "systems.delete" do
    # Delete checks every saved character, so point the characters store at
    # an empty temp directory rather than whatever the working tree holds.
    setup do
      characters =
        Path.join(System.tmp_dir!(), "ttrpg_cli_delete_#{System.unique_integer([:positive])}")

      Application.put_env(:ex_ttrpg_dev, :characters_path, characters)

      on_exit(fn ->
        Application.delete_env(:ex_ttrpg_dev, :characters_path)
        File.rm_rf!(characters)
        RuleSystems.delete_system("delete_me")
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, _} = RuleSystems.clone_system("dnd_5e_srd", "delete_me")
      end)

      :ok
    end

    test "deletes a local system and reports its path" do
      data = run(%{"command" => "systems.delete", "system" => "delete_me"}).data
      assert data.deleted == "delete_me"
      assert data.path == Path.join(ExTTRPGDev.Globals.local_system_configs_path(), "delete_me")
      refute File.exists?(data.path)
      refute RuleSystems.configured?("delete_me")
    end

    test "refuses a bundled system" do
      response = run(%{"command" => "systems.delete", "system" => "dnd_5e_srd"})
      assert response.status == "error"
      assert response.message =~ "not modifiable"
    end

    test "refuses an unknown system" do
      response = run(%{"command" => "systems.delete", "system" => "nonexistent"})
      assert response.message == ~s(rule system not found: "nonexistent")
    end

    test "refuses while saved characters use it, listing them" do
      for slug <- ["aria", "boblin"] do
        :ok =
          Characters.save_character(%Character{
            name: slug,
            generated_values: %{},
            metadata: %Metadata{slug: slug, rule_system: "delete_me", rule_system_version: "x"}
          })
      end

      response = run(%{"command" => "systems.delete", "system" => "delete_me"})
      assert response.status == "error"
      assert response.message =~ "2 saved character(s) use it: "
      assert response.message =~ "aria"
      assert response.message =~ "boblin"
      assert RuleSystems.configured?("delete_me")
    end

    test "refuses when a character file can't be read" do
      dir = ExTTRPGDev.Globals.characters_path()
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "corrupt.json"), "not json")

      response = run(%{"command" => "systems.delete", "system" => "delete_me"})
      assert response.message =~ "can't be read: corrupt"
      assert RuleSystems.configured?("delete_me")
    end
  end

  # ── characters.gen ────────────────────────────────────────────────────────────

  describe "characters.gen" do
    test "stores generated character in pending state" do
      {response, state} =
        Server.handle_command(
          %{"command" => "characters.gen", "system" => "dnd_5e_srd"},
          @initial_state
        )

      assert response.status == "ok"
      assert is_binary(response.data.temp_id)
      assert map_size(state.pending) == 1
    end

    test "response data includes character fields" do
      data = run(%{"command" => "characters.gen", "system" => "dnd_5e_srd"}).data
      assert data.rule_system == "dnd_5e_srd"
      assert is_list(data.character_lists)
      assert is_list(data.choices)
    end

    test "language display templates apply per display mode" do
      lang_items = fn mode ->
        result =
          run(%{
            "command" => "characters.gen",
            "system" => "dnd_5e_srd",
            "display_mode" => mode
          })

        Enum.find(result.data.character_lists, &(&1.label == "Languages")).items
      end

      assert Enum.all?(lang_items.("default"), &String.contains?(&1, "("))
      refute Enum.any?(lang_items.("succinct"), &String.contains?(&1, "("))
      assert Enum.all?(lang_items.("verbose"), &String.contains?(&1, "script:"))
    end

    test "gen auto-resolves all level-1 pending choices" do
      {gen_resp, state} =
        Server.handle_command(
          %{"command" => "characters.gen", "system" => "dnd_5e_srd"},
          @initial_state
        )

      assert gen_resp.status == "ok"

      {save_resp, _} =
        Server.handle_command(
          %{"command" => "characters.save", "temp_id" => gen_resp.data.temp_id},
          state
        )

      slug = save_resp.data.slug
      on_exit(fn -> Characters.delete_character(slug) end)

      data = run(%{"command" => "characters.choices", "character" => slug}).data

      level_1_pending =
        Enum.filter(data.pending_choices, fn c ->
          c[:type] == "pending" and c[:earned_at_level] in [nil, 1]
        end)

      assert level_1_pending == []
    end

    test "errors for unknown system without touching pending state" do
      {response, state} =
        Server.handle_command(
          %{"command" => "characters.gen", "system" => "nonexistent"},
          @initial_state
        )

      assert {response.status, map_size(state.pending)} == {"error", 0}
    end
  end

  # ── character lifecycle ────────────────────────────────────────────────────────

  describe "character lifecycle" do
    setup do
      {gen_response, state1} =
        Server.handle_command(
          %{"command" => "characters.gen", "system" => "dnd_5e_srd"},
          @initial_state
        )

      assert gen_response.status == "ok"
      temp_id = gen_response.data.temp_id

      {save_response, _state2} =
        Server.handle_command(
          %{"command" => "characters.save", "temp_id" => temp_id},
          state1
        )

      assert save_response.status == "ok"
      slug = save_response.data.slug
      on_exit(fn -> Characters.delete_character(slug) end)

      %{slug: slug}
    end

    test "characters.list includes the saved character", %{slug: slug} do
      slugs =
        run(%{"command" => "characters.list"}).data.characters
        |> Enum.map(& &1.slug)

      assert slug in slugs
    end

    test "characters.list filters by system", %{slug: slug} do
      slugs =
        run(%{"command" => "characters.list", "system" => "dnd_5e_srd"}).data.characters
        |> Enum.map(& &1.slug)

      assert slug in slugs
    end

    test "characters.list skips a corrupt character file instead of failing entirely", %{
      slug: slug
    } do
      corrupt_path = Path.join(ExTTRPGDev.Globals.characters_path(), "corrupt.json")
      File.write!(corrupt_path, "not valid json")
      on_exit(fn -> File.rm(corrupt_path) end)

      slugs =
        run(%{"command" => "characters.list"}).data.characters
        |> Enum.map(& &1.slug)

      assert slug in slugs
      refute "corrupt" in slugs
    end

    test "characters.show renders language scripts in default mode", %{slug: slug} do
      data =
        run(%{
          "command" => "characters.show",
          "character" => slug,
          "display_mode" => "default"
        }).data

      assert data.slug == slug
      lang_items = Enum.find(data.character_lists, &(&1.label == "Languages")).items
      assert Enum.all?(lang_items, &String.contains?(&1, "("))
    end

    test "characters.show renders plain language names in succinct mode", %{slug: slug} do
      lang_items =
        run(%{
          "command" => "characters.show",
          "character" => slug,
          "display_mode" => "succinct"
        }).data.character_lists
        |> Enum.find(&(&1.label == "Languages"))
        |> Map.get(:items)

      refute Enum.any?(lang_items, &String.contains?(&1, "("))
    end

    test "characters.delete removes the character", %{slug: slug} do
      assert run(%{"command" => "characters.delete", "character" => slug}).data.deleted == slug

      assert run(%{"command" => "characters.show", "character" => slug}).status == "error"
    end
  end

  describe "characters.copy" do
    # Copying picks slugs by listing every saved character, so point the
    # store at an empty temp directory.
    setup do
      characters =
        Path.join(System.tmp_dir!(), "ttrpg_cli_copy_#{System.unique_integer([:positive])}")

      Application.put_env(:ex_ttrpg_dev, :characters_path, characters)

      on_exit(fn ->
        Application.delete_env(:ex_ttrpg_dev, :characters_path)
        File.rm_rf!(characters)
      end)

      character = %Character{
        name: "Aria Stormwind",
        generated_values: %{},
        metadata: %Metadata{slug: "aria", rule_system: "none", rule_system_version: "1.0.0"}
      }

      :ok = Characters.save_character(character)
      %{character: character}
    end

    test "copies to the given slug, renaming only the copy", %{character: character} do
      response = run(%{"command" => "characters.copy", "character" => "aria", "slug" => "backup"})

      assert response.data == %{
               copied: "aria",
               created: "backup",
               name: "Aria Stormwind (copy)"
             }

      {:ok, copy} = Characters.load_character("backup")

      assert copy == %{
               character
               | name: "Aria Stormwind (copy)",
                 metadata: %{character.metadata | slug: "backup"}
             }

      assert Characters.load_character("aria") == {:ok, character}
    end

    test "carries over everything a generated character has" do
      {gen, state} =
        Server.handle_command(
          %{"command" => "characters.gen", "system" => "dnd_5e_srd"},
          @initial_state
        )

      {saved, _} =
        Server.handle_command(
          %{"command" => "characters.save", "temp_id" => gen.data.temp_id},
          state
        )

      slug = saved.data.slug
      created = run(%{"command" => "characters.copy", "character" => slug}).data.created

      {:ok, source} = Characters.load_character(slug)
      {:ok, copy} = Characters.load_character(created)
      assert Map.drop(copy, [:name, :metadata]) == Map.drop(source, [:name, :metadata])
      assert run(%{"command" => "characters.show", "character" => created}).status == "ok"
    end

    test "without a slug, takes the first free <source>_copy_N" do
      created =
        for _ <- 1..2 do
          run(%{"command" => "characters.copy", "character" => "aria"}).data.created
        end

      assert created == ["aria_copy_1", "aria_copy_2"]
    end

    test "a null slug means none was given" do
      response = run(%{"command" => "characters.copy", "character" => "aria", "slug" => nil})
      assert response.data.created == "aria_copy_1"
    end

    test "refuses a given slug that is taken" do
      response = run(%{"command" => "characters.copy", "character" => "aria", "slug" => "aria"})
      assert response.message == ~s(a character with slug "aria" already exists)
      assert {:ok, %{name: "Aria Stormwind"}} = Characters.load_character("aria")
    end

    test "refuses an invalid slug" do
      response =
        run(%{"command" => "characters.copy", "character" => "aria", "slug" => "../escape"})

      assert response.message =~ ~s(invalid slug "../escape")
    end

    test "asks for a slug when the source's can't take a _copy_N suffix", %{
      character: character
    } do
      long = String.duplicate("a", 195)
      :ok = Characters.save_character(%{character | metadata: %{character.metadata | slug: long}})

      response = run(%{"command" => "characters.copy", "character" => long})

      assert response.message ==
               ~s(can't derive a slug for the copy from "#{long}"; ) <>
                 "give one: characters copy #{long} <new_slug>"
    end

    test "names a nameless or blank-named character's copy after its slug", %{
      character: character
    } do
      for name <- [nil, "", "  "] do
        :ok = Characters.save_character(%{character | name: name}, true)
        response = run(%{"command" => "characters.copy", "character" => "aria"})
        assert response.data.name == "aria (copy)"
      end
    end

    test "refuses an unknown or impossible source" do
      for source <- ["nobody", "../aria"] do
        response = run(%{"command" => "characters.copy", "character" => source})
        assert response.message == "character not found: #{inspect(source)}"
      end
    end

    test "refuses a source whose saved data can't be read" do
      File.write!(Path.join(ExTTRPGDev.Globals.characters_path(), "broken.json"), "nope")
      response = run(%{"command" => "characters.copy", "character" => "broken"})
      assert response.message =~ ~s(cannot copy character "broken": its saved data can't be read)
    end

    test "rejects a slug that isn't a string" do
      response = run(%{"command" => "characters.copy", "character" => "aria", "slug" => 7})
      assert response.status == "error"
      assert Characters.list_characters() == {:ok, ["aria"]}
    end
  end

  # ── saved character commands ──────────────────────────────────────────────────

  describe "saved character commands" do
    setup do
      {gen_response, state1} =
        Server.handle_command(
          %{"command" => "characters.gen", "system" => "dnd_5e_srd"},
          @initial_state
        )

      assert gen_response.status == "ok"

      {save_response, _state2} =
        Server.handle_command(
          %{"command" => "characters.save", "temp_id" => gen_response.data.temp_id},
          state1
        )

      assert save_response.status == "ok"
      slug = save_response.data.slug
      on_exit(fn -> Characters.delete_character(slug) end)

      %{slug: slug}
    end

    test "characters.choices returns pending choices list", %{slug: slug} do
      data = run(%{"command" => "characters.choices", "character" => slug}).data
      assert is_list(data.pending_choices)
    end

    test "characters.inventory returns inventory list", %{slug: slug} do
      data = run(%{"command" => "characters.inventory", "character" => slug}).data
      assert is_list(data.inventory)
    end

    test "characters.award applies experience and returns choices", %{slug: slug} do
      data =
        run(%{
          "command" => "characters.award",
          "character" => slug,
          "award" => "experience_points",
          "value" => 100
        }).data

      assert is_list(data.pending_choices)
    end

    test "characters.award with level_up awards xp to reach next level", %{slug: slug} do
      data =
        run(%{
          "command" => "characters.award",
          "character" => slug,
          "award" => "level_up"
        }).data

      assert is_list(data.pending_choices)
      assert is_integer(data.awarded_xp)
      assert data.awarded_xp > 0
    end

    test "characters.random_resolve resolves all pending choices and returns resolutions",
         %{slug: slug} do
      # Award enough XP to reach level 2 so HP becomes pending
      run(%{
        "command" => "characters.award",
        "character" => slug,
        "award" => "experience_points",
        "value" => 300
      })

      data = run(%{"command" => "characters.random_resolve", "character" => slug}).data

      assert is_list(data.resolutions)
      assert data.resolutions != []
      assert is_list(data.character_lists)
    end

    test "characters.roll returns concept name and dice result", %{slug: slug} do
      data =
        run(%{
          "command" => "characters.roll",
          "character" => slug,
          "type" => "skill",
          "concept" => "acrobatics"
        }).data

      assert data.concept_name == "Acrobatics"
      assert is_list(data.rolls)
      assert is_integer(data.total)
    end

    test "commands error for unknown characters" do
      slugless = fn cmd -> run(Map.put(cmd, "character", "no-such")).status end

      assert slugless.(%{"command" => "characters.choices"}) == "error"
      assert slugless.(%{"command" => "characters.inventory"}) == "error"
      assert slugless.(%{"command" => "characters.show"}) == "error"
    end

    test "characters.resolve_choice for a sub-choice records decision and returns choices",
         %{slug: slug} do
      # 6500 XP = level 5; every class has ASI at level 4, so 1 slot is always pending
      run(%{
        "command" => "characters.award",
        "character" => slug,
        "award" => "experience_points",
        "value" => 6500
      })

      choices_data = run(%{"command" => "characters.choices", "character" => slug}).data
      asi = Enum.find(choices_data.pending_choices, &(&1[:id] == "asi_or_feat"))
      assert asi != nil, "expected asi_or_feat to be pending at level 5"

      run(%{
        "command" => "characters.resolve_choice",
        "character" => slug,
        "progression" => "asi_or_feat",
        "selection" => "ability_score_improvement"
      })

      updated = run(%{"command" => "characters.choices", "character" => slug}).data
      sub = Enum.filter(updated.pending_choices, &Map.has_key?(&1, :scope_type))
      point_1 = Enum.find(sub, &(&1[:id] == "asi_point_1"))
      assert point_1[:scope_type] == "feat"
      assert point_1[:scope_id] == "ability_score_improvement"

      first_option = hd(point_1[:options])[:id]

      data =
        run(%{
          "command" => "characters.resolve_choice",
          "character" => slug,
          "scope_type" => "feat",
          "scope_id" => "ability_score_improvement",
          "choice" => "asi_point_1",
          "selection" => first_option
        }).data

      assert is_list(data.pending_choices)
    end

    test "characters.resolve_choice sub-choice errors for unknown choice", %{slug: slug} do
      assert "error" ==
               run(%{
                 "command" => "characters.resolve_choice",
                 "character" => slug,
                 "scope_type" => "feat",
                 "scope_id" => "ability_score_improvement",
                 "choice" => "nonexistent",
                 "selection" => "strength"
               }).status
    end

    test "characters.award errors for unknown award", %{slug: slug} do
      assert "error" ==
               run(%{
                 "command" => "characters.award",
                 "character" => slug,
                 "award" => "nonexistent",
                 "value" => 1
               }).status
    end

    test "characters.award without value errors for an award that requires an explicit value",
         %{slug: slug} do
      assert "error" ==
               run(%{
                 "command" => "characters.award",
                 "character" => slug,
                 "award" => "experience_points"
               }).status
    end
  end

  # ── character builder ─────────────────────────────────────────────────────────

  describe "characters build flow" do
    setup do
      {resp, state} =
        Server.handle_command(
          %{
            "command" => "characters.build_start",
            "system" => "dnd_5e_srd",
            "name" => "Aria Test"
          },
          @initial_state
        )

      assert resp.status == "ok"
      %{temp_id: resp.data.temp_id, state: state}
    end

    test "build_start returns temp_id and ordered building_choices", %{temp_id: temp_id} do
      assert is_binary(temp_id)
    end

    test "build_start building_choices include race, background, class" do
      data =
        run(%{"command" => "characters.build_start", "system" => "dnd_5e_srd", "name" => "X"}).data

      types = Enum.map(data.building_choices, & &1.concept_type)
      assert "race" in types
      assert "class" in types
      assert "background" in types
    end

    test "build_select adds root decision and returns sub_choices", %{
      state: state,
      temp_id: temp_id
    } do
      {resp, _} =
        Server.handle_command(
          %{
            "command" => "characters.build_select",
            "temp_id" => temp_id,
            "concept_type" => "race",
            "concept_id" => "human"
          },
          state
        )

      assert resp.status == "ok"
      assert is_list(resp.data.sub_choices)
    end

    test "build_resolve_sub applies decision and returns remaining sub_choices",
         %{state: state, temp_id: temp_id} do
      {select_resp, state2} =
        Server.handle_command(
          %{
            "command" => "characters.build_select",
            "temp_id" => temp_id,
            "concept_type" => "race",
            "concept_id" => "human"
          },
          state
        )

      assert select_resp.status == "ok"
      sub = hd(select_resp.data.sub_choices)

      first_option = hd(sub.options).id

      {resolve_resp, _} =
        Server.handle_command(
          %{
            "command" => "characters.build_resolve_sub",
            "temp_id" => temp_id,
            "scope_type" => sub.scope_type,
            "scope_id" => sub.scope_id,
            "choice" => sub.id,
            "selection" => first_option
          },
          state2
        )

      assert resolve_resp.status == "ok"
      assert is_list(resolve_resp.data.sub_choices)
    end

    test "build_finish saves character and returns slug with pending_choices",
         %{state: state, temp_id: temp_id} do
      {resp, _} =
        Server.handle_command(
          %{"command" => "characters.build_finish", "temp_id" => temp_id},
          state
        )

      assert resp.status == "ok"
      assert is_binary(resp.data.slug)
      assert is_list(resp.data.pending_choices)
      on_exit(fn -> Characters.delete_character(resp.data.slug) end)
    end

    test "build_start errors for unknown system" do
      {resp, _} =
        Server.handle_command(
          %{"command" => "characters.build_start", "system" => "nonexistent", "name" => "X"},
          @initial_state
        )

      assert resp.status == "error"
    end

    test "build_start refuses a name with no letters or digits, before any choices" do
      {resp, state} =
        Server.handle_command(
          %{"command" => "characters.build_start", "system" => "dnd_5e_srd", "name" => "!!!"},
          @initial_state
        )

      assert resp.status == "error"
      assert resp.message =~ "at least one letter or digit"
      assert state.pending == %{}
    end
  end

  # ── resolve_choice scoped sub-choice validation ───────────────────────────────

  describe "characters.resolve_choice scoped validation" do
    setup do
      # Build a Cleric so class/cleric sub-choices exist deterministically and
      # start unresolved (the build flow does not auto-resolve sub-choices).
      {start_resp, state1} =
        Server.handle_command(
          %{"command" => "characters.build_start", "system" => "dnd_5e_srd", "name" => "Vala"},
          @initial_state
        )

      temp_id = start_resp.data.temp_id

      state4 =
        [{"class", "cleric"}, {"race", "human"}, {"background", "soldier"}]
        |> Enum.reduce(state1, fn {type, id}, state ->
          {resp, next_state} =
            Server.handle_command(
              %{
                "command" => "characters.build_select",
                "temp_id" => temp_id,
                "concept_type" => type,
                "concept_id" => id
              },
              state
            )

          assert resp.status == "ok"
          next_state
        end)

      {finish_resp, _} =
        Server.handle_command(
          %{"command" => "characters.build_finish", "temp_id" => temp_id},
          state4
        )

      assert finish_resp.status == "ok"
      slug = finish_resp.data.slug
      on_exit(fn -> Characters.delete_character(slug) end)

      %{slug: slug}
    end

    defp resolve_cleric_skill(slug, choice, selection) do
      run(%{
        "command" => "characters.resolve_choice",
        "character" => slug,
        "scope_type" => "class",
        "scope_id" => "cleric",
        "choice" => choice,
        "selection" => selection
      }).status
    end

    test "rejects a selection outside the choice's options whitelist", %{slug: slug} do
      # cleric skill_proficiency_1 whitelists 5 skills; athletics is a valid
      # skill concept but not among them
      assert resolve_cleric_skill(slug, "skill_proficiency_1", "athletics") == "error"
    end

    test "rejects an already-chosen selection for a same-type sibling choice", %{slug: slug} do
      assert resolve_cleric_skill(slug, "skill_proficiency_1", "history") == "ok"
      # same selection for the sibling same-type choice must be rejected...
      assert resolve_cleric_skill(slug, "skill_proficiency_2", "history") == "error"
      # ...while a different whitelisted selection is still accepted
      assert resolve_cleric_skill(slug, "skill_proficiency_2", "insight") == "ok"
    end
  end

  # ── resolve_choice spell inventory integration ────────────────────────────────

  describe "characters.resolve_choice spell inventory" do
    setup do
      # Build a Wizard character so the class is known and deterministic.
      # build_finish does not require all sub-choices to be resolved, so we
      # can skip language/skill sub-choices and rely on pending_choice_slots
      # for the spell progressions.
      {start_resp, state1} =
        Server.handle_command(
          %{"command" => "characters.build_start", "system" => "dnd_5e_srd", "name" => "Aria"},
          @initial_state
        )

      assert start_resp.status == "ok"
      temp_id = start_resp.data.temp_id

      {_, state2} =
        Server.handle_command(
          %{
            "command" => "characters.build_select",
            "temp_id" => temp_id,
            "concept_type" => "class",
            "concept_id" => "wizard"
          },
          state1
        )

      {_, state3} =
        Server.handle_command(
          %{
            "command" => "characters.build_select",
            "temp_id" => temp_id,
            "concept_type" => "race",
            "concept_id" => "human"
          },
          state2
        )

      {_, state4} =
        Server.handle_command(
          %{
            "command" => "characters.build_select",
            "temp_id" => temp_id,
            "concept_type" => "background",
            "concept_id" => "soldier"
          },
          state3
        )

      {finish_resp, _} =
        Server.handle_command(
          %{"command" => "characters.build_finish", "temp_id" => temp_id},
          state4
        )

      assert finish_resp.status == "ok"
      slug = finish_resp.data.slug
      on_exit(fn -> Characters.delete_character(slug) end)

      %{slug: slug, pending_choices: finish_resp.data.pending_choices}
    end

    test "resolving a cantrip adds the spell to inventory with prepared: true",
         %{slug: slug, pending_choices: pending_choices} do
      cantrip = Enum.find(pending_choices, &(&1[:id] == "cantrips"))
      assert cantrip != nil, "expected cantrips pending choice for Wizard"

      spell_id = hd(cantrip[:options])[:id]

      resp =
        run(%{
          "command" => "characters.resolve_choice",
          "character" => slug,
          "progression" => "cantrips",
          "selection" => spell_id
        })

      assert resp.status == "ok"

      inventory = run(%{"command" => "characters.inventory", "character" => slug}).data.inventory
      item = Enum.find(inventory, &(&1[:concept_id] == spell_id))
      assert item != nil, "expected #{spell_id} in inventory after resolving cantrip"
      assert item[:fields]["prepared"] == true
    end

    test "resolving a spells_known choice adds the spell to inventory with prepared: false",
         %{slug: slug, pending_choices: pending_choices} do
      spells_known = Enum.find(pending_choices, &(&1[:id] == "spells_known"))
      assert spells_known != nil, "expected spells_known pending choice for Wizard"

      spell_id = hd(spells_known[:options])[:id]

      resp =
        run(%{
          "command" => "characters.resolve_choice",
          "character" => slug,
          "progression" => "spells_known",
          "selection" => spell_id
        })

      assert resp.status == "ok"

      inventory = run(%{"command" => "characters.inventory", "character" => slug}).data.inventory
      item = Enum.find(inventory, &(&1[:concept_id] == spell_id))
      assert item != nil, "expected #{spell_id} in inventory after resolving spells_known"
      assert item[:fields]["prepared"] == false
    end
  end

  # ── error handling ────────────────────────────────────────────────────────────

  describe "multiclassed characters" do
    alias ExTTRPGDev.Characters.{Character, Decision}
    alias ExTTRPGDev.CLI.Serializer
    alias ExTTRPGDev.RuleSystem.Effect

    # wizard 1 / rogue 1
    defp wizard_rogue(system) do
      wizard = %Decision{scope: nil, choice: "class", selection: "wizard"}
      xp = %Effect{target: {"character_trait", "experience_points", "total"}, value: 300}

      %{Character.gen_character!(system, [wizard]) | effects: [xp], level_classes: ["rogue"]}
    end

    defp list_items(data, label),
      do: Enum.find_value(data.character_lists, [], &(&1.label == label && &1.items))

    test "the sheet shows a multiclassed class's reduced proficiencies" do
      system = RuleSystems.load_system!("dnd_5e_srd")
      data = Serializer.serialize_character(system, wizard_rogue(system), "x", :default)

      assert "Light Armor" in list_items(data, "Armor Proficiencies")
      assert "Thieves' Tools" in list_items(data, "Tool Proficiencies")
      refute "Rapier" in list_items(data, "Weapon Proficiencies")
    end

    test "the sheet shows a multiclassed class's values" do
      system = RuleSystems.load_system!("dnd_5e_srd")
      data = Serializer.serialize_character(system, wizard_rogue(system), "x", :default)

      class_concepts =
        data.concept_types
        |> Enum.filter(&(&1.id == "class"))
        |> Enum.flat_map(& &1.concepts)
        |> Enum.map(& &1.id)

      assert "rogue" in class_concepts
    end
  end

  describe "error handling" do
    test "unknown command returns error" do
      assert run(%{"command" => "nonexistent"}).status == "error"
    end

    test "missing command field returns error" do
      assert run(%{"not_a_command" => "x"}).status == "error"
    end

    test "characters.save with unknown temp_id returns error" do
      assert run(%{"command" => "characters.save", "temp_id" => "999"}).status == "error"
    end
  end

  # ── response encoding ────────────────────────────────────────────────────────

  describe "encode_response/1" do
    test "encodes a normal response as-is" do
      json = Server.encode_response(%{status: "ok", data: %{}})
      assert Jason.decode!(json) == %{"status" => "ok", "data" => %{}}
    end

    test "falls back to an error response instead of raising on unencodable data" do
      json = Server.encode_response(%{status: "ok", data: %{bad: {1, 2}}})

      assert %{"status" => "error", "message" => message} = Jason.decode!(json)
      assert message =~ "not JSON-encodable"
    end
  end
end
