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
| **L1.1** | `Gene.promoter_block` and `Gene.regulatory_block` are `nil` in Phase 1 (parsing deferred to generative Phase 3). | Promoters and riboswitches are not inspectable, do not mutate, and do not drive expression. The "regulation" advertised in the manual is reduced to a global scalar. | ✅ **Closed Phase 25 / 7.3 (parser) + Phase 31 / L1.1 (builder)**: the *parser* `Arkea.Genome.Regulation` ships in Phase 25 (`promoter_sites/1` 4-codon stride; `riboswitches/1` 5-codon stride). The *builder* ships in Phase 31: `Gene.from_codons/2` accepts `:promoter_block` and `:regulatory_block` opts that populate the corresponding fields on the resulting Gene; the 1-arity form `from_codons/1` stays backward-compatible (blocks default to `nil`). The operon-aware runtime σ (Phase 25.5 / 7.2b) consumes the parsed structures when the blocks are populated. |
| **L1.2** | `:regulator_output` is parsed (mode, cooperativity) but **not aggregated** into a multi-component σ-factor. | Mutations in `:regulator_output` have no observable effect on target expression. | ✅ **Closed Phase 21 #5 (structurally)** — `Phenotype.regulatory_outputs` aggregates each gene carrying `:regulator_output`, enriching mode/cooperativity with the `binding_affinity` of any co-located `:dna_binding` and the `signal_key` of any co-located `:ligand_sensor`; `Phenotype.sigma_factor_components/1` produces a summary `{net_activation, total_activation, total_repression, n_activators, n_repressors}`; new trait `regulatory_net_activation` exposed via TimeSeries + Trends tab; `regulatory_outputs` + `sigma_factor_components` fields exposed in the snapshot export. **Runtime σ wiring deliberately deferred**: `step_expression/1` still uses `dna_binding_affinity` as a single scalar to preserve Phase 5/6/7 calibration. Runtime cabling in the regulatory network = Phase 25. |
| **L1.3** | `Gene.operon_id` is a data field (UUID) but **the module `Arkea.Genome.Operon` does not exist**, nor does a coordinated-expression runtime. Genes under the same operon are not co-transcribed. | The operon as a regulatory unit does not function; the manual must not use it as an operational concept. | ✅ **Closed Phase 25 / 7.2a + Phase 25.5 / 7.2b**: `Arkea.Genome.Operon` module (Phase 25) provides the *structural surface* (`operons/1`, `solo_genes/1`, `containing/2`, `same_operon?/3`, `leader_gene/2`). Runtime σ-coordination (Phase 25.5) via `Phenotype.operon_aware_sigma_input/2`: for genomes with explicitly populated `operon_id` tags the σ-input is the mean across *transcriptional units* (operons + solo genes), where each operon contributes only the leader gene's `dna_binding_affinity` (5 `:dna_binding` domains in one operon = 1 transcription event, not 5). `compute_growth_deltas_v5` consumes `operon_aware_sigma_input` instead of `dna_binding_affinity`. For genomes without explicit operons the fallback is the legacy mean (preserves Phase 5/6/7 calibration). |
| **L1.4** | `ribosome_like = 1.0` is **hardcoded** in `phenotype.ex:291`, in violation of Block 5 ("everything is genome"). | All lineages have the same "translation machinery" regardless of genome; no evolution of the ribosomal machinery. | ✅ **Closed Phase 29 / 29.1**: `Phenotype.translation_efficiency/1` derives a `0..1` scalar from the genome's ribosome-like proxy composition (`:structural_fold` with `multimerization_n >= 4` co-located with `:catalytic_site` `reaction_class :ligation`). Per-gene quality = `(stability / 0.57) × (kcat / 10.0)`, clamped; cell-level efficiency = `max` across ribosome-like genes (the best ribosome paces the cell). `Tick.compute_growth_deltas_v5/5` multiplies the `net` growth term by `translation_efficiency`, making mutations in ribosomal domains a *selectable trait* — closes the Block-5 violation. Genomes without the proxy fall through to `1.0` (preserves Phase-5/6/7 calibration; gate-with-fallback pattern, same as Phase 25.5). |
| **L1.5** | Conjugation: `hgt.ex` uses only the count of `:transmembrane_anchor` as a proxy for the sex pilus. **The prescribed triad** `pili_like + relaxase_like + oriT_like` **is absent**. | Mobilizable plasmids (require relaxase but not pili) cannot be distinguished from self-conjugating ones; entry exclusion and compatibility groups have no molecular basis. | ✅ **Closed Phase 28 / 28.1**: the triad now *gates* the conjugation runtime. `HGT.self_conjugative?/1` requires `pili_strength > 0` (count of `:transmembrane_anchor` domains on plasmid genes) AND `relaxase_strength > 0` (plasmid genes co-encoding `:dna_binding` + `:catalytic_site` with `reaction_class :hydrolysis`) AND `oriT_present` (intergenic block `transfer: ["orit_site"]`). `HGT.mobilizable?/1` distinguishes relaxase+oriT-only plasmids (e.g. ColE1) from pili-only plasmids — a biologically meaningful gateway distinction (Smillie et al. 2010). `HGT.helper_plasmid/2` finds a self-conjugative plasmid co-resident in the donor cell that can supply the pilus apparatus to a mobilizable plasmid; helper-mediated transfers are tagged `transfer_mode: :mobilized` in the audit event vs `:self_conjugative` for triad-complete transfers. The throughput strength factor remains the *pili count* (Phase 5/6/7 calibration preserved); `@mobilisation_efficiency = 0.5` applies a realistic penalty to helper-mediated transfers. |
| **L1.6** | SOS: `@sos_active_threshold = 0.20` is a **module-level** constant in `mutator.ex:86`, not derived from `:ligand_sensor(target: :dna_damage)` domains expressed in the lineage. | DNA-damage sensitivity does not evolve; all lineages share the same threshold. Anti-realistic for anyone familiar with LexA/RecA regulation. | ✅ **Closed Phase 25.5 / 7.6**: `Mutator.sos_threshold/1` reads `:ligand_sensor` domains with `signal_key == "dna_damage"` (LexA-like SOS sensor) and computes `min(threshold) × Lineage.dna_damage_max()` as the lineage's absolute threshold (most-sensitive sensor wins, OR-gate over SOS-boxes). When the genome has no SOS sensor, the fallback is the legacy constant (`@sos_active_threshold = 0.20`). The three runtime call sites (`Tick.detect_sos_transitions`, `Tick.apply_spawn_outcome`, `HGT.lysogeny_induction_check`) now use the per-lineage threshold via `sos_active?(damage, threshold)`. |
| **L1.7** | R-M (`defense.ex`): opaque 4-codon `signal_key` values represent recognition sites. **No nucleotide sequence model**, no distinction between Type I / II / III. Methylation tracked as a list of keys (no per-nucleotide). | Restriction enzyme specificity is not inspectable at sequence level; methylation is not visualisable as a pattern. | ✅ **Closed Phase 30 (view) + Phase 31 (sequence-level matching) + Phase 32 (refinements)**: Phase 30 ships `RecognitionSite` struct (full 20-codon pattern + Type I/II/III classification), `Phenotype.rm_profiles_detailed/1`, and `Views.RestrictionInspector` for UI inspection. Phase 31 closes the runtime loop: `RecognitionSite.methylated_positions :: MapSet` tracks per-codon-position methylation; `RecognitionSite.protected_by?/2` validates full coverage (signature + pattern equality + per-position `MapSet.subset?`). `Defense.restriction_check_sequence/3` (and its virion variant) matches at sequence level with per-position protection. `Virion.methylation_sites` and `DnaFragment.methylation_sites` carry rich profiles from the burst donor. `Phage.run_rm_and_outcome/5` prefers the sequence-level path when both sides carry rich data, falling back to the legacy 4-codon signature path when one or both are empty (preserves Phase-12 calibration for pre-Phase-31 virions / delta-encoded lineages). Phase 32 adds the biologically realistic refinements: **(a) codon-complement involution** `c → 19 - c` plays the role of the Watson-Crick base-pair complement; `palindrome_kind/1` returns `:exact | :complement | :none`, and `classify_type/2` now captures Type II reverse-complement palindromes (textbook EcoRI shape `5'-GAATTC-3'`); **(b) kcat-modulated partial methylation** — `scale_methylation_to_kcat/2` scales `methylated_positions` proportionally to the methylase's `:catalytic_site.kcat` (range `0..10`): a degraded methylase methylates only the leading 5'→3' positions, so restriction enzymes can still cleave the trailing positions; `Phenotype.rm_profiles_detailed/1` applies the scaling automatically. |

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
| **L2.13** | `:domain_flip` (mutation in `type_tag` changes domain category) | `genome/mutation/applicator.ex` | ✅ Closed Phase 26 (1.13) |
| **L2.14** | `:gene_chimera_birth` (translocation fuses two genes) | `genome/mutation/applicator.ex` | ✅ Closed Phase 26 (1.14) |

