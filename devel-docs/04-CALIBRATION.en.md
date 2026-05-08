> [🇮🇹 Italiano](04-CALIBRATION.md) · 🇬🇧 English (this page)

# Arkea biological model calibration

This document is the calibration appendix of the biological model, recommended by the scientific review conducted after Phase 19. Its purpose: to *explicitly* declare the internal time and concentration scales of the simulator, and to map every key constant in the code to the known biological range found in the literature.

**Without this appendix, a professional microbiologist opening the code will find constants that "look" too low or too high and will ask embarrassing questions** (verbatim from the scientific review). With this appendix the model is defensible as an *individual-based evolutionary sandbox with generative-grammar genomes and pathway-level Michaelis-Menten metabolism, with parameter regimes calibrated for phenomenon visibility within the simulator's in-silico time-scales rather than fitted to organism-specific kinetics* — a framing the computational microbiology community recognises for educational sandboxes and qualitative research.

> **Terminology note**: internal project docs (01-DESIGN.md "decision 2026-04-25", 05-BIOLOGICAL-MODEL-REVIEW.md) refer to "level B+C" as shorthand for "cellular-architecture (B) + pathway-level metabolism (C)". That shorthand is internal to the project scoping brainstorm, **not** a published taxonomy; for external communication use the full description above. Landscape comparison: more abstract than Karr (whole-cell), more detailed than Avida on the metabolic side, comparable to Aevol on the genome side.

## Calibration principles

1. **Explicit abstraction, not fitted kinetics**. Arkea is an *individual-based evolutionary sandbox* at the cellular-architecture + pathway-level-metabolism layer (see terminology note above), not a kinetic-equation solver. Constants are calibrated to surface biological phenomena within game-play timescales, not to replicate absolute measurements.
2. **Declared time-compression**. 1 simulated tick = 5 minutes wall-clock. One reference Arkeon "generation" = 1 tick. Real generations vary (Lenski-style *E. coli*: 30 min; mutator strains: 20 min; stationary: hours); the time-compression maps to the cell-cycle of the average modeled organism.
3. **Declared concentration scale**. Concentrations in `Phase.metabolite_pool` are in *dimensionless* units, scaled so that *"typical" values for nutrient inflow in the canary* fall in the range `100..500`. No 1:1 conversion to mol/L.
4. **Calibration for canary visibility**. Events that are rare in vivo (transduction, SOS hypermutation) are *amplified* just enough to be observable in scenarios spanning hundreds to a few thousand ticks. Config-tunable override settings are available for scientific benchmark experiments.

## Time scales

| Construct | Arkea value | Biological reality |
|---|---|---|
| 1 tick | 5 minutes wall-clock | 1 reference generation |
| Phage decay half-life | 3–5 ticks | hours–days in surface waters (Suttle 1994) — consistent if 1 tick ≈ 1 h |
| Bacteriocin kill | 80–160 ticks | colicin in vivo: 30–60 min (Cascales 2007) — *deliberately slow*: chronic > acute warfare |
| SOS activation | 4–10 ticks under stress | minutes in vivo (Cox 2000) — *time-compression* |
| Mutator emergence | 50–200 ticks | 100–1000 generations in Lenski-style — comparable |
| Cycle closure cross-feeding | 100–500 ticks at steady state | days in chemostat (Stams & Plugge 2009) — consistent |

## Key code constants (post-Phase 20)

### HGT — conjugation

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `@conj_base_rate` | `hgt.ex:55` | 0.005 | F-plasmid 10⁻²/cell/h at high density | Under-estimate at low densities; OK in "estuary" canary |
| `@p_conj_max` | `hgt.ex:56` | 0.30 | Saturation cap | Conservative |

### HGT — transformation

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `@uptake_base` | `transformation.ex` | 0.0006 | Competent *Streptococcus* / *Bacillus* / *Haemophilus*: 10⁻⁵–10⁻⁷/cell/gen | Calibrated for canary visibility |
| `competence_score` threshold | derived | 0.10 | Only species with the ComEC + TM + sensor triad | Realistic — competence is non-default |

