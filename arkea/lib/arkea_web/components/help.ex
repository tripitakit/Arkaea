defmodule ArkeaWeb.Components.Help do
  @moduledoc """
  In-app help primitives.

  - `<.glossary_term term="kcat" />` renders a span styled as a hint that
    shows a definition tooltip on hover, and links to the relevant
    section of `/help/<doc>?section=<anchor>` on click.
  - `<.help_link doc="user-manual" section="..." />` is the underlying
    link primitive used elsewhere.

  The glossary is a static keyword list — adding a term is a one-line
  change. Adding a section anchor in a doc is enough to wire the link;
  the help live view honours `?section=` deep links.
  """
  use Phoenix.Component

  # The term keys are matched case-insensitively.
  # `summary`: one-sentence description shown in the tooltip.
  # `doc`: which Markdown doc the term is described in (HelpDoc slug).
  # `section`: anchor inside that doc (Earmark slugified heading).
  @glossary [
    {"kcat",
     %{
       summary:
         "Turnover number: catalytic reactions per active site per second under saturating substrate.",
       doc: "design",
       section: "block-7-domini-funzionali"
     }},
    {"km",
     %{
       summary:
         "Michaelis constant: substrate concentration at which the enzyme runs at half-Vmax.",
       doc: "design",
       section: "block-7-domini-funzionali"
     }},
    {"hgt",
     %{
       summary:
         "Horizontal gene transfer: cell-to-cell DNA movement via conjugation, transformation, or transduction.",
       doc: "biological-model-review",
       section: "fase-12-difese-r-m-e-ciclo-fagico-chiuso-p0-prerequisito-bloccante"
     }},
    {"qs",
     %{
       summary:
         "Quorum sensing: density-dependent regulation via secreted/received small-molecule signals.",
       doc: "design",
       section: "block-9-quorum-sensing"
     }},
    {"sos",
     %{
       summary:
         "SOS response: DNA-damage-triggered program raising mutation rate and inducing prophages.",
       doc: "biological-model-review",
       section: "fase-17-sos-error-catastrophe-operoni-bacteriocine-p1"
     }},
    {"r-m",
     %{
       summary:
         "Restriction-modification: paired enzymes that cleave foreign DNA but spare host DNA via methylation.",
       doc: "biological-model-review",
       section: "fase-12-difese-r-m-e-ciclo-fagico-chiuso-p0-prerequisito-bloccante"
     }},
    {"plasmid",
     %{
       summary:
         "Extrachromosomal replicon, often mobilizable; copy-number, inc-group and oriT govern its dynamics.",
       doc: "design",
       section: "block-4-replicon-i-cromosoma-plasmidi-profagi"
     }},
    {"prophage",
     %{
       summary:
         "Phage genome integrated lysogenically; can be induced under stress to enter the lytic cycle.",
       doc: "biological-model-review",
       section: "fase-12-difese-r-m-e-ciclo-fagico-chiuso-p0-prerequisito-bloccante"
     }},
    {"lineage",
     %{
       summary:
         "A clonal population sharing a genome; speciation creates a new lineage with a parent_id link.",
       doc: "design",
       section: "block-3-lineage-speciazione-tracking"
     }},
    {"phenotype",
     %{
       summary:
         "Aggregated runtime expression of the genome — kcat, Km, n_passes, qs_receives, surface tags, etc.",
       doc: "design",
       section: "block-8-phenotype-aggregator"
     }},
    {"biofilm",
     %{
       summary:
         "QS-driven aggregation lowering local dilution; emergent from adhesin/matrix surface tags.",
       doc: "design",
       section: "block-9-quorum-sensing"
     }},
    {"mutator",
     %{
       summary:
         "Strain with reduced repair fidelity → elevated mutation rate; explores phenotype space faster, risks error catastrophe.",
       doc: "design",
       section: "block-7-domini-funzionali"
     }},
    {"tick",
     %{
       summary:
         "One step of the simulation clock; a biotope advances ~once every 2s in production.",
       doc: "design",
       section: "block-2-tick-determinismo-rng"
     }},
    {"seed",
     %{
       summary:
         "Player-designed founder genome + spec; instantiated as the initial lineage of a home biotope.",
       doc: "user-manual",
       section: "4-seed-lab--progettare-larkeon-iniziale"
     }},
    {"oriT",
     %{
       summary:
         "Origin of transfer: intergenic motif marking a plasmid as conjugatively mobilizable.",
       doc: "design",
       section: "block-7-domini-funzionali"
     }}
  ]

  @term_lookup Map.new(@glossary, fn {term, meta} -> {String.downcase(term), {term, meta}} end)

  @doc "List all glossary entries in declaration order."
  @spec glossary() :: [{String.t(), map()}]
  def glossary, do: @glossary

  @doc """
  Find a glossary entry by case-insensitive term. Returns the metadata map
  or `nil`.
  """
  @spec lookup(String.t()) :: map() | nil
  def lookup(term) when is_binary(term) do
    case Map.get(@term_lookup, String.downcase(term)) do
      {_canonical, meta} -> meta
      nil -> nil
    end
  end

  attr :term, :string, required: true, doc: "key into the glossary registry"
  attr :label, :string, default: nil, doc: "override the rendered text (defaults to term)"
  attr :class, :string, default: nil

  @doc """
  Inline glossary affordance. Render the term with a hint cursor + dotted
  underline, a hover tooltip with the one-line summary, and a click that
  navigates to the help section.

  Falls back to a plain `<span>` if the term is not registered.
  """
  def glossary_term(assigns) do
    case lookup(assigns.term) do
      nil ->
        ~H"""
        <span class={@class}>{@label || @term}</span>
        """

      meta ->
        assigns =
          assigns
          |> assign(:meta, meta)
          |> assign(:href, "/help/#{meta.doc}?section=#{meta.section}")

        ~H"""
        <a
          href={@href}
          class={["arkea-glossary-term", @class]}
          title={@meta.summary}
          aria-label={"Definition: #{@meta.summary}"}
        >
          {@label || @term}
        </a>
        """
    end
  end

  attr :doc, :string, required: true
  attr :section, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  @doc """
  Plain wrapper to a `/help/:doc?section=...` URL. Useful in places where
  you want to link to a help section without going through the glossary.
  """
  def help_link(assigns) do
    assigns =
      assign(
        assigns,
        :href,
        if(assigns.section,
          do: "/help/#{assigns.doc}?section=#{assigns.section}",
          else: "/help/#{assigns.doc}"
        )
      )

    ~H"""
    <a href={@href} class={["arkea-glossary-term", @class]}>
      {render_slot(@inner_block)}
    </a>
    """
  end
end