**Current status**: **14/14 closed** (Phase 26 closes the last two). `Applicator.detect_mutation_events/4` compares old/new genome after every `apply/2` and produces a `:domain_flip` per position whose `Domain.type` changed plus a `:gene_chimera_birth` for every successful `Translocation`; events flow through `Tick.attempt_spawn` → `pending_events` → `AuditWriter` → audit_log with channel-direct shapes (`gene_id`, `domain_index`, stringified `from_type`/`to_type` for flips; `source_gene_id`, `dest_gene_id`, `codons_moved` for chimera).

### L3. Limited player interventions

✅ **Closed Phase 27 (Advanced player interventions)** — `Intervention.apply/2` now exposes 9 commands (4 pre-Phase-27 + 5 new), all pure transforms on `BiotopeState` with typed audit events. The xenobiotic catalog covers 4 target classes (PBP, ribosome, gyrase, membrane) with 4 antibiotics.

**Pre-existing**:
- `:nutrient_pulse` with fixed mix `{glucose, nh3, po4}` (fixed mix retained as a deliberate v1 choice: generic "buffet" pulse).
- `:plasmid_inoculation` with a hardcoded 1-gene model plasmid (still v1 — the `:lineage_inoculation` of 27.5 supersedes this for custom genomes).
- `:xenobiotic_pulse` (Phase 27 / 27.1): catalog extended with `:beta_lactam` + `:aminoglycoside` (`:ribosome_like`, cidal) + `:fluoroquinolone` (`:dna_polymerase_like`, mutagen — Cirz et al. 2005, antibiotic-induced mutagenesis) + `:polymyxin` (`:membrane`, cidal — Velkov 2010). `dose` and `xenobiotic_id` are command parameters.
- `:mixing_event` (phase homogenisation).

