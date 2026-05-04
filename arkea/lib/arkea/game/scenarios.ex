defmodule Arkea.Game.Scenarios do
  @moduledoc """
  Curated seed-lab presets (UI Phase G).

  Each scenario is a one-click recipe for a seed: it pre-fills the
  Seed Lab form with a deliberate combination of archetype +
  metabolism / membrane / regulation / mobile-module so the player
  can land in an interesting evolutionary corner without designing
  from scratch.

  The simulation already exposes 8 archetypes, 3 metabolism profiles,
  3 membrane profiles, 3 regulation profiles and 3 mobile modules;
  the goal of this module is *not* to enumerate the combinatorial
  space but to highlight a small handful of stress-tests each
  illustrating a distinct evolutionary phenomenon.
  """

  @scenarios [
    %{
      id: "mutator_vs_steady_lake",
      title: "Mutator vs steady (Oligotrophic lake)",
      summary:
        "Mutator-edge regulation in a low-nutrient lake. Watch DNA-damage scores climb and SOS-driven prophage induction kick in.",
      params: %{
        "seed_name" => "Mutator Edge",
        "starter_archetype" => "oligotrophic_lake",
        "metabolism_profile" => "thrifty",
        "membrane_profile" => "porous",
        "regulation_profile" => "mutator",
        "mobile_module" => "latent_prophage"
      }
    },
    %{
      id: "cross_feeding_pond",
      title: "Cross-feeding bloom (Eutrophic pond)",
      summary:
        "Rich glucose pool + responsive regulation — by-products (acetate, lactate) build up and feed secondary niches. Monitor the metabolite heatmap to see C cycle closure.",
      params: %{
        "seed_name" => "Pond Bloom",
        "starter_archetype" => "eutrophic_pond",
        "metabolism_profile" => "bloom",
        "membrane_profile" => "porous",
        "regulation_profile" => "responsive",
        "mobile_module" => "conjugative_plasmid"
      }
    },
    %{
      id: "saline_gradient_estuary",
      title: "Halotolerant estuary",
      summary:
        "Tidal salinity gradient with a salinity-tuned envelope. Compare survival across the freshwater / mixing-zone / marine layers.",
      params: %{
        "seed_name" => "Estuary Halophile",
        "starter_archetype" => "saline_estuary",
        "metabolism_profile" => "balanced",
        "membrane_profile" => "salinity_tuned",
        "regulation_profile" => "responsive",
        "mobile_module" => "none"
      }
    },
    %{
      id: "acidophile_mine",
      title: "Acidophile iron oxidiser",
      summary:
        "pH ≈ 3 acid mine drainage, fortified envelope, balanced metabolism. Iron-cycling niche for chemolithotrophs.",
      params: %{
        "seed_name" => "Acidophile Pioneer",
        "starter_archetype" => "acid_mine_drainage",
        "metabolism_profile" => "balanced",
        "membrane_profile" => "fortified",
        "regulation_profile" => "steady",
        "mobile_module" => "none"
      }
    }
  ]

  @doc "Full list of curated scenarios."
  @spec list() :: [map()]
  def list, do: @scenarios

  @doc "Find one scenario by id, or nil."
  @spec find(String.t()) :: map() | nil
  def find(id) when is_binary(id) do
    Enum.find(@scenarios, &(&1.id == id))
  end
end