### HGT — phages and R-M

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `@cleave_p` | `defense.ex:67` | **0.95** (Phase 20: was 0.70) | Type II 95–99 % per site (Tock & Dryden 2005) | ✅ Aligned post-Phase 20 |
| `@transduction_probability` | `phage.ex:76` | **0.005** (post-Review-2; was 0.05) | 10⁻⁶–10⁻³ per phage particle (Chen 2018) | ~1 order of magnitude above the literature ceiling (canary visibility); realistic override: `config :arkea, :transduction_probability, 0.001` |
| `@transducing_burst_fraction` | `phage.ex:77` | 0.03 | ~3 % mis-packaged capsids | Realistic |
| `@base_decay` | `phage.ex:84` | 0.20/tick | Free phage half-life (Suttle 1994) | Consistent with time scale |
| `@p_infect_base` | `phage.ex:92` | 0.0008 | Adsorption rate constant 10⁻⁹–10⁻⁷ mL/min | Calibrated for visibility |
| `@lytic_decision_base` | `phage.ex:104` | **0.50** (post-Review-2; was 0.40) | Lambda lysis frequency under stress | p_lytic saturates at 1 with repressor=0 (commit `d922365`) |

### Selection pressures

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `oxygen` toxic threshold | `metabolism.ex:160` | **50** (Phase 20: was 200) | µM for obligate anaerobes, Imlay 2008 | ✅ Phase 20: obligate anaerobes discriminated |
| `oxygen` toxic scale | `metabolism.ex:160` | 200 | Slope towards full toxicity | OK |
| `h2s` toxic threshold | `metabolism.ex:161` | 20 | 10–100 µM on cytochrome c (Cooper & Brown 2008) | OK |
| `lactate` toxic threshold | `metabolism.ex:162` | 30 | Not toxic per se (it is pH) | **To be removed** when Phase 21 implements dynamic pH |
| `@elemental_floor_per_cell` | `metabolism.ex` | 0.001 | Stoichiometry-derived | Conservative |

### Aerobic respiration (Phase 20)

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `@aerobic_boost` | `metabolism.ex:120` | 7.0 | Glucose: 32 ATP aerobic vs 2 fermentation = 16× | Conservative (8× max effective vs 16× textbook) |

### SOS / error catastrophe

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `@sos_active_threshold` | `mutator.ex:86` | **0.20** (Phase 20: was 0.50) | SOS near-immediate in vivo (Cox 2000) | ✅ Phase 20: now routine under stress |
| `@sos_mutation_amplifier` | `mutator.ex:87` | 4.0× | DinB-like fold-change µ: 10²–10⁴ × in vivo | Conservative |
| `@sos_induction_amplifier` | `mutator.ex:88` | 3.0× | RecA cleaves cI fold-change | Plausible |
| `@dna_damage_decay` | `mutator.ex:74` | 0.10/tick | Repair half-life ~min in vivo | Consistent with tick ≈ hours |
| `@ros_damage_max_per_tick` | `mutator.ex:99` | 0.05 | Per-tick increment ceiling under full exposure | Phase 20 addition |
| `@critical_mu_per_gene` | `mutator.ex:89` | 0.20 | Eigen quasispecies threshold (legacy hint) | Exposed as API; no longer used in lethality |
| `@selection_coefficient_default` | `mutator.ex:80` | 2.0 | Master sequence fitness 2× mean mutant (Bull et al. 2005) | σ used in `error_catastrophe_lethality/2` |

### Error catastrophe — Eigen threshold (post-Review-2)

`Mutator.error_catastrophe_lethality(mu, genome_size, sigma \\ 2.0)` implements the
Eigen criterion *strictly*: the per-replication fidelity is `(1 − µ/L)^L`, and
the lethality is the relative fidelity deficit against the threshold `1/σ`:

```
fidelity = (1 − µ/L)^L
lethality = max(0, 1 − fidelity × σ)
```

- For `σ = 2.0` (master sequence with fitness ~2× the mean mutant — the
  reference value in Bull et al. 2005) the per-cell threshold is ≈ `ln(σ) = 0.693`,
  *almost independent of L* for moderate L.
- The transition is **smooth**, not a saturation cliff (vs the pre-Review-2
  formula that triggered the barrier already at `µ × L ≥ 1`).

#### Biological consequence