**Phase 27 new**:
- ✅ `:mutagen_pulse` *(27.2)* — UV / MMS-like, dose as a fraction of `Lineage.dna_damage_max/0`. Hits every lineage resident in the phase, clamped at cap. Emits per-lineage `:dna_damage_pulse` + umbrella `:intervention`.
- ✅ `:environmental_shift` *(27.3)* — updates `temperature` / `ph` / `osmolarity` / `dilution_rate` of a phase, validated against `Phase.validate/1`. Out-of-range values rejected with `{:error, :temperature_out_of_range}` etc.
- ✅ `:gene_knockout` *(27.4)* — zeros the codons of a target chromosome gene, preserving codon count (grammar invariant: multiple of 23). The rebuilt domains parse to `:substrate_binding` with all-zero params (non-functional gene: kcat=0, affinity=0). Phenotype cache invalidated.
- ✅ `:lineage_inoculation` *(27.5)* — introduces a user-supplied genome as a new founder lineage at the current tick. "Save & retry" workflow. Genome validated; abundance > 0; optional `:original_seed_id` for Community Mode tagging.

**Phase 32 orchestration layer**: ✅ `:scheduled_dosing` closed via `Arkea.Sim.Intervention.Scheduler.schedule/1` + `Arkea.Sim.Intervention.ScheduledDosingWorker` (Oban worker, queue `:scheduled_dosing`). `Scheduler.schedule/1` validates the command and enqueues it with biotope_id + due_tick. The worker is poll-style: if the biotope has reached due_tick → `BiotopeServer.apply_intervention/2`; otherwise → `{:snooze, 30s}` retry. Biotope no longer running → `{:cancel, :biotope_not_running}`. v1: single-shot only (no recurrence); tick-based (no wall-clock); cancellation client-side via `Oban.cancel_job/1`.

**Still deferred**: heterologous single-gene injection as a dedicated surgical command — the current workflow uses `:lineage_inoculation` with a custom genome (functionally equivalent), but no dedicated "inject this single gene into an existing lineage" command exists.

### L4. Missing analysis tools

