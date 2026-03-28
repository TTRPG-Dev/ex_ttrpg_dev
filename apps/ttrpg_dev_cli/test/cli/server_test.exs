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

    test "characters.award errors for unknown award", %{slug: slug} do
      assert "error" ==
               run(%{
                 "command" => "characters.award",
                 "character" => slug,
                 "award" => "nonexistent",
                 "value" => 1
               }).status
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
