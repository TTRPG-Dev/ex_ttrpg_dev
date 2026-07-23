defmodule ExTTRPGDev.Characters.Preparation do
  @moduledoc """
  Preparation-managed inventory: computing a character's preparation state
  (mode, cap, eligible pool, prepared items), activating/preparing items of
  a preparation-managed type, and adding concepts to typed inventories when
  qualifying progressions are resolved.

  Callers should use the delegating functions on `ExTTRPGDev.Characters`
  (e.g. `ExTTRPGDev.Characters.preparation_state/3`); this module hosts the
  implementation.
  """

  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Decision
  alias ExTTRPGDev.Characters.Effects
  alias ExTTRPGDev.Characters.InventoryItem
  alias ExTTRPGDev.RuleSystem.InventoryRules
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  @doc """
  Returns the current preparation state for the given inventory type.

  See `ExTTRPGDev.Characters.preparation_state/3` for documentation.
  """
  def preparation_state(%LoadedSystem{} = system, %Character{} = character, type_id) do
    case InventoryRules.type_config(system.inventory_rules, type_id) do
      nil -> {:error, {:unknown_inventory_type, type_id}}
      %{preparation: nil} -> {:error, {:not_a_preparation_type, type_id}}
      config -> do_preparation_state(system, character, type_id, config)
    end
  end

  @doc """
  Activates or prepares items of the given inventory type for a character.

  See `ExTTRPGDev.Characters.activate/4` for documentation.
  """
  def activate(%LoadedSystem{} = system, %Character{} = character, type_id, item_ids) do
    case InventoryRules.type_config(system.inventory_rules, type_id) do
      nil ->
        {:error, {:unknown_inventory_type, type_id}}

      %{preparation: nil} ->
        {:error, {:not_a_preparation_type, type_id}}

      %{preparation: prep, activation_field: activation_field} ->
        with {:ok, class_key, mode} <- prep_class_and_mode(system, character, prep),
             :ok <- require_prepared_mode_for_activate(mode, prep.activation_mode),
             ctx = prep_context(system, character, class_key, %{type_id: type_id, prep: prep}),
             {:ok, cap} <- ctx.cap,
             {:ok, pool_config} <- ctx.pool_config,
             item_ids = Enum.uniq(item_ids),
             :ok <- validate_eligible_items(item_ids, ctx.eligible),
             :ok <- validate_cap_limit(item_ids, cap) do
          apply_activation(
            character,
            type_id,
            item_ids,
            system.inventory_rules,
            activation_field,
            pool_config,
            ctx.eligible
          )
        end
    end
  end

  @doc """
  Adds a concept to the appropriate typed inventory when a qualifying character
  progression is resolved.

  See `ExTTRPGDev.Characters.add_to_typed_inventory/4` for documentation.
  """
  def add_to_typed_inventory(
        %LoadedSystem{} = system,
        %Character{} = character,
        progression_id,
        concept_id
      ) do
    case InventoryRules.type_for_progression(system.inventory_rules, progression_id) do
      nil ->
        {:ok, character}

      {type_id, prog_config} ->
        type_config = InventoryRules.type_config(system.inventory_rules, type_id)
        activated = resolve_auto_activate(system, character, prog_config, type_config)

        initial_fields =
          if activated and type_config.activation_field,
            do: %{type_config.activation_field => true},
            else: %{}

        case InventoryItem.new(type_id, concept_id, system.inventory_rules, initial_fields) do
          {:ok, item} -> {:ok, %{character | inventory: character.inventory ++ [item]}}
          error -> error
        end
    end
  end

  defp do_preparation_state(system, character, type_id, %{preparation: prep, activation_field: af}) do
    case prep_class_and_mode(system, character, prep) do
      {:error, :no_preparation_class} ->
        {:ok, %{mode: nil}}

      {:ok, class_key, mode} ->
        ctx = prep_context(system, character, class_key, %{type_id: type_id, prep: prep})
        opts = %{prep: prep, af: af, type_id: type_id, mode: mode}
        {:ok, build_prep_state_map(system, character, ctx, opts)}
    end
  end

  # Stage 1 of the shared preparation pipeline: the active class and its
  # preparation mode. Cheap — no DAG evaluation — so activate can reject a
  # wrong mode before any evaluation happens.
  defp prep_class_and_mode(system, character, prep) do
    with {:ok, class_key} <- find_prep_class_for_activate(character, system, prep) do
      {:ok, class_key, get_in(system.concept_metadata, [class_key, prep.mode_field])}
    end
  end

  # Stage 2: everything else both the read path (preparation_state) and the
  # write path (activate) derive — resolved cap, max prepared level, pool
  # config, and the eligible pool. Fallible steps (cap, pool_config) are
  # kept as tagged results so activate can pattern-match errors strictly
  # while preparation_state degrades tolerantly.
  defp prep_context(system, character, {class_type, class_id} = class_key, opts) do
    %{type_id: type_id, prep: prep} = opts
    {_effects, resolved} = Effects.resolved_state(system, character)
    max_level = trunc(resolved[prep.max_level_node] || 0)
    pool_name = get_in(system.concept_metadata, [class_key, prep.pool_field])
    pool_config = fetch_pool_config(prep, pool_name)

    eligible_ctx = %{
      type_id: type_id,
      class_id: class_id,
      max_level: max_level,
      level_field: prep.level_field
    }

    eligible =
      case pool_config do
        {:ok, pc} -> compute_eligible_pool(system, character, pc, eligible_ctx)
        {:error, _} -> []
      end

    %{
      cap: resolve_activation_cap(resolved, class_type, class_id, prep),
      max_level: max_level,
      pool_config: pool_config,
      eligible: eligible
    }
  end

  defp build_prep_state_map(system, character, ctx, opts) do
    %{prep: prep, af: af, type_id: type_id, mode: mode} = opts

    cap =
      case ctx.cap do
        {:ok, c} -> c
        {:error, _} -> nil
      end

    always =
      prep_always_prepared(system, character, %{
        prep: prep,
        max_level: ctx.max_level,
        type_id: type_id
      })

    prepared =
      character.inventory
      |> Enum.filter(&(&1.concept_type == type_id and &1.fields[af] == true))
      |> Enum.map(& &1.concept_id)

    %{
      mode: mode,
      cap: cap,
      eligible: ctx.eligible,
      always_prepared: always,
      prepared: prepared
    }
  end

  defp prep_always_prepared(system, character, ctx) do
    %{prep: prep, max_level: max_level, type_id: type_id} = ctx

    with key when not is_nil(key) <- prep.always_prepared_metadata_key,
         true <- max_level > 0 do
      level_ctx = %{type_id: type_id, level_field: prep.level_field, max_level: max_level}
      active = Effects.active_concepts(character.decisions, system.concept_metadata)

      active
      |> Enum.flat_map(fn {concept_type, concept_id} ->
        meta = Map.get(system.concept_metadata, {concept_type, concept_id}, %{})
        Map.get(meta, key, [])
      end)
      |> filter_within_level(system.concept_metadata, level_ctx)
    else
      _ -> []
    end
  end

  defp filter_within_level(ids, concept_metadata, ctx) do
    Enum.filter(ids, fn id ->
      meta = Map.get(concept_metadata, {ctx.type_id, id}, %{})
      Map.get(meta, ctx.level_field, 0) <= ctx.max_level
    end)
  end

  # --- activate/4 helpers ---

  defp find_prep_class_for_activate(character, system, prep) do
    result =
      Enum.find_value(system.module.character_building_choices, fn %{concept_type: type_id} ->
        find_prep_concept(character.decisions, system.concept_metadata, type_id, prep.mode_field)
      end)

    if result, do: {:ok, result}, else: {:error, :no_preparation_class}
  end

  defp find_prep_concept(decisions, concept_metadata, type_id, mode_field) do
    Enum.find_value(decisions, fn
      %Decision{scope: nil, choice: ^type_id, selection: concept_id} ->
        meta = Map.get(concept_metadata, {type_id, concept_id}, %{})
        if Map.has_key?(meta, mode_field), do: {type_id, concept_id}, else: nil

      _ ->
        nil
    end)
  end

  defp require_prepared_mode_for_activate(mode, mode), do: :ok
  defp require_prepared_mode_for_activate(mode, _), do: {:error, {:mode_not_prepared, mode}}

  defp resolve_activation_cap(resolved, class_type, class_id, prep) do
    case Map.fetch(resolved, {class_type, class_id, prep.cap_field}) do
      {:ok, val} -> {:ok, max(1, trunc(val))}
      :error -> {:error, :no_preparation_cap}
    end
  end

  defp fetch_pool_config(prep, pool_name) when is_binary(pool_name) do
    case Map.fetch(prep.pools, pool_name) do
      {:ok, config} -> {:ok, config}
      :error -> {:error, {:unknown_pool, pool_name}}
    end
  end

  defp fetch_pool_config(_prep, _), do: {:error, :no_pool_configured}

  # ctx: %{type_id, class_id, max_level, level_field}
  defp compute_eligible_pool(system, character, pool_config, ctx) when ctx.max_level > 0 do
    case pool_config.management do
      :add_remove ->
        add_remove_eligible(system.concept_metadata, pool_config, ctx)

      :toggle_field ->
        toggle_field_eligible(character.decisions, system.concept_metadata, pool_config, ctx)
    end
  end

  defp compute_eligible_pool(_system, _character, _pool_config, _ctx), do: []

  defp add_remove_eligible(concept_metadata, pool_config, ctx) do
    %{type_id: type_id, class_id: class_id, max_level: max_level, level_field: level_field} = ctx
    filter_field = pool_config.class_filter_field

    concept_metadata
    |> Enum.filter(fn {{type, _id}, meta} ->
      type == type_id and meta[level_field] in 1..max_level and
        class_id in (meta[filter_field] || [])
    end)
    |> Enum.map(fn {{_type, id}, _} -> id end)
  end

  defp toggle_field_eligible(decisions, concept_metadata, pool_config, ctx) do
    %{type_id: type_id, max_level: max_level, level_field: level_field} = ctx
    scope = {pool_config.scope_type, pool_config.scope_id}
    spellbook_ids = decisions |> Enum.filter(&(&1.scope == scope)) |> MapSet.new(& &1.selection)

    concept_metadata
    |> Enum.filter(fn {{type, id}, meta} ->
      type == type_id and meta[level_field] in 1..max_level and MapSet.member?(spellbook_ids, id)
    end)
    |> Enum.map(fn {{_type, id}, _} -> id end)
  end

  defp validate_eligible_items(item_ids, eligible) do
    eligible_set = MapSet.new(eligible)
    invalid = Enum.reject(item_ids, &MapSet.member?(eligible_set, &1))
    if Enum.empty?(invalid), do: :ok, else: {:error, {:ineligible_items, invalid}}
  end

  defp validate_cap_limit(item_ids, cap) do
    if length(item_ids) <= cap,
      do: :ok,
      else: {:error, {:exceeds_cap, length(item_ids), cap}}
  end

  defp apply_activation(
         character,
         type_id,
         item_ids,
         inv_rules,
         activation_field,
         %{
           management: :add_remove
         },
         eligible
       ) do
    eligible_set = MapSet.new(eligible)

    other_items =
      Enum.reject(character.inventory, fn item ->
        item.concept_type == type_id and MapSet.member?(eligible_set, item.concept_id)
      end)

    result =
      Enum.reduce_while(item_ids, {:ok, []}, fn id, {:ok, acc} ->
        case InventoryItem.new(type_id, id, inv_rules, %{activation_field => true}) do
          {:ok, item} -> {:cont, {:ok, [item | acc]}}
          error -> {:halt, error}
        end
      end)

    case result do
      {:ok, new_items} -> {:ok, %{character | inventory: other_items ++ Enum.reverse(new_items)}}
      error -> error
    end
  end

  defp apply_activation(
         character,
         type_id,
         item_ids,
         _inv_rules,
         activation_field,
         %{
           management: :toggle_field
         },
         eligible
       ) do
    prepared_set = MapSet.new(item_ids)
    eligible_set = MapSet.new(eligible)

    updated_inventory =
      Enum.map(character.inventory, fn item ->
        if item.concept_type == type_id and MapSet.member?(eligible_set, item.concept_id) do
          %{
            item
            | fields:
                Map.put(
                  item.fields,
                  activation_field,
                  MapSet.member?(prepared_set, item.concept_id)
                )
          }
        else
          item
        end
      end)

    {:ok, %{character | inventory: updated_inventory}}
  end

  # --- add_to_typed_inventory/4 helpers ---

  defp resolve_auto_activate(_system, _character, %{auto_activate: true}, _type_config), do: true

  defp resolve_auto_activate(system, character, %{auto_activate: false}, type_config) do
    case type_config && type_config.preparation do
      %{auto_activate_when_field: field, auto_activate_when_value: value}
      when not is_nil(field) ->
        auto_activate_when_met?(system, character, field, value)

      _ ->
        false
    end
  end

  defp auto_activate_when_met?(system, character, field, expected_value) do
    choices = if system.module, do: system.module.character_building_choices, else: []

    Enum.any?(choices, fn %{concept_type: class_type} ->
      Enum.any?(character.decisions, fn
        %Decision{scope: nil, choice: ^class_type, selection: class_id} ->
          meta = Map.get(system.concept_metadata, {class_type, class_id}, %{})
          meta[field] == expected_value

        _ ->
          false
      end)
    end)
  end
end
