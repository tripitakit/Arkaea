defmodule Arkea.Game.SeedLab.DomainEditorTest do
  use ExUnit.Case, async: true

  alias Arkea.Game.SeedLab
  alias Arkea.Game.SeedLab.DomainEditor

  describe "editable_params/1" do
    test "returns the high-impact param for the 5 editable domain types" do
      assert [%{key: "target_metabolite_id"}] = DomainEditor.editable_params("substrate_binding")
      assert [%{key: "reaction_class"}] = DomainEditor.editable_params("catalytic_site")
      assert [%{key: "sensed_metabolite_id"}] = DomainEditor.editable_params("ligand_sensor")
      assert [%{key: "tag_class"}] = DomainEditor.editable_params("surface_tag")
      assert [%{key: "repair_class"}] = DomainEditor.editable_params("repair_fidelity")
    end

    test "returns [] for the 6 non-editable domain types" do
      for type <-
            ~w(transmembrane_anchor channel_pore energy_coupling dna_binding regulator_output structural_fold) do
        assert DomainEditor.editable_params(type) == []
        refute DomainEditor.editable?(type)
      end
    end
  end

  describe "metabolite_options/0" do
    test "returns 13 canonical metabolites with stable atom names" do
      options = DomainEditor.metabolite_options()
      assert length(options) == 13
      assert {"0", "glucose"} in options
      assert {"11", "iron"} in options
    end
  end

  describe "override_codons/3" do
    test "pins target_metabolite_id by overriding the first codon" do
      default = [0 | List.duplicate(4, 19)]

      iron =
        DomainEditor.override_codons("substrate_binding", default, %{
          "target_metabolite_id" => "11"
        })

      assert hd(iron) == 11
    end

    test "pins reaction_class via codons[0..2]" do
      default = List.duplicate(9, 20)

      oxidation =
        DomainEditor.override_codons("catalytic_site", default, %{"reaction_class" => "oxidation"})

      assert Enum.take(oxidation, 3) == [1, 0, 0]
    end

    test "is a no-op for non-editable types" do
      default = List.duplicate(7, 20)
      assert DomainEditor.override_codons("transmembrane_anchor", default, %{}) == default
    end

    test "is a no-op for unknown params" do
      default = List.duplicate(13, 20)
      assert DomainEditor.override_codons("surface_tag", default, %{"foo" => "bar"}) == default
    end
  end

  describe "sanitize/2" do
    test "drops keys not in the editable schema" do
      assert DomainEditor.sanitize("substrate_binding", %{
               "target_metabolite_id" => "11",
               "kcat" => "9.9"
             }) == %{"target_metabolite_id" => "11"}
    end
  end

  describe "end-to-end SeedLab integration" do
    test "a substrate_binding domain pinned to iron lands in phenotype.substrate_affinities[:iron]" do
      preview =
        SeedLab.preview(%{
          "seed_name" => "iron-eater",
          "starter_archetype" => "acid_mine_drainage",
          "metabolism_profile" => "balanced",
          "membrane_profile" => "porous",
          "regulation_profile" => "responsive",
          "mobile_module" => "none",
          "custom_gene_payload" =>
            Jason.encode!([
              %{
                "domains" => [
                  %{"type" => "substrate_binding", "params" => %{"target_metabolite_id" => "11"}}
                ],
                "intergenic" => %{"expression" => [], "transfer" => [], "duplication" => []}
              }
            ])
        })

      assert Map.has_key?(preview.phenotype.substrate_affinities, :iron)
    end

    test "custom plasmid genes append a new plasmid replicon with the chosen substrate" do
      preview =
        SeedLab.preview(%{
          "seed_name" => "plasmid-iron",
          "starter_archetype" => "acid_mine_drainage",
          "metabolism_profile" => "balanced",
          "membrane_profile" => "porous",
          "regulation_profile" => "responsive",
          "mobile_module" => "none",
          "custom_plasmid_payload" =>
            Jason.encode!([
              %{
                "domains" => [
                  %{"type" => "substrate_binding", "params" => %{"target_metabolite_id" => "11"}}
                ],
                "intergenic" => %{"transfer" => ["orit_site"]}
              }
            ])
        })

      assert length(preview.genome.plasmids) == 1
      assert Map.has_key?(preview.phenotype.substrate_affinities, :iron)
    end

    test "legacy bare-string domain entries still produce default params (backward compat)" do
      preview =
        SeedLab.preview(%{
          "seed_name" => "legacy",
          "starter_archetype" => "eutrophic_pond",
          "metabolism_profile" => "balanced",
          "membrane_profile" => "porous",
          "regulation_profile" => "responsive",
          "mobile_module" => "none",
          "custom_gene_payload" =>
            Jason.encode!([
              %{"domains" => ["substrate_binding"], "intergenic" => %{}}
            ])
        })

      # Default substrate_binding template targets metabolite 0 (glucose).
      assert Map.has_key?(preview.phenotype.substrate_affinities, :glucose)
    end
  end
end
