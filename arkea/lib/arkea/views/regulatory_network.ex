defmodule Arkea.Views.RegulatoryNetwork do
  @moduledoc """
  Pure view-model for the lineage regulatory network (Phase 25
  / 2.5).

  Consumes the three structural surfaces produced by Phase 21–25:

    * `Arkea.Sim.Phenotype.regulatory_outputs/0` — gene-level
      transcription-factor activities (mode, cooperativity,
      binding_affinity, signal_key) added in Phase 21 / 7.1.
    * `Arkea.Genome.Operon.operons/1` — coordinated transcription
      units added in Phase 25 / 7.2a.
    * `Arkea.Genome.Regulation.{promoter_sites/1,
      riboswitches/1}` — promoter binding sites + riboswitch
      metabolite-sensitivity entries added in Phase 25 / 7.3.

  Produces a small pure shape — `{nodes, edges}` plus a few
  per-shape rollups — that future UI components (the Phylogeny
  tab's "regulatory network" sub-panel, a dedicated
  network-diagram component) can render without re-deriving the
  graph topology.

  ## Node kinds

    * `:gene` — every chromosome gene; `id` = gene id; `label`
      composed from the gene's dominant domain types.
    * `:operon` — every operon (one per `Operon.t()`); `id` =
      operon id; `label` = `"operon · N genes"`.
    * `:metabolite` — every metabolite that appears as the
      target of at least one riboswitch in any chromosome gene.
      `id` = `"met:<metabolite_id>"`.
    * `:signal` — every signal key emitted as the `signal_key`
      of any regulator_output. `id` = `"sig:<signal_key>"`.

  ## Edge kinds

    * `:operon_member` — `gene → operon` when the gene's
      `operon_id` matches the operon.
    * `:regulator_output` — `gene → signal` (or `gene → ?`
      when no signal_key co-locates) for every entry in the
      gene's regulatory_outputs list. `mode :: :activator |
      :repressor` carried alongside.
    * `:riboswitch` — `metabolite → gene` for every riboswitch
      entry on the gene's regulatory_block. `mode :: :activator
      | :repressor`.

  Pure: no DB / no LiveView. The caller passes a `Genome.t()`.
  """

  alias Arkea.Genome
  alias Arkea.Genome.Gene
  alias Arkea.Genome.Operon
  alias Arkea.Genome.Regulation
  alias Arkea.Sim.Phenotype

  @type node_kind :: :gene | :operon | :metabolite | :signal
  @type node_t :: %{
          kind: node_kind(),
          id: String.t(),
          label: String.t()
        }

  @type edge_kind :: :operon_member | :regulator_output | :riboswitch
  @type edge :: %{
          kind: edge_kind(),
          from: String.t(),
          to: String.t(),
          mode: :activator | :repressor | nil,
          payload: map()
        }

  @type t :: %{
          nodes: [node_t()],
          edges: [edge()],
          gene_count: non_neg_integer(),
          operon_count: non_neg_integer(),
          regulator_count: non_neg_integer(),
          riboswitch_count: non_neg_integer()
        }

  @doc """
  Build the regulatory-network view-model from a genome.

  Returns the structure documented above. An empty / leader-only
  genome still gets nodes for every gene; edges + operon /
  metabolite / signal nodes only appear when the corresponding
  structural surface is non-empty.
  """
  @spec build(Genome.t()) :: t()
  def build(%Genome{} = genome) do
    operons = Operon.operons(genome)
    phenotype = Phenotype.from_genome(genome)
    regulatory_outputs = Map.get(phenotype, :regulatory_outputs, [])

    {gene_nodes, operon_nodes, member_edges} = build_genes_and_operons(genome, operons)
    {regulator_edges, signal_nodes} = build_regulator_edges(regulatory_outputs)

    {riboswitch_edges, metabolite_nodes, riboswitch_count} =
      build_riboswitch_edges(genome.chromosome)

    %{
      nodes: gene_nodes ++ operon_nodes ++ metabolite_nodes ++ signal_nodes,
      edges: member_edges ++ regulator_edges ++ riboswitch_edges,
      gene_count: length(gene_nodes),
      operon_count: length(operon_nodes),
      regulator_count: length(regulator_edges),
      riboswitch_count: riboswitch_count
    }
  end

  defp build_genes_and_operons(%Genome{chromosome: chromosome}, operons) do
    gene_nodes =
      Enum.map(chromosome, fn %Gene{} = gene ->
        %{kind: :gene, id: gene.id, label: gene_label(gene)}
      end)

    operon_nodes =
      Enum.map(operons, fn op ->
        %{kind: :operon, id: op.id, label: "operon · #{op.gene_count} genes"}
      end)

    member_edges =
      Enum.flat_map(operons, fn op ->
        Enum.map(op.gene_ids, fn gid ->
          %{
            kind: :operon_member,
            from: gid,
            to: op.id,
            mode: nil,
            payload: %{leader?: gid == op.leader_gene_id}
          }
        end)
      end)

    {gene_nodes, operon_nodes, member_edges}
  end

  defp build_regulator_edges(regulatory_outputs) do
    {edges_rev, signals} =
      Enum.reduce(regulatory_outputs, {[], MapSet.new()}, fn entry, {acc_edges, acc_signals} ->
        # Without a per-entry source-gene id, each regulator_output
        # entry is materialised as an *outgoing* edge from the
        # genome to the targeted signal — the genome-as-emitter
        # framing keeps the node graph well-defined even when
        # multiple genes contribute to the same regulatory_output
        # cassette. The 7.2b runtime promotes these edges to
        # gene-level once the per-gene attribution lands.
        from = "genome"

        case entry.signal_key do
          nil ->
            edge = %{
              kind: :regulator_output,
              from: from,
              to: "signal:none",
              mode: entry.mode,
              payload: %{
                cooperativity: entry.cooperativity,
                binding_affinity: entry.binding_affinity
              }
            }

            {[edge | acc_edges], acc_signals}

          signal_key ->
            sig_node_id = "sig:" <> signal_key

            edge = %{
              kind: :regulator_output,
              from: from,
              to: sig_node_id,
              mode: entry.mode,
              payload: %{
                cooperativity: entry.cooperativity,
                binding_affinity: entry.binding_affinity,
                signal_key: signal_key
              }
            }

            {[edge | acc_edges], MapSet.put(acc_signals, signal_key)}
        end
      end)

    signal_nodes =
      signals
      |> Enum.sort()
      |> Enum.map(fn sig ->
        %{kind: :signal, id: "sig:" <> sig, label: "signal:" <> sig}
      end)

    {Enum.reverse(edges_rev), signal_nodes}
  end

  defp build_riboswitch_edges(chromosome) do
    {edges_rev, metabolites, count} =
      Enum.reduce(chromosome, {[], MapSet.new(), 0}, fn %Gene{} = gene, {edges, mets, n} ->
        entries = Regulation.riboswitches(gene)
        new_n = n + length(entries)

        {gene_edges, gene_mets} =
          Enum.reduce(entries, {[], MapSet.new()}, fn r, {acc_edges, acc_mets} ->
            met_id = "met:#{r.metabolite_id}"

            edge = %{
              kind: :riboswitch,
              from: met_id,
              to: gene.id,
              mode: r.mode,
              payload: %{
                metabolite_id: r.metabolite_id,
                threshold: r.threshold,
                magnitude: r.magnitude
              }
            }

            {[edge | acc_edges], MapSet.put(acc_mets, r.metabolite_id)}
          end)

        {gene_edges ++ edges, MapSet.union(mets, gene_mets), new_n}
      end)

    metabolite_nodes =
      metabolites
      |> Enum.sort()
      |> Enum.map(fn mid ->
        %{kind: :metabolite, id: "met:#{mid}", label: "metabolite ##{mid}"}
      end)

    {Enum.reverse(edges_rev), metabolite_nodes, count}
  end

  defp gene_label(%Gene{domains: domains}) do
    case Enum.map(domains, & &1.type) do
      [] ->
        "gene"

      [single] ->
        Atom.to_string(single)

      types ->
        types
        |> Enum.frequencies()
        |> Enum.max_by(fn {_t, n} -> n end)
        |> elem(0)
        |> Atom.to_string()
        |> Kernel.<>(" + #{length(types) - 1}")
    end
  end
end