Data exist in `phenotype.ex` and in the snapshot export, but **live views are absent**:

- ✅ **Trait tracker time-series** for macro phenotype (one or more selected lineages) — *Closed Phase 21 Top 5 #4*: `kind: "phenotype_trait"` samples persisted every `cell_sampling_period` ticks (default 10), payload carries 10 scalar/boolean traits (`base_growth_rate`, `repair_efficiency`, `energy_cost`, `dna_binding_affinity`, `competence_score`, `hydrolase_capacity`, `efflux_capacity`, `structural_stability`, `n_transmembrane`, `biofilm_capable`); `Arkea.Views.PopulationTrajectory.build_trait/3` builds the multi-lineage series; UI `SimLive` Trends tab exposes a trait selector.
- ✅ **Per-gene expression (view layer + runtime σ)** — *Closed Phase 25 / 2.2 (view) + Phase 25.5 / 7.2b (runtime)*: `Arkea.Views.GeneExpression.derive(genome, signal_pool)` returns `[%{gene_id, base_level, modulation, expression}]` per chromosome gene (view-layer self-modulation). The *runtime* σ is now operon-aware via `Phenotype.operon_aware_sigma_input/2` (Phase 25.5): for genomes with explicitly populated operons the σ-input collapses multi-`:dna_binding` operons to a single transcriptional unit (leader-driven). The `kind: "gene_expression"` time-series sample (per-tick persistence) remains additive for when the Trends tab consumer is ready.
- ✅ **Genome diff between two lineages** (macro level: shared vs unique genes / plasmids / prophages + phenotype Δ) — *Closed Phase 22 / 2.3a*: `Arkea.Views.GenomeDiff.build/2` partitions chromosome, plasmids and prophages into `{shared, a_only, b_only}` using identity based on `:erlang.phash2(gene.codons)` (immune to the random UUID v4s of `Gene.id`); plasmid identity = `{inc_group, sorted gene signatures}`; phenotype delta over 7 scalars + `biofilm_capable_changed` flag. UX in `lineage_drawer`: "Pin as compare" button + inline "Genome diff vs ⟨pinned⟩" section once both lineages are pinned. **Codon-level diff** (per-position Δ, domain flips) — *Closed Phase 26 / 2.3b*: `Arkea.Views.GeneDiff.build/2` zooms in on a pair of homologous genes and produces per-codon `{change, role, domain_index}` + per-domain summary (type_a/b, type_changed?, substitutions_in_tag/in_params). Positional alignment v1; true indel-aware alignment requires 3.7-precise.
- ✅ **Metabolic map of the biotope** (heatmap of 13 metabolites × phases with per-row normalisation) — *Closed Phase 22 / 2.4*: `Arkea.Views.MetabolicMap.build/1` returns `{phases, metabolites, rows, biotope_max}` with one row per canonical metabolite (ordered by cycle: C → C1 → acceptors/donors → N → S → micronutrients) and `cells` with `intensity ∈ 0.0..1.0` normalised *per-row* (the sulfur cycle stays legible next to glucose). Rendered in the `SimLive` Chemistry tab with chemistry-correct labels (CO₂, H₂S, SO₄²⁻, Fe²⁺/³⁺, etc.) and a tooltip with the raw value. Inter-lineage fluxes (cross-feeding visualisation) remain deferred to Phase 22 stretch / Phase 25.
- ⚠️ **Molecular regulatory network (view-only)** — *Closed Phase 25 / 2.5 (view layer)*: `Arkea.Views.RegulatoryNetwork.build/1` returns `{nodes, edges, gene_count, operon_count, regulator_count, riboswitch_count}` consuming three structural surfaces (regulatory_outputs of 7.1, operons of 7.2a, riboswitches of 7.3). Node kinds: `:gene`, `:operon`, `:metabolite`, `:signal`. Edge kinds: `:operon_member` (gene→operon, leader flag), `:regulator_output` (genome→signal, mode), `:riboswitch` (metabolite→gene, mode). Pure data shape — the UI consumer (network diagram in the Phylogeny tab or a dedicated panel) ships in a polish phase. The σ-coordination runtime consumes the same structures in 7.2b.
- ✅ **Codon-level viewer** (zoom: chromosome → operon → gene → 50–200 codons on alphabet-20) — *Closed Phase 26 / 2.6*: `Arkea.Views.CodonViewer.build/1` annotates every codon with its *role* (`:type_tag` for the 3 codons that select the domain category, `:parameter_codon` for the 20 that parameterise its continuous traits, `:promoter_codon`/`:regulatory_codon` for the optional blocks); also returns a per-domain summary with `start`/`end_pos`/`type`/`params`. The UI consumer is separate; the view layer is pure and direct.
- ✅ **Mutation hotspot map per gene** — *Closed Phase 26 / 2.7*: `Arkea.Views.MutationHotspot.build/2` aggregates per-codon `domain_flip` events (spread `+1` across the 23 codons of the affected domain) and `gene_chimera_birth` events (bump on the last codon as a coarse v1 representative) from the audit list; output `bins[codon_index] = {count, contributors}` ready for a heatmap track aligned with the CodonViewer. Per-position precision requires 3.7 (ancestral reconstruction).
- ✅ **Phenotypic distribution of the biotope** (abundance-weighted strip plot with centre-of-mass line) — *Closed Phase 22 / 2.8*: `Arkea.Views.PhenotypeDistribution.build/3` produces a scatter model `{tick, x_domain, y_domain, weighted_mean, total_abundance, points}` for the selected trait at the latest sampled tick; `Chart.phenotype_distribution` renders it in the Trends tab beneath the time-series. Booleans plot at 0/1, radius ∝ √abundance, dashed vertical line at the abundance-weighted mean. Replaces the canonical violin plot (no kernel density estimation) with a more direct view for the target audience — two visible clusters on the x-axis flag incipient speciation / polarisation.
- ✅ **Structure–function landscape of a domain** (2D scatter of all variants) — *Closed Phase 26 / 2.9*: `Arkea.Views.DomainLandscape.build/2` walks the entire population (chromosome + plasmids + prophages of every lineage) and produces one point per instance of the requested `domain_type`, annotated with `lineage_id`, `abundance`, `gene_id`, `domain_index`, `replicon`/`replicon_index`, and the domain's `params` map (`kcat`+`reaction_class`+`signal_key` for `:catalytic_site`; `binding_affinity`+`promoter_specificity` for `:dna_binding`; etc.). The consumer chooses which two keys become the X/Y axes — the view is generic over `domain_type`.

