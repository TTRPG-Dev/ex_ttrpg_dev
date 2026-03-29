defmodule ExTTRPGDev.CLI.ServerTest do
  use ExUnit.Case, async: false

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.CLI.Server

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
      assert data.version == "1.0.0"
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
  end

  # ── error handling ────────────────────────────────────────────────────────────

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
end
