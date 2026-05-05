defmodule Arkea.Game.SeedLab.DomainEditor do
  @moduledoc """
  High-impact parameter editor for custom gene domains (UI Phase A —
  domain parameter editing).

  Today every custom domain in the gene designer is built from a fixed
  default codon pattern, so the player can pick the **type** of a
  domain (substrate_binding, catalytic_site, …) but never the
  **specificity** of it (which metabolite, which reaction class, which
  surface-tag class). That makes the chemolithotrophic archetypes
  (acid mine, hydrothermal, …) effectively unreachable: their pools
  are dominated by Fe²⁺/H₂S/SO₄²⁻ but the only substrate-binding
  domain available targets glucose by default.

  This module exposes the **5 highest-impact parameters** as
  player-editable, while leaving the other 7+ parameters per domain
  to the codon-derived defaults:

  | Domain type | Editable param | Choices |
  |---|---|---|
  | `:substrate_binding` | `target_metabolite_id` | 13 canonical metabolites (glucose, acetate, …, iron) |
  | `:catalytic_site` | `reaction_class` | 6 reaction classes (hydrolysis, oxidation, …) |
  | `:ligand_sensor` | `sensed_metabolite_id` | same 13 metabolites |
  | `:surface_tag` | `tag_class` | 3 tag classes (pilus_receptor, phage_receptor, surface_antigen) |
  | `:repair_fidelity` | `repair_class` | 3 repair classes (mismatch, proofreading, error_prone) |

  The override technique: every editable parameter is encoded by the
  first one to three parameter codons of the domain (see
  `Arkea.Genome.Domain.type_params/4` for the canonical decoding).
  Overriding those codons is sufficient to pin the corresponding
  param to the player choice without disturbing the others (kcat,
  km, hydrophobicity, …) — they keep flowing from the rest of the
  20-codon block.

  Pure: no I/O. Used by `Arkea.Game.SeedLab.template_domain/2`.
  """

  alias Arkea.Sim.Metabolism

  # Canonical lists, mirrored from `Arkea.Genome.Domain` so we don't
  # need to import that module at compile time. If the upstream lists
  # change, the test in `test/arkea/game/seed_lab/domain_editor_test.exs`
  # asserts the lengths still match.
  @reaction_classes [:hydrolysis, :oxidation, :reduction, :isomerization, :ligation, :lyase]
  @tag_classes [:pilus_receptor, :phage_receptor, :surface_antigen]
  @repair_classes [:mismatch, :proofreading, :error_prone]

  @type domain_id :: String.t()
  @type param_choice :: %{
          key: String.t(),
          label: String.t(),
          options: [{String.t(), String.t()}]
        }

  @doc """
  List of parameters editable for the given domain id, with the
  options each choice exposes. Returns `[]` when no params are exposed
  for editing (most domains).
  """
  @spec editable_params(domain_id()) :: [param_choice()]
  def editable_params(type_id) when is_binary(type_id) do
    case type_id do
      "substrate_binding" ->
        [
          %{
            key: "target_metabolite_id",
            label: "Target metabolite",
            options: metabolite_options()
          }
        ]

      "catalytic_site" ->
        [
          %{
            key: "reaction_class",
            label: "Reaction class",
            options: enum_options(@reaction_classes)
          }
        ]

      "ligand_sensor" ->
        [
          %{
            key: "sensed_metabolite_id",
            label: "Sensed metabolite",
            options: metabolite_options()
          }
        ]

      "surface_tag" ->
        [
          %{
            key: "tag_class",
            label: "Tag class",
            options: enum_options(@tag_classes)
          }
        ]

      "repair_fidelity" ->
        [
          %{
            key: "repair_class",
            label: "Repair class",
            options: enum_options(@repair_classes)
          }
        ]

      _ ->
        []
    end
  end

  @doc "True when the domain type exposes any editable parameters."
  @spec editable?(domain_id()) :: boolean()
  def editable?(type_id), do: editable_params(type_id) != []

  @doc """
  Override the default codon block of a domain so the editable
  parameters resolve to the player's choices when the simulation
  re-derives the params via `Domain.type_params/4`.

  Inputs:
  - `type_id` — string id from the palette (`"substrate_binding"`, …).
  - `default_codons` — the 20-codon parameter list produced by the
    fixed templates in `SeedLab`.
  - `params` — the user choices, stringified-keys map (the wire shape
    arriving from the LiveView form), e.g.
    `%{"target_metabolite_id" => 11}`.

  Returns the new 20-codon list. Pure.
  """
  @spec override_codons(domain_id(), [non_neg_integer()], map()) :: [non_neg_integer()]
  def override_codons(type_id, codons, params) when is_list(codons) and is_map(params) do
    case type_id do
      "substrate_binding" ->
        case parse_int(params["target_metabolite_id"]) do
          nil -> codons
          mid -> List.replace_at(codons, 0, rem(mid, 13))
        end

      "ligand_sensor" ->
        case parse_int(params["sensed_metabolite_id"]) do
          nil -> codons
          mid -> List.replace_at(codons, 0, rem(mid, 13))
        end

      "catalytic_site" ->
        # First three codons sum mod 6 = reaction_class index. We
        # encode the choice as `[idx, 0, 0]` and keep the rest of the
        # block (which controls kcat / cofactor / signal_key) intact.
        case enum_index(@reaction_classes, params["reaction_class"]) do
          nil ->
            codons

          idx ->
            codons
            |> List.replace_at(0, idx)
            |> List.replace_at(1, 0)
            |> List.replace_at(2, 0)
        end

      "surface_tag" ->
        case enum_index(@tag_classes, params["tag_class"]) do
          nil -> codons
          idx -> List.replace_at(codons, 0, rem(idx, 3))
        end

      "repair_fidelity" ->
        case enum_index(@repair_classes, params["repair_class"]) do
          nil -> codons
          idx -> List.replace_at(codons, 0, rem(idx, 3))
        end

      _ ->
        codons
    end
  end

  @doc "List of {value, label} options for the 13 canonical metabolites."
  @spec metabolite_options() :: [{String.t(), String.t()}]
  def metabolite_options do
    Metabolism.canonical_metabolites()
    |> Enum.with_index()
    |> Enum.map(fn {atom, idx} ->
      {Integer.to_string(idx), Atom.to_string(atom)}
    end)
  end

  defp enum_options(atoms) do
    Enum.map(atoms, fn a ->
      s = Atom.to_string(a)
      {s, s}
    end)
  end

  defp enum_index(atoms, value) when is_binary(value) do
    Enum.find_index(atoms, fn a -> Atom.to_string(a) == value end)
  end

  defp enum_index(_atoms, _other), do: nil

  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int(_), do: nil

  @doc "Sanitize a stringified-keys params map to keep only fields recognised by the editor for the given domain type."
  @spec sanitize(domain_id(), map()) :: map()
  def sanitize(type_id, params) when is_map(params) do
    keys = editable_params(type_id) |> Enum.map(& &1.key)
    Map.take(params, keys)
  end

  def sanitize(_type_id, _other), do: %{}
end
