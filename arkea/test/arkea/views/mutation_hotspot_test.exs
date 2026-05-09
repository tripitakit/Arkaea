defmodule Arkea.Views.MutationHotspotTest do
  use ExUnit.Case, async: true

  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Persistence.AuditLog
  alias Arkea.Views.MutationHotspot

  defp two_domain_gene do
    Gene.from_domains([
      Domain.new([0, 0, 1], List.duplicate(10, 20)),
      Domain.new([0, 0, 5], List.duplicate(15, 20))
    ])
  end

  test "build/2 with no audit returns zero counts on every codon" do
    gene = two_domain_gene()
    model = MutationHotspot.build(gene, [])

    assert model.gene_id == gene.id
    assert model.codon_count == 46
    assert model.total_events == 0
    assert Enum.all?(model.bins, &(&1.count == 0))
  end

  test "domain_flip event spreads its weight across all 23 codons of the affected domain" do
    gene = two_domain_gene()

    audit = [
      %AuditLog{
        event_type: "domain_flip",
        occurred_at_tick: 5,
        target_lineage_id: "L-1",
        payload: %{
          "gene_id" => gene.id,
          "domain_index" => 0,
          "from_type" => "catalytic_site",
          "to_type" => "transmembrane_anchor"
        }
      }
    ]

    model = MutationHotspot.build(gene, audit)

    # Domain 0 → codons 0..22 each get +1.
    domain_0 = Enum.slice(model.bins, 0, 23)
    assert Enum.all?(domain_0, &(&1.count == 1))

    domain_1 = Enum.slice(model.bins, 23, 23)
    assert Enum.all?(domain_1, &(&1.count == 0))

    assert model.total_events == 23
  end

  test "domain_flip event on a different gene is ignored" do
    gene = two_domain_gene()

    audit = [
      %AuditLog{
        event_type: "domain_flip",
        occurred_at_tick: 5,
        target_lineage_id: "L-2",
        payload: %{"gene_id" => "some-other-gene-id", "domain_index" => 0}
      }
    ]

    model = MutationHotspot.build(gene, audit)
    assert model.total_events == 0
  end

  test "gene_chimera_birth bumps the last codon when the gene is source or dest" do
    gene = two_domain_gene()

    audit = [
      %AuditLog{
        event_type: "gene_chimera_birth",
        occurred_at_tick: 7,
        target_lineage_id: "L-3",
        payload: %{
          "source_gene_id" => gene.id,
          "dest_gene_id" => "X",
          "codons_moved" => 23
        }
      },
      %AuditLog{
        event_type: "gene_chimera_birth",
        occurred_at_tick: 8,
        target_lineage_id: "L-4",
        payload: %{
          "source_gene_id" => "Y",
          "dest_gene_id" => gene.id,
          "codons_moved" => 23
        }
      }
    ]

    model = MutationHotspot.build(gene, audit)
    last_bin = List.last(model.bins)
    assert last_bin.count == 2
    assert "gene_chimera_birth" in last_bin.contributors
  end

  test "unrelated audit event types are filtered out" do
    gene = two_domain_gene()

    audit = [
      %AuditLog{
        event_type: "lineage_born",
        occurred_at_tick: 1,
        target_lineage_id: "L-5",
        payload: %{"mutation_summary" => %{"d_growth_rate" => 0.1}}
      },
      %AuditLog{
        event_type: "intervention",
        occurred_at_tick: 2,
        payload: %{}
      }
    ]

    assert MutationHotspot.build(gene, audit).total_events == 0
  end
end