Under the Eigen-aderent formula, Arkea — whose maximum `mu_per_cell` is
≈ 0.04 (`base_rate 0.01 × repair=0 × SOS×4`) — operates **far below the Eigen
threshold**. This is consistent with microbiological reality:

| Organism | µ per replication | Distance from threshold |
|---|---|---|
| RNA virus (poliovirus) | ~10⁰ (≈ 1 mut/genome) | *near* threshold (Eigen 1971) |
| *E. coli* | ~10⁻³ (4.6×10⁻⁴) | far below |
| Arkea SOS-amplified | ~4×10⁻² | far below |

`error_catastrophe_lethality` therefore acts as a **theoretical ceiling**:
enforced but rarely reached during a typical simulation. For extreme
hypermutation scenarios (e.g. synthetic tests with `µ > ln(2)`) the formula
yields a smooth transition toward 1.

Reference: **Bull JJ, Meyers LA, Lachmann M**. *Quasispecies Made Simple*. PLOS
Comput Biol 2005; **Eigen M**. *Self-organization of matter and the evolution of
biological macromolecules*. Naturwissenschaften 1971.

### Bacteriocins

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `@secretion_per_cell` | `bacteriocin.ex:62` | 0.0001/tick | Colicin nM concentrations | Calibrated for *chronic* warfare |
| `@damage_rate` | `bacteriocin.ex:70` | 0.005 | Kill in 50–100 ticks = days at tick = 1 h | Slow but realistic |
| `@max_damage_per_pool` | `bacteriocin.ex:76` | 0.05 | Per-pool damage cap | Conservative |

### Plasmids (Phase 16)

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `@inc_group_modulus` | `genome.ex` | 7 | Inc groups: ~30 known families | Simplification |
| `@max_copy_number` | `genome.ex` | 10 | High-copy plasmids: 10–100 in vivo | Simplification |

### Biofilm (Phase 18)

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `@biofilm_dilution_relief` | `tick.ex:118` | 0.5 | EPS retention 50–95 % in nature | Conservative |

### Mixing (Phase 18)

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `@mixing_event_probability` | `tick.ex:126` | 1.0e-4/tick | Storm cadence ~weeks | Consistent with time-compression |

### Community Mode (Phase 19)

| Constant | Path:line | Value | Note |
|---|---|---|---|
| `SeedLibrary.@max_size` | `seed_library.ex` | 12 entries/player | Anti-deck-building |
| `CommunityLab.@max_community_seeds` | `community_lab.ex` | 3 simultaneous seeds/biotope | Progressive cap |

## Overrides for scientific benchmarks

```elixir
# config/runtime.exs (or test fixture)
config :arkea, :transduction_probability, 0.001  # realistic biological rate
```

## Known v1 model limitations

This section **honestly declares the gaps between what the design promises (`01-DESIGN.en.md`) and what the code currently does**. Origin: user review from a microbiologist perspective (`13-MICROBIOLOGIST-PERSPECTIVE-REVIEW.md`) and molecular biologist perspective (`14-BIOMOL-PERSPECTIVE-REVIEW.md`); closure plan in `15-MICRO-BIO-MOL-INTEGRATION-PLAN.md`.

**Rationale**: the target audience — professional microbiologists and molecular biologists — prefers openly declared limitations over advertised mechanisms that do not work. Each entry below is an *honesty marker*: removed once the corresponding phase is merged.

### L1. Simplified molecular model

