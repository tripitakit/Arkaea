defmodule Arkea.Game.Scenarios do
  @moduledoc """
  Curated seed-lab presets (UI Phase G).

  Each scenario is a one-click recipe for a seed: it pre-fills the
  Seed Lab form with a deliberate combination of archetype +
  metabolism / membrane / regulation / mobile-module so the player
  can land in an interesting evolutionary corner without designing
  from scratch.

  ## Survival calibration (2026-05-05)

  Every preset shipped here is validated against the live tick to
  keep the founder colony alive for ≥ 400 ticks at default
  parameters. Configurations that collapse the founder via osmotic
  shock or substrate exhaustion (e.g. `mutator` regulation in
  oligotrophic phases, default cassettes in chemolithotrophic
  archetypes like `acid_mine_drainage` / `hydrothermal_vent` /
  `methanogenic_bog`) are deliberately *not* exposed as quick-start
  chips: the simulation's substrate-binding domains target glucose
  by default, and reaching those archetypes productively requires
  manual customisation of the catalytic / substrate domains in the
  gene designer. They remain available for hand-built seeds —
  experimentation is the point — but the chips below stay safe.

  The simulation already exposes 8 archetypes, 3 metabolism profiles,
  3 membrane profiles, 3 regulation profiles and 3 mobile modules;
  the goal of this module is *not* to enumerate the combinatorial
  space but to highlight a small handful of stress-tests each
  illustrating a distinct evolutionary phenomenon.
  """

  @scenarios [
    %{
      id: "lake_with_prophage",
      title: "Oligotrophic lake + latent prophage",
      summary:
        "Cool low-nutrient lake with a balanced cassette and a latent prophage in the seed. Population stays modest; once density is high enough the prophage can induce under stress.",
      params: %{
        "seed_name" => "Lake Pioneer",
        "starter_archetype" => "oligotrophic_lake",
        "metabolism_profile" => "balanced",
        "membrane_profile" => "porous",
        "regulation_profile" => "responsive",
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
      id: "soil_generalist",
      title: "Mesophilic soil generalist",
      summary:
        "Patchy soil with aerobic pores + wet clumps + soil water. Balanced cassette and salinity-tuned envelope handle the moderate osmotic gradient; ideal for observing niche partitioning across phases.",
      params: %{
        "seed_name" => "Soil Generalist",
        "starter_archetype" => "mesophilic_soil",
        "metabolism_profile" => "balanced",
        "membrane_profile" => "salinity_tuned",
        "regulation_profile" => "responsive",
        "mobile_module" => "conjugative_plasmid"
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