### L5. Phylogeny — missing capabilities

The dendrogram in `phylogeny.ex` shows lineages, abundance, branch lengths, but:

- ✅ **Filter by trait on the dendrogram** — *Closed Phase 25 / 3.X*: `Phylogeny.colour_by_trait(model, trait)` annotates every non-synthetic node with `:colour_value` from the `phenotype` map (`:base_growth_rate`, `:repair_efficiency`, `:energy_cost`); the UI consumer can colour the dendrogram by that trait instead of abundance.
- Highlight of phenotypic or domain-level convergences — *partially enabled Phase 26 / 3.6+3.7+3.8*: ancestral reconstruction and gene tree are now available (see entries below); the convergence-highlight marker on the dendrogram remains UI polish (Phase 26+ stretch).
- ✅ **Per-branch mutation rate (proxy)** — *Closed Phase 25 / 3.X*: `Phylogeny.enrich_with_branch_metrics(model, audit)` adds `:phenotype_displacement = |Δgrowth| + |Δrepair| + |Δenergy_cost|` per node (proxy for "phenotypic shift per branch", divide by `branch_length` for the mutator-style intensity). Not the per-position mutation count (would need a sub/indel/dup/inv breakdown in the `mutation_summary` audit, currently absent — TODO 3.4-precise).
- ✅ **Per-branch HGT rate** — *Closed Phase 25 / 3.X*: same enrichment adds `:hgt_received` per node (count of `hgt_transfer` audit entries with `target_lineage_id == node.id`); identifies HGT-hub lineages.
- ✅ **Ancestral reconstruction of genome + gene sequence** — *Closed Phase 26 / 3.6+3.7*: `Arkea.Views.AncestralReconstruction.genome_trace/2` walks the `parent_id` chain from target lineage to root and produces one entry per ancestor with `gene_count`, `plasmid_count`, `prophage_count`, `genome_present?`; `gene_trace/3` zooms on a `gene_chromosome_index` position and returns codon sequence + type + params per ancestor (with `:lost` marker if the ancestor has a shorter chromosome, `:delta_only` if delta-encoded). v1 exploits resident ancestor genomes — this is NOT true phylogenetic state inference on unsampled internal nodes (Felsenstein/parsimony, deferred to Phase 30+).
- ✅ **Gene tree distinct from the species tree (HGT as topological incongruence)** — *Closed Phase 26 / 3.8*: `Arkea.Views.GeneTree.build/2` clusters lineages by gene similarity (greedy single-linkage on p-distance, default threshold `0.05`) and annotates each cluster with `topology: :singleton | :congruent | :incongruent` by comparing the members' MRCA against its subtree in the species tree. A cluster is `:incongruent` when non-member lineages descend from the MRCA — the classical HGT signature (Doolittle 1999). v1 surfaces raw clustering + congruence flag; full gene-tree↔species-tree reconciliation with per-edge gain/loss/transfer ships in Phase 30+.