| ID | Limitation | Consequence for the user | Closure phase |
|---|---|---|---|
| **L1.1** | `Gene.promoter_block` and `Gene.regulatory_block` are `nil` in Phase 1 (parsing deferred to generative Phase 3). | Promoters and riboswitches are not inspectable, do not mutate, and do not drive expression. The "regulation" advertised in the manual is reduced to a global scalar. | Phase 25 (Operons and regulation) |
| **L1.2** | `:regulator_output` is parsed (mode, cooperativity) but **not aggregated** into a multi-component σ-factor. | Mutations in `:regulator_output` have no observable effect on target expression. | ✅ **Closed Phase 21 #5 (structurally)** — `Phenotype.regulatory_outputs` aggregates each gene carrying `:regulator_output`, enriching mode/cooperativity with the `binding_affinity` of any co-located `:dna_binding` and the `signal_key` of any co-located `:ligand_sensor`; `Phenotype.sigma_factor_components/1` produces a summary `{net_activation, total_activation, total_repression, n_activators, n_repressors}`; new trait `regulatory_net_activation` exposed via TimeSeries + Trends tab; `regulatory_outputs` + `sigma_factor_components` fields exposed in the snapshot export. **Runtime σ wiring deliberately deferred**: `step_expression/1` still uses `dna_binding_affinity` as a single scalar to preserve Phase 5/6/7 calibration. Runtime cabling in the regulatory network = Phase 25. |
| **L1.3** | `Gene.operon_id` is a data field (UUID) but **the module `Arkea.Genome.Operon` does not exist**, nor does a coordinated-expression runtime. Genes under the same operon are not co-transcribed. | The operon as a regulatory unit does not function; the manual must not use it as an operational concept. | Phase 25 |
| **L1.4** | `ribosome_like = 1.0` is **hardcoded** in `phenotype.ex:291`, in violation of Block 5 ("everything is genome"). | All lineages have the same "translation machinery" regardless of genome; no evolution of the ribosomal machinery. | Phase 29 |
| **L1.5** | Conjugation: `hgt.ex` uses only the count of `:transmembrane_anchor` as a proxy for the sex pilus. **The prescribed triad** `pili_like + relaxase_like + oriT_like` **is absent**. | Mobilizable plasmids (require relaxase but not pili) cannot be distinguished from self-conjugating ones; entry exclusion and compatibility groups have no molecular basis. | Phase 28 |
| **L1.6** | SOS: `@sos_active_threshold = 0.20` is a **module-level** constant in `mutator.ex:86`, not derived from `:ligand_sensor(target: :dna_damage)` domains expressed in the lineage. | DNA-damage sensitivity does not evolve; all lineages share the same threshold. Anti-realistic for anyone familiar with LexA/RecA regulation. | Phase 25 |
| **L1.7** | R-M (`defense.ex`): opaque 4-codon `signal_key` values represent recognition sites. **No nucleotide sequence model**, no distinction between Type I / II / III. Methylation tracked as a list of keys (no per-nucleotide). | Restriction enzyme specificity is not inspectable at sequence level; methylation is not visualisable as a pattern. | Phase 28 (partial: N-codon tag-sequence) |

### L2. Missing audit events (silent mechanisms)

Status of the 14 audit-event categories identified in the user reviews. `✅` = closed (event emitted, persisted via `Arkea.Persistence.AuditWriter`, visible in the ledger).

| ID | Event | Emitting file | Status |
|---|---|---|---|
| **L2.1** | `conjugation` (conjugation channel, derived from `hgt_transfer` with `payload.channel == "conjugation"`) | `hgt.ex` | ✅ Closed Phase 21 — kind promotion in `Arkea.Views.HGTLedger` |
| **L2.2** | `:transformation_event` | `hgt/channel/transformation.ex:252` | ✅ Closed pre-Phase 21 (Sub-task 1.2 remediation) |
| **L2.3** | `:transduction_event` | `hgt/phage.ex:598` | ✅ Closed pre-Phase 21 (Sub-task 1.3 remediation) |
| **L2.4** | `:phage_infection` (adsorption + injection, distinct from `:phage_burst`) | `hgt/phage.ex:713` | ✅ Closed pre-Phase 21 (Sub-task 1.3 remediation) |
| **L2.5** | `:rm_digestion` (R-M cleaves unmethylated foreign DNA) | `hgt/phage.ex:724` | ✅ Closed pre-Phase 21 (Sub-task 1.3 remediation) |
| **L2.6** | `:plasmid_displaced` (incompatibility or entry exclusion) | `hgt.ex:381` | ✅ Closed pre-Phase 21 (Sub-task 1.4 remediation) |
| **L2.7** | `:bacteriocin_kill` (with killer/target lineage pair) | `bacteriocin.ex` | ✅ Closed pre-Phase 21 (Sub-task 1.5 remediation) |
| **L2.8** | `:sos_active` (off→on transition when `dna_damage` crosses `Mutator.sos_active_threshold/0`) | `tick.ex` `detect_sos_transitions/3` | ✅ Closed Phase 21 |
| **L2.9** | `:mutator_emergence` (child with `repair_efficiency < 0.10` from parent with `repair_efficiency >= 0.30`) | `tick.ex` `detect_mutator_emergences/3` | ✅ Closed Phase 21 |
| **L2.10** | `:error_catastrophe_death` (Eigen criterion exceeded) | `mutator.ex` | ✅ Closed (writer + emit ready; reachable only synthetically by Eigen-faithful design) |
| **L2.11** | `:biofilm_formation` / `:biofilm_dispersal` (child with `biofilm_capable?` differing from parent) | `tick.ex` `detect_biofilm_transitions/3` | ✅ Closed Phase 21 |
| **L2.12** | `:migration_pulse` (per-receiving-biotope aggregate: `lineage_cells`, `metabolite_mass`, `signal_mass`, `phage_particles`) | `biotope/server.ex` `apply_migration` | ✅ Closed Phase 21 |
| **L2.13** | `:domain_flip` (mutation in `type_tag` changes domain category) | `genome/mutation/applicator.ex` | ❌ Pending Phase 26 |
| **L2.14** | `:gene_chimera_birth` (translocation fuses two genes) | `genome/mutation/applicator.ex` | ❌ Pending Phase 26 |

