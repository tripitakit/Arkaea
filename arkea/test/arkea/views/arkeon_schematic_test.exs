defmodule Arkea.Views.ArkeonSchematicTest do
  use ExUnit.Case, async: true

  alias Arkea.Views.ArkeonSchematic

  describe "build/1" do
    test "produces a complete layout from a minimal preview" do
      layout =
        ArkeonSchematic.build(%{
          spec: %{
            membrane_profile: "porous",
            metabolism_profile: "balanced",
            regulation_profile: "responsive",
            mobile_module: "none"
          },
          phenotype: %{n_transmembrane: 0, surface_tags: []},
          genome: %{plasmids: [], prophages: []}
        })

      assert layout.viewbox =~ "0 0"
      assert layout.envelope.kind == :smooth
      refute layout.envelope.double?
      assert layout.membrane_spans == []
      assert is_list(layout.granules) and length(layout.granules) > 0
      assert layout.plasmids == []
      assert layout.prophage == nil
      assert layout.flagellum == nil
      assert layout.stress_halo == nil
      assert layout.cluster == :generalist
      assert length(layout.legend) == 4
    end

    test "fortified envelope renders a double outline" do
      layout =
        ArkeonSchematic.build(%{
          spec: %{
            membrane_profile: "fortified",
            metabolism_profile: "balanced",
            regulation_profile: "responsive",
            mobile_module: "none"
          },
          phenotype: %{n_transmembrane: 0, surface_tags: []},
          genome: %{plasmids: [], prophages: []}
        })

      assert layout.envelope.kind == :smooth
      assert layout.envelope.double?
      assert layout.envelope.inner_offset > 0
    end

    test "salinity_tuned envelope renders a scalloped path" do
      layout =
        ArkeonSchematic.build(%{
          spec: %{
            membrane_profile: "salinity_tuned",
            metabolism_profile: "balanced",
            regulation_profile: "responsive",
            mobile_module: "none"
          },
          phenotype: %{n_transmembrane: 0, surface_tags: []},
          genome: %{plasmids: [], prophages: []}
        })

      assert layout.envelope.kind == :scalloped
      assert layout.envelope.path =~ "M "
    end

    test "transmembrane spans count matches phenotype.n_transmembrane (capped)" do
      for n <- [0, 1, 3, 8, 12, 20] do
        layout =
          ArkeonSchematic.build(%{
            spec: %{
              membrane_profile: "porous",
              metabolism_profile: "balanced",
              regulation_profile: "responsive",
              mobile_module: "none"
            },
            phenotype: %{n_transmembrane: n, surface_tags: []},
            genome: %{plasmids: [], prophages: []}
          })

        expected = n |> max(0) |> min(12)
        assert length(layout.membrane_spans) == expected
      end
    end

    test "biofilm cluster surfaces adhesin appendages" do
      layout =
        ArkeonSchematic.build(%{
          spec: %{
            membrane_profile: "porous",
            metabolism_profile: "balanced",
            regulation_profile: "responsive",
            mobile_module: "none"
          },
          phenotype: %{n_transmembrane: 1, surface_tags: [:adhesin, :biofilm]},
          genome: %{plasmids: [], prophages: []}
        })

      assert layout.cluster == :biofilm
      assert Enum.any?(layout.surface_appendages, &(&1.kind == :adhesin))
      # Motile is overridden by biofilm precedence.
      assert layout.flagellum == nil
    end

    test "n_transmembrane >= 2 + no biofilm tags = motile cluster + flagellum" do
      layout =
        ArkeonSchematic.build(%{
          spec: %{
            membrane_profile: "porous",
            metabolism_profile: "balanced",
            regulation_profile: "responsive",
            mobile_module: "none"
          },
          phenotype: %{n_transmembrane: 3, surface_tags: []},
          genome: %{plasmids: [], prophages: []}
        })

      assert layout.cluster == :motile
      assert layout.flagellum != nil
      assert layout.flagellum.path =~ "M "
    end

    test "phage_receptor surface tag emits a receptor appendage" do
      layout =
        ArkeonSchematic.build(%{
          spec: %{
            membrane_profile: "porous",
            metabolism_profile: "balanced",
            regulation_profile: "responsive",
            mobile_module: "none"
          },
          phenotype: %{n_transmembrane: 1, surface_tags: [:phage_receptor]},
          genome: %{plasmids: [], prophages: []}
        })

      assert Enum.any?(layout.surface_appendages, &(&1.kind == :phage_receptor))
    end

    test "conjugative_plasmid hint shows when genome has no materialised plasmid yet" do
      layout =
        ArkeonSchematic.build(%{
          spec: %{
            membrane_profile: "porous",
            metabolism_profile: "balanced",
            regulation_profile: "responsive",
            mobile_module: "conjugative_plasmid"
          },
          phenotype: %{n_transmembrane: 0, surface_tags: []},
          genome: %{plasmids: [], prophages: []}
        })

      assert length(layout.plasmids) == 1
      assert hd(layout.plasmids)[:hinted?]
    end

    test "latent_prophage shows the prophage triangular mark" do
      layout =
        ArkeonSchematic.build(%{
          spec: %{
            membrane_profile: "porous",
            metabolism_profile: "balanced",
            regulation_profile: "responsive",
            mobile_module: "latent_prophage"
          },
          phenotype: %{n_transmembrane: 0, surface_tags: []},
          genome: %{plasmids: [], prophages: []}
        })

      assert layout.prophage != nil
      assert layout.prophage.size > 0
    end

    test "mutator regulation surfaces a stress halo" do
      layout =
        ArkeonSchematic.build(%{
          spec: %{
            membrane_profile: "porous",
            metabolism_profile: "balanced",
            regulation_profile: "mutator",
            mobile_module: "none"
          },
          phenotype: %{n_transmembrane: 0, surface_tags: []},
          genome: %{plasmids: [], prophages: []}
        })

      assert layout.stress_halo != nil
      assert layout.stress_halo.stroke_dasharray =~ "3"
    end

    test "granule count grows with metabolism profile aggressiveness" do
      thrifty =
        ArkeonSchematic.build(%{
          spec: %{
            membrane_profile: "porous",
            metabolism_profile: "thrifty",
            regulation_profile: "responsive",
            mobile_module: "none"
          },
          phenotype: %{n_transmembrane: 0, surface_tags: []},
          genome: %{plasmids: [], prophages: []}
        })

      bloom =
        ArkeonSchematic.build(%{
          spec: %{
            membrane_profile: "porous",
            metabolism_profile: "bloom",
            regulation_profile: "responsive",
            mobile_module: "none"
          },
          phenotype: %{n_transmembrane: 0, surface_tags: []},
          genome: %{plasmids: [], prophages: []}
        })

      assert length(bloom.granules) > length(thrifty.granules)
    end

    test "is deterministic across calls" do
      preview = %{
        spec: %{
          membrane_profile: "fortified",
          metabolism_profile: "bloom",
          regulation_profile: "mutator",
          mobile_module: "latent_prophage"
        },
        phenotype: %{n_transmembrane: 4, surface_tags: [:adhesin, :phage_receptor]},
        genome: %{plasmids: [%{}], prophages: [%{}]}
      }

      a = ArkeonSchematic.build(preview)
      b = ArkeonSchematic.build(preview)

      assert a == b
    end

    test "unknown spec strings fall back to safe defaults" do
      layout =
        ArkeonSchematic.build(%{
          spec: %{
            membrane_profile: "wat",
            metabolism_profile: nil,
            regulation_profile: 42,
            mobile_module: "rocket_booster"
          },
          phenotype: %{n_transmembrane: 0, surface_tags: []},
          genome: %{plasmids: [], prophages: []}
        })

      assert layout.envelope.kind == :smooth
      assert layout.cytoplasm.density == :medium
      assert layout.stress_halo == nil
      assert layout.plasmids == []
    end
  end
end