### L6. Lab notebook absent

The system exports JSON/CSV/blueprint but:

- ✅ **User annotation attachable to a specific tick** — *Closed Phase 24 / 6.1*: `biotope_annotations` table (uuid, biotope_id, player_id, tick, body, timestamps); `Arkea.Notebook` context with `list_for_biotope/1`, `create/4`, `delete/2` (author-only); "Notebook" panel as the 7th bottom tab of the biotope viewport with an entry form and a per-tick list.
- ✅ **Time-anchored permalinks** (link that re-opens the biotope at a specific tick) — *Closed Phase 24 / 6.2 (banner-only v1)*: URL `/biotopes/:id?at=N` parsed by `SimLive.handle_params/3` and validated (integer ≥ 0); cyan-amber banner above the scene shows the pinned tick + the list of annotations/bookmarks attached to that tick + a "Jump to live" button. The tick chip on each notebook entry is now a clickable `?at=N` permalink. **v1 limitation**: the viewport does NOT rebuild the historical state for the pinned tick (it keeps showing the live state); full historical *replay scrubbing* is 6.4. Enough to share "look at my note at tick 1827" — the recipient sees the note highlighted.
- ✅ **Event bookmark (with user label, visible on the time-series)** — *Closed Phase 24 / 6.3*: `bookmark :: boolean` field added to `biotope_annotations` (default false, partial index `WHERE bookmark = true` for fast lookups); `Notebook.toggle_bookmark/2` flips the flag (author-only); `Notebook.list_bookmarks_for_biotope/1` returns only flagged notes; `PopulationTrajectory.build/3` and `build_trait/4` accept the bookmarks list as the third/fourth argument and render them as vertical markers on the Trends chart (solid amber line vs the dashed audit-derived ones); UI in the Notebook panel: ★/☆ button next to delete for toggling.
- ✅ **Historical replay via permalink** — *Closed Phase 24 / 6.4 (basic-replay v1)*: `Arkea.History.fetch_state_at(biotope_id, tick)` reconstructs the closest-before-N `BiotopeState` using, in order: WAL exact match → snapshot ≤ N → WAL ≤ N. `SimLive` on `?at=N` replaces the live `sim_state` with the historical rebuild, rebuilds the phenotype cache from scratch (no `BiotopeServer` round-trip), and freezes live tick broadcasts (`handle_info({:biotope_tick, …}, %{pinned: not nil})` short-circuits). Banner shows the effective rebuild tick if it differs from N (older snapshot). **v1 limitation**: no continuous scrubbing slider on the time-series (the user navigates tick-by-tick via permalink); slider UI ships later if needed.
- No FASTA-like export (codon sequences) or GFF-like (genome annotation) — Phase 27
- ✅ **Notebook-ready export** — *Closed Phase 24 / 6.8*: two new API endpoints. `GET /api/biotopes/:id/notebook-export.csv` returns long-format `tick,lineage_id,trait,value` (boolean → 0/1, numeric scalars as-is), directly consumable with `pandas.read_csv` / `polars.read_csv`. `GET /api/biotopes/:id/notebook-export.jsonl` returns NDJSON with `record_type ∈ {annotation, phenotype_trait, audit_event}` discriminator, one record per line (streaming-friendly), consumable with `polars.read_ndjson` or generic readers. `.csv` / `.jsonl` buttons added to the biotope-viewport header. Parquet/AnnData explicitly NOT native (would require Rust NIF or Python interop); the user derives them locally with `pl.read_csv(...).write_parquet(...)`.

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
