defmodule Arkea.Generators do
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  # `gen all do ... end` blocks compose by nesting; the canonical StreamData
  # pattern legitimately exceeds Credo's default depth here.

  @moduledoc """
  StreamData generators for Arkea domain structs.

  Used by all property-based tests. Generators are designed to be:
  - Biologically reasonable: generated data falls within the valid parameter
    spaces defined by the design documents.
  - Adversarial where useful: edge values (0, 19, min/max codon counts) are
    included with reasonable frequency.
  - Shrinkable: prefer integer generators and small lists to aid shrinking.

  All generators are pure StreamData pipelines. No side effects.
  """

  use ExUnitProperties

  alias Arkea.Ecology.Biotope
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Domain.Type
  alias Arkea.Genome.Gene
  alias Arkea.Genome.Mutation.Duplication
  alias Arkea.Genome.Mutation.Indel
  alias Arkea.Genome.Mutation.Inversion
  alias Arkea.Genome.Mutation.Substitution
  alias Arkea.Genome.Mutation.Translocation

  # ---------------------------------------------------------------------------
  # Codon generators

  @doc "Generate a single valid codon (integer in 0..19)."
  def codon do
    StreamData.integer(0..19)
  end

  @doc """
  Generate a list of codons with length in the given range.

  The length must be provided as a Range with integer bounds.
  """
  def codon_list(length_range) do
    StreamData.bind(StreamData.integer(length_range), fn len ->
      StreamData.list_of(codon(), length: len)
    end)
  end

  @doc "Generate a 3-codon type_tag."
  def type_tag do
    StreamData.list_of(codon(), length: 3)
  end

  @doc """
  Generate parameter_codons with length in 10..30.

  This is the Domain-level freedom; the Gene Phase1 parser fixes length to 20.
  """
  def parameter_codons do
    codon_list(10..30)
  end

  @doc "Generate parameter_codons of exactly 20 for Gene Phase1 compatibility."
  def parameter_codons_phase1 do
    StreamData.list_of(codon(), length: 20)
  end

  # ---------------------------------------------------------------------------
  # Domain generator

  @doc """
  Generate a valid Domain struct using Domain.new/2.

  Uses parameter_codons of length 10..30 (full Domain freedom).
  All generated domains pass Domain.valid?/1.
  """
  def domain do
    StreamData.bind(type_tag(), fn tag ->
      StreamData.bind(parameter_codons(), fn params ->
        StreamData.constant(Domain.new(tag, params))
      end)
    end)
  end

  @doc """
  Generate a valid Domain struct compatible with Phase1 Gene parsing
  (parameter_codons length fixed at 20).
  """
  def domain_phase1 do
    StreamData.bind(type_tag(), fn tag ->
      StreamData.bind(parameter_codons_phase1(), fn params ->
        StreamData.constant(Domain.new(tag, params))
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Gene generators

  @doc """
  Generate a valid Gene struct from a list of Phase1-compatible domains.

  Generates 1..9 domains via domain_phase1/0, then uses Gene.from_domains/1.
  The resulting gene has codon count n * 23 with n in 1..9.
  Internally consistent: codons == concat of domain type_tags + parameter_codons.
  """
  def gene do
    StreamData.bind(StreamData.integer(1..9), fn n ->
      StreamData.bind(StreamData.list_of(domain_phase1(), length: n), fn domains ->
        StreamData.constant(Gene.from_domains(domains))
      end)
    end)
  end

  @doc """
  Generate a valid Gene by producing a codon list of length n * 23 (n in 1..9)
  and parsing it via Gene.from_codons/1.

  Useful for testing the from_codons path specifically.
  """
  def gene_from_codons do
    StreamData.bind(StreamData.integer(1..9), fn n ->
      StreamData.bind(StreamData.list_of(codon(), length: n * 23), fn codons ->
        case Gene.from_codons(codons) do
          {:ok, gene} -> StreamData.constant(gene)
          {:error, _} -> StreamData.constant(:error)
        end
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Genome generator

  @doc """
  Generate a valid Genome struct with a non-empty chromosome of 1..5 genes.

  Phase 1: plasmids and prophages are empty.
  """
  def genome do
    StreamData.bind(StreamData.integer(1..5), fn n ->
      StreamData.bind(StreamData.list_of(gene(), length: n), fn genes ->
        StreamData.constant(Genome.new(genes))
      end)
    end)
  end

  @doc """
  Generate a genome paired with a valid plasmid (list of 1..3 genes).
  Returns {genome, plasmid}.
  """
  def genome_with_plasmid do
    StreamData.bind(genome(), fn g ->
      StreamData.bind(StreamData.integer(1..3), fn n ->
        StreamData.bind(StreamData.list_of(gene(), length: n), fn plasmid ->
          StreamData.constant({g, plasmid})
        end)
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Lineage generators

  @doc """
  Generate a valid founder Lineage using Lineage.new_founder/3.

  Abundances are a map with 1..3 atom keys, each with a non-negative count.
  """
  def lineage do
    alias Arkea.Ecology.Lineage

    StreamData.bind(genome(), fn g ->
      StreamData.bind(abundances(), fn abunds ->
        StreamData.bind(StreamData.integer(0..1_000_000), fn tick ->
          StreamData.constant(Lineage.new_founder(g, abunds, tick))
        end)
      end)
    end)
  end

  @doc """
  Generate a parent-child lineage pair where child.created_at_tick > parent.created_at_tick.

  Returns {parent, child}.
  """
  def lineage_pair do
    alias Arkea.Ecology.Lineage

    StreamData.bind(lineage(), fn parent ->
      StreamData.bind(genome(), fn child_genome ->
        StreamData.bind(abundances(), fn abunds ->
          child_tick = parent.created_at_tick + 1

          StreamData.bind(StreamData.integer(0..1_000), fn extra ->
            tick = child_tick + extra

            StreamData.constant({parent, Lineage.new_child(parent, child_genome, abunds, tick)})
          end)
        end)
      end)
    end)
  end

  @doc """
  Generate abundance maps: atom keys => non-negative integers.

  Uses phase-name-like atoms to keep things semantically plausible.
  """
  def abundances do
    phase_name_atoms = [
      :surface,
      :water_column,
      :sediment,
      :vent_core,
      :mixing_zone,
      :acid_water,
      :mineral_surface,
      :aerated_pore
    ]

    StreamData.bind(StreamData.integer(1..3), fn n ->
      keys = Enum.take_random(phase_name_atoms, n)

      StreamData.bind(
        StreamData.list_of(StreamData.integer(0..100_000), length: n),
        fn vals ->
          StreamData.constant(Enum.zip(keys, vals) |> Map.new())
        end
      )
    end)
  end

  @doc """
  Generate a growth delta map: atom keys => signed integers.

  Some deltas may be strongly negative (adversarial).
  """
  def growth_deltas do
    phase_name_atoms = [
      :surface,
      :water_column,
      :sediment,
      :vent_core,
      :mixing_zone,
      :acid_water,
      :mineral_surface
    ]

    StreamData.bind(StreamData.integer(1..3), fn n ->
      keys = Enum.take_random(phase_name_atoms, n)

      StreamData.bind(
        StreamData.list_of(StreamData.integer(-200_000..200_000), length: n),
        fn vals ->
          StreamData.constant(Enum.zip(keys, vals) |> Map.new())
        end
      )
    end)
  end

  # ---------------------------------------------------------------------------
  # Phase generator

  @doc """
  Generate a valid Phase struct with random environmental parameters.

  Generates values within the valid ranges defined by Phase:
  - temperature: -50.0..150.0
  - ph: 0.0..14.0
  - osmolarity: 0.0..5000.0
  - dilution_rate: 0.0..1.0 (exclusive bounds handled by Phase validation)
  """
  def phase do
    phase_names = [
      :surface,
      :water_column,
      :sediment,
      :vent_core,
      :mixing_zone,
      :acid_water,
      :mineral_surface,
      :aerated_pore,
      :wet_clump,
      :soil_water,
      :freshwater_layer,
      :marine_layer,
      :interface,
      :bulk_sediment,
      :peat_core,
      :surface_oxic
    ]

    StreamData.bind(StreamData.member_of(phase_names), fn name ->
      StreamData.bind(float_in(-50.0, 150.0), fn temp ->
        StreamData.bind(float_in(0.0, 14.0), fn ph ->
          StreamData.bind(float_in(0.0, 5000.0), fn osm ->
            StreamData.bind(float_in(0.0, 1.0), fn dr ->
              StreamData.constant(
                Phase.new(name,
                  temperature: temp,
                  ph: ph,
                  osmolarity: osm,
                  dilution_rate: dr
                )
              )
            end)
          end)
        end)
      end)
    end)
  end

  @doc """
  Generate a Phase with at least one metabolite and one signal in their pools.

  Used to test dilution properties more meaningfully.
  """
  def phase_with_pools do
    metabolite_names = [:glucose, :acetate, :lactate, :co2, :h2s, :oxygen]
    signal_names = [:c4_hsl, :c12_hsl, :ai2, :indole]

    StreamData.bind(phase(), fn p ->
      StreamData.bind(StreamData.member_of(metabolite_names), fn met ->
        StreamData.bind(float_in(0.0, 1000.0), fn met_conc ->
          StreamData.bind(StreamData.member_of(signal_names), fn sig ->
            StreamData.bind(float_in(0.0, 100.0), fn sig_conc ->
              StreamData.constant(
                p
                |> Phase.update_metabolite(met, met_conc)
                |> Phase.update_signal(sig, sig_conc)
              )
            end)
          end)
        end)
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Biotope generator

  @doc """
  Generate a valid Biotope struct for a random archetype.

  Coordinates are floats in -1000.0..1000.0.
  Uses default_phases for the archetype to ensure correctness.
  """
  def biotope do
    StreamData.bind(StreamData.member_of(Biotope.archetypes()), fn archetype ->
      StreamData.bind(float_in(-1000.0, 1000.0), fn x ->
        StreamData.bind(float_in(-1000.0, 1000.0), fn y ->
          StreamData.constant(Biotope.new(archetype, {x, y}))
        end)
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Mutation generators

  @doc "Generate a valid Substitution mutation."
  def substitution do
    StreamData.bind(uuid(), fn gene_id ->
      StreamData.bind(StreamData.integer(0..1000), fn pos ->
        StreamData.bind(codon(), fn old ->
          # Ensure new_codon != old_codon by picking a different one
          StreamData.bind(
            StreamData.filter(codon(), fn c -> c != old end),
            fn new_c ->
              StreamData.constant(%Substitution{
                gene_id: gene_id,
                position: pos,
                old_codon: old,
                new_codon: new_c
              })
            end
          )
        end)
      end)
    end)
  end

  @doc "Generate a valid Indel mutation."
  def indel do
    StreamData.bind(uuid(), fn gene_id ->
      StreamData.bind(StreamData.integer(0..1000), fn pos ->
        StreamData.bind(StreamData.member_of([:insertion, :deletion]), fn kind ->
          StreamData.bind(
            StreamData.bind(StreamData.integer(1..10), fn n ->
              StreamData.list_of(codon(), length: n)
            end),
            fn codons ->
              StreamData.constant(%Indel{
                gene_id: gene_id,
                position: pos,
                kind: kind,
                codons: codons
              })
            end
          )
        end)
      end)
    end)
  end

  @doc "Generate a valid Duplication mutation."
  def duplication do
    StreamData.bind(uuid(), fn gene_id ->
      StreamData.bind(StreamData.integer(0..100), fn rs ->
        StreamData.bind(StreamData.integer(0..100), fn range_extra ->
          StreamData.bind(StreamData.integer(0..1000), fn at ->
            StreamData.constant(%Duplication{
              gene_id: gene_id,
              range_start: rs,
              range_end: rs + range_extra,
              insert_at: at
            })
          end)
        end)
      end)
    end)
  end

  @doc "Generate a valid Inversion mutation."
  def inversion do
    StreamData.bind(uuid(), fn gene_id ->
      StreamData.bind(StreamData.integer(0..100), fn rs ->
        StreamData.bind(StreamData.integer(0..100), fn range_extra ->
          StreamData.constant(%Inversion{
            gene_id: gene_id,
            range_start: rs,
            range_end: rs + range_extra
          })
        end)
      end)
    end)
  end

  @doc "Generate a valid Translocation mutation (source != dest)."
  def translocation do
    StreamData.bind(uuid(), fn src ->
      StreamData.bind(
        StreamData.filter(uuid(), fn d -> d != src end),
        fn dest ->
          StreamData.bind(StreamData.integer(0..100), fn rs ->
            StreamData.bind(StreamData.integer(0..100), fn range_extra ->
              StreamData.bind(StreamData.integer(0..1000), fn at ->
                StreamData.constant(%Translocation{
                  source_gene_id: src,
                  dest_gene_id: dest,
                  source_range: {rs, rs + range_extra},
                  dest_position: at
                })
              end)
            end)
          end)
        end
      )
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers

  @doc false
  def uuid do
    StreamData.constant(nil)
    |> StreamData.map(fn _ -> Arkea.UUID.v4() end)
  end

  @doc false
  def float_in(lo, hi) when lo <= hi do
    StreamData.bind(StreamData.integer(0..10_000_000), fn n ->
      StreamData.constant(lo + n / 10_000_000 * (hi - lo))
    end)
  end

  @doc """
  All 11 domain type atoms.
  """
  def domain_type do
    StreamData.member_of(Type.all())
  end
end
