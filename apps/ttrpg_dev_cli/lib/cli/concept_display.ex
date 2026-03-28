defmodule ExTTRPGDev.CLI.ConceptDisplay do
  @moduledoc """
  Renders concept metadata into a display string for the CLI.

  Three modes are supported:

  - `:succinct` — name only (the `"name"` field in the metadata map).
  - `:default` — uses the system-defined display template when one is provided;
    falls back to `:succinct` when no template is available.
  - `:verbose` — all metadata fields formatted as `key: value` pairs on one line,
    with the name first.

  Templates are plain strings with two substitution constructs:

  - `{{field}}` — replaced with the string value of `fields["field"]`, or `""` when absent.
  - `{{?field:text}}` — replaced with `text` when `fields["field"]` is truthy
    (non-nil, non-false, non-zero, non-empty-string); replaced with `""` otherwise.

  Example template:

      "{{name}}: Level {{level}}, {{school}} ({{?verbal:V}}{{?somatic:S}}{{?material:M}})"

  With `%{"name" => "Fire Bolt", "level" => 1, "school" => "evocation",
  "verbal" => true, "somatic" => true, "material" => false}` in `:default` mode
  this renders as `"Fire Bolt: Level 1, evocation (VS)"`.
  """

  @doc """
  Renders `fields` into a display string according to `mode`.

  `template` is the system-defined template string (may be `nil`).
  `fields` is the concept's raw metadata map (string keys).
  `mode` is `:succinct`, `:default`, or `:verbose`.
  """
  @spec render(String.t() | nil, map(), :succinct | :default | :verbose) :: String.t()
  def render(_template, fields, :succinct), do: fields["name"] || ""
  def render(nil, fields, :default), do: fields["name"] || ""
  def render(template, fields, :default), do: apply_template(template, fields)
  def render(_template, fields, :verbose), do: format_verbose(fields)

  # --- Helpers ---

  defp apply_template(template, fields) do
    template
    |> replace_conditionals(fields)
    |> replace_substitutions(fields)
  end

  defp replace_conditionals(template, fields) do
    Regex.replace(~r/\{\{\?(\w+):([^}]*)\}\}/, template, fn _, field, text ->
      if truthy?(fields[field]), do: text, else: ""
    end)
  end

  defp replace_substitutions(template, fields) do
    Regex.replace(~r/\{\{(\w+)\}\}/, template, fn _, field ->
      to_string(fields[field] || "")
    end)
  end

  defp format_verbose(fields) do
    name = fields["name"] || ""

    details =
      fields
      |> Map.drop(["name", "hidden"])
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map_join("  ", fn {k, v} -> "#{k}: #{value_to_string(v)}" end)

    if details == "", do: name, else: "#{name}  #{details}"
  end

  defp value_to_string(v) when is_map(v) or is_list(v), do: inspect(v)
  defp value_to_string(v), do: to_string(v)

  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(0), do: false
  defp truthy?(""), do: false
  defp truthy?(_), do: true
end
