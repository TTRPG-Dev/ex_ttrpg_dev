defmodule ExTTRPGDev.CLI.Server.Handlers.Systems do
  @moduledoc """
  Handles the `systems.*` commands: listing, inspecting, creating, copying
  and deleting rule systems, and declaring concept types in them.
  """

  alias ExTTRPGDev.CLI.Serializer
  alias ExTTRPGDev.Globals
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.RuleSystems.Dependents

  defguardp is_optional_string(value) when is_binary(value) or is_nil(value)

  def handle(%{"command" => "systems.list"}, state) do
    {:ok, %{systems: RuleSystems.list_systems()}, state}
  end

  def handle(%{"command" => "systems.show", "system" => slug} = cmd, state) do
    concept_type = Map.get(cmd, "concept_type")
    concept_id = Map.get(cmd, "concept_id")

    system = RuleSystems.load_system!(slug)

    data =
      cond do
        concept_id != nil ->
          meta = system.concept_metadata[{concept_type, concept_id}] || %{}
          %{id: concept_id, concept_type: concept_type, fields: meta}

        concept_type != nil ->
          Serializer.serialize_concepts(system, concept_type)

        true ->
          Serializer.serialize_system(system)
      end

    {:ok, data, state}
  end

  # Every field but "command" goes to the library as [module] metadata, so
  # its validation (required name, known keys) is the single source of
  # truth for what can be given.
  def handle(%{"command" => "systems.create"} = cmd, state) do
    fields = Map.delete(cmd, "command")

    case RuleSystems.create_system(fields) do
      # The engine always uses the default filesystem store, where a new
      # (local) system lives flat at {root}/{slug}.
      {:ok, slug} ->
        path = Path.join([Globals.local_system_configs_path(), slug, "module.toml"])
        {:ok, %{created: slug, version: created_version(slug), path: path}, state}

      {:error, reason} ->
        {:error, create_error_message(fields, reason)}
    end
  end

  # Without a "slug" (or with null, as create treats nil fields), the copy
  # takes the first free <source>_copy_N. Any other non-string "slug"
  # matches neither clause, so it's refused as invalid arguments rather
  # than reaching the library.
  def handle(%{"command" => "systems.copy", "system" => source, "slug" => slug}, state)
      when is_binary(source) and is_optional_string(slug),
      do: copy(source, slug, state)

  def handle(%{"command" => "systems.copy", "system" => source} = cmd, state)
      when is_binary(source) and not is_map_key(cmd, "slug"),
      do: copy(source, nil, state)

  def handle(%{"command" => "systems.delete", "system" => slug}, state) do
    case RuleSystems.delete_system(slug) do
      # The engine always uses the default filesystem store, where a
      # deletable (local) system lives flat at {root}/{slug}.
      :ok ->
        {:ok, %{deleted: slug, path: Path.join(Globals.local_system_configs_path(), slug)}, state}

      {:error, reason} ->
        {:error, delete_error_message(slug, reason)}
    end
  end

  # As with systems.create, every field but "command" and "system" goes to
  # the library, which decides what a concept type may have.
  def handle(%{"command" => "systems.concept_type.add", "system" => slug} = cmd, state)
      when is_binary(slug) do
    fields = Map.drop(cmd, ["command", "system"])

    case RuleSystems.add_concept_type(slug, fields) do
      # The engine always uses the default filesystem store, where a
      # modifiable (local) system lives flat at {root}/{slug}.
      {:ok, id} ->
        path = Path.join([Globals.local_system_configs_path(), slug, "module.toml"])
        {:ok, %{added: id, system: slug, path: path}, state}

      {:error, reason} ->
        {:error, add_concept_type_error_message(slug, fields, reason)}
    end
  end

  def handle(%{"command" => cmd}, _state),
    do: {:error, "invalid arguments for command: #{inspect(cmd)}"}

  # The version the library stored, which may be its default rather than
  # anything the user gave, so the CLI never has to know that default. A
  # created system has exactly one installed entry. nil only if the store
  # can't be listed right after the create succeeded.
  defp created_version(slug) do
    case RuleSystems.fetch_installed_systems() do
      {:ok, entries} -> Enum.find_value(entries, &(&1.slug == slug and &1.version))
      {:error, _} -> nil
    end
  end

  defp create_error_message(_fields, {tag, _} = reason) when tag in [:slug_taken, :slug_occupied],
    do: new_slug_error_message(reason)

  defp create_error_message(fields, {:invalid_slug, ""}),
    do:
      "can't derive a slug from name #{inspect(fields["name"])}: " <>
        "it needs at least one letter or digit"

  defp create_error_message(fields, {:slug_too_long, slug, max_bytes}) do
    what = if Map.has_key?(fields, "slug"), do: "slug", else: "name"

    "the #{what} is too long: its slug would be #{byte_size(slug)} bytes, " <>
      "and the limit is #{max_bytes}. Try a shorter #{what}."
  end

  defp create_error_message(_fields, {:invalid_slug, _} = reason),
    do: new_slug_error_message(reason)

  defp create_error_message(_fields, {:invalid_module, {:missing_required_key, key}}),
    do: "#{key} is required"

  defp create_error_message(_fields, {:invalid_module, {:unknown_key, key}}),
    do: "unknown rule system field: #{inspect(key)}"

  defp create_error_message(_fields, {:invalid_module, {:not_a_string, key, _}}),
    do: "rule system field #{inspect(key)} must be a string"

  defp create_error_message(_fields, reason),
    do: "cannot create rule system: #{inspect(reason)}"

  # Why a slug for a new (created or copied) system was refused, for the
  # reasons that don't depend on what the user typed to get that slug.
  defp new_slug_error_message({:slug_taken, slug}),
    do: "a rule system with slug #{inspect(slug)} already exists"

  # The engine always uses the filesystem store, so the slug is occupied
  # at (or, on a case-insensitive filesystem, by a differently cased name
  # matching) the directory a new system would be written to. The message
  # says only what's certain: something is there and isn't listed as a
  # system. It may be empty, lack a module.toml, or be a real system under
  # a name that isn't a valid slug (e.g. "Homebrew/" on macOS).
  defp new_slug_error_message({:slug_occupied, slug}) do
    dir = Path.join(Globals.local_system_configs_path(), slug)

    "something already exists at #{dir} (or a differently cased name) " <>
      "that isn't a listed rule system, e.g. a directory with no module.toml. " <>
      "Remove or rename it, or choose another name."
  end

  defp new_slug_error_message({:invalid_slug, slug}),
    do: "invalid slug #{inspect(slug)}: use lowercase letters, digits and single underscores"

  # The source's name is read first, which also reports an unknown source
  # before any slug is tried. Only its module.toml is read, not loaded as a
  # whole: copying a system whose content doesn't load (to fix it in the
  # copy) must work, since clone_system/3 doesn't need it to load either.
  defp copy(source, new_slug, state) do
    with {:ok, name} <- copy_name(source),
         {:ok, slug} <- copy_to(source, new_slug, name) do
      path = Path.join(Globals.local_system_configs_path(), slug)
      {:ok, %{copied: source, created: slug, name: name, path: path}, state}
    else
      {:error, reason} -> {:error, copy_error_message(source, new_slug, reason)}
    end
  end

  # A module.toml that doesn't parse has no name to trust, so the copy is
  # named after the slug instead; the copy is still worth making.
  defp copy_name(source) do
    case RuleSystems.fetch_module(source) do
      {:ok, module} -> {:ok, "#{module.name} (copy)"}
      {:error, {:module_parse_error, _}} -> {:ok, "#{source} (copy)"}
      error -> error
    end
  end

  # The slugs are listed once and the listed ones skipped without a clone
  # attempt, since each attempt lists and resolves again. clone_system/3
  # still has the last word: a slug occupied by something that isn't a
  # system isn't listed, and one may be taken after the listing.
  defp copy_to(source, nil, name) do
    with {:ok, slugs} <- RuleSystems.fetch_systems() do
      copy_to_next_free(source, name, 1, MapSet.new(slugs))
    end
  end

  defp copy_to(source, slug, name), do: RuleSystems.clone_system(source, slug, name: name)

  # Each refused candidate is a system or something occupying its
  # directory, so this ends after at most that many tries.
  defp copy_to_next_free(source, name, n, listed) do
    slug = "#{source}_copy_#{n}"

    if MapSet.member?(listed, slug),
      do: copy_to_next_free(source, name, n + 1, listed),
      else: try_copy_to(source, name, n, listed)
  end

  defp try_copy_to(source, name, n, listed) do
    case RuleSystems.clone_system(source, "#{source}_copy_#{n}", name: name) do
      {:error, {tag, _}} when tag in [:slug_taken, :slug_occupied] ->
        copy_to_next_free(source, name, n + 1, listed)

      result ->
        result
    end
  end

  defp copy_error_message(source, _new_slug, {:not_configured, _}),
    do: "rule system not found: #{inspect(source)}"

  defp copy_error_message(_source, slug, {tag, _} = reason)
       when slug != nil and tag in [:slug_taken, :slug_occupied, :invalid_slug],
       do: new_slug_error_message(reason)

  defp copy_error_message(_source, slug, {:slug_too_long, _, max_bytes}) when slug != nil,
    do: "the slug is too long: it's #{byte_size(slug)} bytes, and the limit is #{max_bytes}"

  # Only reachable without a given slug, when the source's own slug can't
  # take a _copy_N suffix: it's an older slug not in today's form, or it's
  # near the length limit.
  defp copy_error_message(source, nil, reason)
       when elem(reason, 0) in [:invalid_slug, :slug_too_long] do
    "can't derive a slug for the copy from #{inspect(source)}; " <>
      "give one: systems copy #{source} <new_slug>"
  end

  defp copy_error_message(source, _new_slug, reason),
    do: "cannot copy rule system #{inspect(source)}: #{inspect(reason)}"

  defp add_concept_type_error_message(slug, _fields, {:concept_type_exists, id}),
    do: "rule system #{inspect(slug)} already has a concept type #{inspect(id)}"

  defp add_concept_type_error_message(_slug, fields, {:invalid_concept_type_id, ""}),
    do:
      "can't derive a concept type ID from name #{inspect(fields["name"])}: " <>
        "it needs at least one letter or digit"

  defp add_concept_type_error_message(_slug, fields, {:invalid_concept_type_id, id}),
    do:
      "can't use #{inspect(id)} (from name #{inspect(fields["name"])}) as a concept type ID: " <>
        "formulas can only refer to IDs made of ASCII letters, digits and underscores"

  defp add_concept_type_error_message(_slug, _fields, {:invalid_concept_type, reason}) do
    case reason do
      {:missing_required_key, key} -> "#{key} is required"
      {:unknown_key, key} -> "unknown concept type field: #{inspect(key)}"
      {:not_a_string, key, _} -> "concept type field #{inspect(key)} must be a string"
      other -> "invalid concept type: #{inspect(other)}"
    end
  end

  defp add_concept_type_error_message(slug, _fields, {:not_configured, _}),
    do: "rule system not found: #{inspect(slug)}"

  defp add_concept_type_error_message(slug, _fields, {:not_modifiable, _}),
    do:
      "rule system #{inspect(slug)} is not modifiable (bundled systems can't be edited). " <>
        "Copy it first: systems copy #{slug}"

  # The only way adding a type stops a system loading: concept files
  # already used the ID, and were ignored until it was declared.
  defp add_concept_type_error_message(slug, _fields, {:invalid_update, reason}),
    do:
      "cannot add the concept type: rule system #{inspect(slug)} wouldn't load with it " <>
        "(concepts of that type may already exist and be invalid): #{inspect(reason)}"

  defp add_concept_type_error_message(slug, _fields, reason),
    do: "cannot add a concept type to rule system #{inspect(slug)}: #{inspect(reason)}"

  defp delete_error_message(slug, :not_modifiable),
    do: "rule system #{inspect(slug)} is not modifiable (bundled systems can't be deleted)"

  defp delete_error_message(slug, {:not_configured, _}),
    do: "rule system not found: #{inspect(slug)}"

  defp delete_error_message(slug, {:has_dependents, found}) do
    {characters, others} = Enum.split_with(found, &match?({Dependents, _}, &1))

    parts =
      [
        characters != [] &&
          "#{length(characters)} saved character(s) use it: " <>
            Enum.map_join(characters, ", ", &elem(&1, 1)),
        others != [] && "also used by: " <> Enum.map_join(others, ", ", &inspect(elem(&1, 1)))
      ]
      |> Enum.filter(& &1)

    "cannot delete rule system #{inspect(slug)}: #{Enum.join(parts, "; ")}. " <>
      "Delete or move what uses it first."
  end

  defp delete_error_message(slug, {:dependents_unavailable, {_, {:unreadable_characters, bad}}}) do
    "cannot delete rule system #{inspect(slug)}: couldn't check which characters use it, " <>
      "because these character files can't be read: " <> Enum.map_join(bad, ", ", &elem(&1, 0))
  end

  defp delete_error_message(slug, reason),
    do: "cannot delete rule system #{inspect(slug)}: #{inspect(reason)}"
end