**Current status**: 12/14 closed. Phase 21 Top 5 #1 added the "Known v1 limitations" section; Top 5 #2 closed L2.1 (kind promotion of the `conjugation` channel in the view layer); Top 5 #3 closed L2.8/9/11/12 (`:sos_active`, `:mutator_emergence`, `:biofilm_formation`/`_dispersal`, `:migration_pulse` renamed from the previous `:migration`). L2.2-L2.7 and L2.10 were already closed by pre-Phase 21 remediation (Sub-tasks 1.2-1.6) but not documented as such — earlier updates aligned the documentation to the real state of the code. Only L2.13, L2.14 remain, closed in Phase 26 (codon-level events).

### L3. Limited player interventions

Only 4 interventions are available in `Intervention.apply/2`, all at the phase level:

- `:nutrient_pulse` with fixed mix `{glucose, nh3, po4}` (no metabolite choice)
- `:plasmid_inoculation` with a hardcoded 1-gene model plasmid (not customisable)
- `:xenobiotic_pulse` with only `:beta_lactam` exposed in the UI (the `target_class` framework is generative)
- `:mixing_event` (phase homogenisation)

**Missing**: guided mutagenesis, knockout / knockdown, heterologous expression, UV/MMS-like mutagenic pulse, environment shift (pH/T/osmolarity), inoculation of a lineage observed elsewhere, scheduled temporal dosing, aminoglycoside/fluoroquinolone/polymyxin xenobiotics.

**Closure**: Phase 27 (Advanced interventions).

### L4. Missing analysis tools

Data exist in `phenotype.ex` and in the snapshot export, but **live views are absent**:

- ✅ **Trait tracker time-series** for macro phenotype (one or more selected lineages) — *Closed Phase 21 Top 5 #4*: `kind: "phenotype_trait"` samples persisted every `cell_sampling_period` ticks (default 10), payload carries 10 scalar/boolean traits (`base_growth_rate`, `repair_efficiency`, `energy_cost`, `dna_binding_affinity`, `competence_score`, `hydrolase_capacity`, `efflux_capacity`, `structural_stability`, `n_transmembrane`, `biofilm_capable`); `Arkea.Views.PopulationTrajectory.build_trait/3` builds the multi-lineage series; UI `SimLive` Trends tab exposes a trait selector.
- Per-gene per-tick expression (today `Phenotype.from_genome/1` aggregates everything into global scalars) — Phase 25
- ✅ **Genome diff between two lineages** (macro level: shared vs unique genes / plasmids / prophages + phenotype Δ) — *Closed Phase 22 / 2.3a*: `Arkea.Views.GenomeDiff.build/2` partitions chromosome, plasmids and prophages into `{shared, a_only, b_only}` using identity based on `:erlang.phash2(gene.codons)` (immune to the random UUID v4s of `Gene.id`); plasmid identity = `{inc_group, sorted gene signatures}`; phenotype delta over 7 scalars + `biofilm_capable_changed` flag. UX in `lineage_drawer`: "Pin as compare" button + inline "Genome diff vs ⟨pinned⟩" section once both lineages are pinned. Codon-level diff (per-position Δ, domain flips) remains deferred to Phase 26.
- ✅ **Metabolic map of the biotope** (heatmap of 13 metabolites × phases with per-row normalisation) — *Closed Phase 22 / 2.4*: `Arkea.Views.MetabolicMap.build/1` returns `{phases, metabolites, rows, biotope_max}` with one row per canonical metabolite (ordered by cycle: C → C1 → acceptors/donors → N → S → micronutrients) and `cells` with `intensity ∈ 0.0..1.0` normalised *per-row* (the sulfur cycle stays legible next to glucose). Rendered in the `SimLive` Chemistry tab with chemistry-correct labels (CO₂, H₂S, SO₄²⁻, Fe²⁺/³⁺, etc.) and a tooltip with the raw value. Inter-lineage fluxes (cross-feeding visualisation) remain deferred to Phase 22 stretch / Phase 25.
- Molecular regulatory network (`:dna_binding` + `:regulator_output` → target promoter) — Phase 25
- Codon-level viewer (zoom: chromosome → operon → gene → 50–200 codons on alphabet-20) — Phase 26
- Mutation hotspot map per gene — Phase 26
- ✅ **Phenotypic distribution of the biotope** (abundance-weighted strip plot with centre-of-mass line) — *Closed Phase 22 / 2.8*: `Arkea.Views.PhenotypeDistribution.build/3` produces a scatter model `{tick, x_domain, y_domain, weighted_mean, total_abundance, points}` for the selected trait at the latest sampled tick; `Chart.phenotype_distribution` renders it in the Trends tab beneath the time-series. Booleans plot at 0/1, radius ∝ √abundance, dashed vertical line at the abundance-weighted mean. Replaces the canonical violin plot (no kernel density estimation) with a more direct view for the target audience — two visible clusters on the x-axis flag incipient speciation / polarisation.
- Structure–function landscape of a domain (2D scatter `kcat × Km` of all variants) — Phase 26

### L5. Phylogeny — missing capabilities

The dendrogram in `phylogeny.ex` shows lineages, abundance, branch lengths, but:

- No filter by trait (currently colours only by abundance) — Phase 25
- No highlight of phenotypic or domain-level convergences — Phase 25
- Mutation rate per branch not normalised by branch length — Phase 25
- No ancestral reconstruction of the genome or of the ancestral sequence of a gene — Phase 26
- No gene tree distinct from the species tree (HGT as topological incongruence) — Phase 26

### L6. Lab notebook absent

The system exports JSON/CSV/blueprint but:

- No user annotation attachable to a specific tick — Phase 24
- No time-anchored permalinks (link that re-opens the biotope at the state of tick X) — Phase 24
- No event bookmark (with user label, visible on the time-series) — Phase 24
- No replay with scrubbing — Phase 24
- No FASTA-like export (codon sequences) or GFF-like (genome annotation) — Phase 27
- No notebook-ready export (parquet, AnnData) — Phase 24

### L7. What is NOT a limitation (scope clarifications)

To prevent incorrect expectations:

- **No real DNA (ATGC)**: the genome is a sequence of logical codons on alphabet-20, *deliberately* (Block 5 of the design). This is not a gap; it is a scope choice.
- **No real ribosome, no real replisome, no intracellular compartments**: deliberately excluded (see `01-DESIGN.en.md`).
- **No CRISPR/Cas in v1**: deferred to v2 (explicit decision 2026-04-25).
- **No senescence**: bacteria are immortal in v1 (explicit decision).
- **No complete chemolithotrophy (H₂/H₂S/CH₄ as electron donors)**: partial coverage, not a design gap.
- **No finely modelled H₂S/lactate toxicity**: in the backlog, not a design gap.

### Closure roadmap

See `15-MICRO-BIO-MOL-INTEGRATION-PLAN.md` §4 for the full Phase 21 → 29 sequence. Each merged phase updates this section **by removing** the closed entry (single source of truth).

## Recommended primary citations for documentation

- **Imlay JA**. *Cellular defenses against superoxide and hydrogen peroxide*. Annu Rev Biochem 2008.
- **Cooper CE, Brown GC**. *The inhibition of mitochondrial cytochrome oxidase by sulfide*. J Bioenerg Biomembr 2008.
- **Tock MR, Dryden DTF**. *The biology of restriction and anti-restriction*. Curr Opin Microbiol 2005.
- **Chen J et al**. *Genome hypermobility by lateral transduction*. Science 2018.
- **Cascales E et al**. *Colicin biology*. Microbiol Mol Biol Rev 2007.
- **Wommack KE, Colwell RR**. *Virioplankton: viruses in aquatic ecosystems*. Microbiol Mol Biol Rev 2000.
- **Riley MA, Wertz JE**. *Bacteriocins: evolution, ecology, and application*. Annu Rev Microbiol 2002.
- **Eigen M**. *Self-organization of matter and the evolution of biological macromolecules*. Naturwissenschaften 1971.
- **Bull JJ, Meyers LA, Lachmann M**. *Quasispecies Made Simple*. PLOS Comput Biol 2005.
- **Hawver LA et al**. *Specificity and complexity in bacterial quorum-sensing*. FEMS Microbiol Rev 2016.
- **Suttle CA**. *The significance of viruses to mortality in aquatic microbial communities*. Microb Ecol 1994.
- **Stams AJM, Plugge CM**. *Electron transfer in syntrophic communities of anaerobic bacteria and archaea*. Nat Rev Microbiol 2009.
- **Cox MM et al**. *The importance of repairing stalled replication forks*. Nature 2000.
- **San Millán A, MacLean RC**. *Fitness costs of plasmids: a limit to plasmid transmission*. Microbiol Spectr 2018.
- **Novick RP**. *Plasmid incompatibility*. Microbiol Rev 1987.
- **Johnston C et al**. *Bacterial transformation: distribution, shared mechanisms and divergent control*. Nat Rev Microbiol 2014.
- **Smillie CS et al**. *Ecology drives a global network of gene exchange*. Nature 2011.

## Phase 20 calibration changes (changelog)

Phase 20 performed a *scientific calibration pass* to align key constants to biological scales, addressing the P0 points raised in the post-Phase 19 scientific review.

### Bug fix
- **Inverted receptor matching** (`phage.ex:778-786` post-fix): the pre-Phase 20 fallback `phenotype.surface_tags == []` accepted infection on lineages without tags — the opposite of real biology. Phase 20 explicitly requires `:phage_receptor` in `surface_tags`. Loss-of-receptor mutants now escape correctly.

### Calibration updates
- `@cleave_p`: 0.70 → 0.95 (R-M efficiency 95–99 % per site, Tock & Dryden 2005)
- `@sos_active_threshold`: 0.50 → 0.20 (SOS near-immediate in vivo, Cox 2000)
- `oxygen` toxic threshold: 200 → 50 (obligate anaerobes discriminated, Imlay 2008)
- `@transduction_probability`: now `Application.compile_env`-tunable (default 0.05 amplified; override for scientific benchmarks). **Post-Review-2 (Task 6)**: default lowered to 0.005 — still above the literature ceiling for canary visibility, but by 1 order of magnitude rather than 3.

### New Phase 20 mechanisms
- **Aerobic ATP upregulation** (`Metabolism.aerobic_boost_factor/1`): multiplicative boost `1 + 7 × oxygen_share` on organic substrates (`:glucose`, `:acetate`, `:lactate`, `:ch4`) when co-uptaken with O₂. Surface aerobic vs anaerobic niche now distinct.
- **ROS-coupled DNA damage** (`Mutator.ros_damage_increment/1`): unprotected cells under oxidative stress accumulate DNA damage independently of replication. SOS trigger also fires in starvation/stationary phase.
- **Derived cassette repressor_strength**: `Phage.derive_repressor_strength/1` now computes repressor_strength from the mean `binding_affinity` of the `:dna_binding` domains in the cassette. Cassettes with stronger repressors are more stable in lysogeny — selection on the cI/cro switch is now visible.
