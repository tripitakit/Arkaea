> [🇮🇹 Italiano](BIOLOGICAL-MODEL-REVIEW.md) · 🇬🇧 English (this page)

# Arkea biological model — Scientific review and intervention plan

## Context

Arkea is a persistent simulation of proto-bacterial evolution targeted at a biologist/microbiologist audience (target: genuine scientific accuracy, not mere flavour). Phases 0–11 + UI Evolution are complete: the genetic infrastructure (5 mutation types, 11 functional domains, lineage tracking, delta encoding), Michaelis-Menten metabolism over 13 metabolites, 4D Gaussian quorum sensing, intra-biotope phases, inter-biotope migration, and a **first HGT implementation** (plasmid conjugation + stress-driven prophage induction) are all operational.

A thorough scientific review has identified gaps that prevent the model from expressing its full design (DESIGN.md Blocks 5, 7, 8, 13). The gaps fall into three families:

1. **Incomplete HGT**: natural transformation and transduction entirely absent; phage cycle only half-implemented (induction yes, but no free virion release nor infection chain); R-M encodable as domains but not integrated as gating on HGT channels; plasmids without `inc_group` or `copy_number`; audit log schema present but write path missing.
2. **Weak selective pressures**: specific toxicities (O₂ on anaerobes, H₂S on cytochromes, lactate) absent; elemental deficiencies (P/N/Fe/S) non-constraining; xenobiotics/antibiotics absent — without these, RAS is not observable end-to-end and the 11 metabolic strategies of Block 6 do not produce distinct niches.
3. **Missing coupled cellular mechanisms**: continuous biomass (membrane/wall/dna progress) absent, error catastrophe not modeled, SOS response as biologically correct induction trigger not implemented, operons not explicit, bacteriocins absent.

The expected outcome of the plan: close all gaps while preserving the principles of Block 5 (*everything is metabolism, everything is encoded in the genome, no special cases*), so that the model exhibits the evolutionary phenomena described in the "Chronicles of a contested estuary" walk-through: conjugation + selection → resistance, mutator strains → speciation, free phages → arms race with loss-of-receptor, transformation → mobility of non-conjugative plasmids, error catastrophe as the natural upper bound on µ.

**Key choices confirmed by the user**:
- Scope: full review (Phases 12–18).
- SOS: trigger via realistic DNA damage score (no longer ATP deficit only).
- Operons: refactor after HGT (Phase 17), not before.

---

## Guiding principles (binding for every phase)

- **Pure sim core**: no I/O in `Arkea.Sim.*` modules. Persistence remains delegated to the Server via event structs returned by the pure tick.
- **Generative-only**: every new trait derives from existing genome codons or from co-occurrences of already-defined domains. No explicit flag that cannot be derived from the genome.
- **Mandatory property tests**: for each new mechanism at least (a) a *conservation test*, (b) a *monotonicity test*, (c) a *no-special-case test* (random genome without the key domains never triggers the mechanism).
- **`biological-realism-reviewer` validation**: before consolidation (squash onto master) of each phase, parametric ranges must be validated against primary literature; if a test passes only because of a magic number without derivation → stop on merge.
- **DESIGN.md coherence**: every change to the biological architecture must be annotated in DESIGN.md (and DESIGN.en.md via `bilingual-docs-maintainer`).

---

## Phase 12 — R-M defenses and closed phage cycle (P0, blocking prerequisite)

**Objective**: transform the current stress-driven induction into a complete phage cycle (lytic burst → virion release → free phage decay/migration → infection of compatible recipients → lysogenic integration vs immediate lysis) and wire R-M as uniform gating on all HGT channels.

### Genome and data changes

- `Arkea.Genome` — refactor of the `prophages` field from `[[Gene.t()]]` to `[%{genes: [Gene.t()], state: :lysogenic | :induced, repressor_strength: float()}]`. Resolves an explicit TODO at `lib/arkea/genome.ex:27`.
- `Arkea.Ecology.Phase` — promotion of `phage_pool` from `%{binary => non_neg_integer}` to `%{phage_id => %{genome: thin_genome, abundance, decay_age, surface_tag_signature}}`; addition of the `dna_pool` field (for Phase 13).

### New pure modules

- `lib/arkea/sim/hgt/defense.ex` — `restriction_check(payload_genes, recipient_genome, rng) :: {:digested | :passed, rng}`. Reuses the `signal_key` (already present as `String.t()` in the first 4 codons of DNA-binding domains) as cut specificity. Payload methylases (proteins inherited from the donor) bypass the check when the donor shares the signal_key (reproduces the host modification mechanism of Arber-Dussoix).
- `lib/arkea/sim/hgt/phage.ex` — `lytic_burst/2` (produces virions in `phage_pool` + fragments in `dna_pool`), `infection_step/3`, `decay_step/2`. Burst size emerges from the number of `Structural fold (multimerization_n)` in the prophage cassette.

### Tick integration

- Modification to `lib/arkea/sim/hgt.ex`: `induction_step` calls `HGT.Phage.lytic_burst` instead of `apply_lytic_burst`.
- New step `step_phage_infection/1` in `lib/arkea/sim/tick.ex`, positioned between `step_hgt` and `step_environment`. For each virion: surface_tag/sub-tag matching with recipient → R-M check → lysogenic integration (probability from cassette `repressor_strength`) or immediate lysis.
- Extension of `step_environment` with decay of `phage_pool` (half-life ~ a few ticks, to be validated with the realism reviewer) and of `dna_pool`.

### References to existing utilities

- `Arkea.Sim.Intergenic` — `oriT_site` / `integration_hotspot` biases already exist; extend with an analogous `phage_attachment_site` bias for infection.
- `Arkea.Sim.Phenotype.from_genome` — add field `restriction_profile :: [signal_key]` (pre-computed cache to avoid O(M×N) during the check).

### Property tests (in `test/arkea/sim/hgt/`)

- `phage_test.exs`: stress-driven induction preserves `Σabundance + Σvirions` ("information" mass conserved modulo quantified decay rate).
- `phage_test.exs`: lineage with loss-of-receptor (Surface tag mutated outside matching range) has infection probability ≈ 0; converges to stable phenotype after N ticks of phage pressure.
- `defense_test.exs`: payload carrying methylase of the same signal_key bypasses R-M with probability ≥ 0.95; payload without methylase is digested with probability ≥ 0.7 when recipient has restriction enzyme.
- `defense_test.exs` (StreamData): genome without `Catalytic(hydrolysis)` adjacent to `Substrate-binding(DNA-like)` does not block any payload.

### Realism validation

- Burst size in range [10, 500] virions/lysis (biologically plausible).
- Free phage decay rate < biotope dilution rate (virions persist for several ticks).
- Lysogeny probability ~ 0.1–0.4 at baseline stress, → ~0.9 lytic under high stress.

### Critical files touched

- `lib/arkea/genome.ex`, `lib/arkea/ecology/phase.ex`, `lib/arkea/sim/hgt.ex`, `lib/arkea/sim/tick.ex`, `lib/arkea/sim/phenotype.ex`.
- New: `lib/arkea/sim/hgt/defense.ex`, `lib/arkea/sim/hgt/phage.ex`.

---

## Phase 13 — Natural transformation (P0)

**Objective**: introduce the free DNA uptake channel, gated by R-M (Phase 12).

### Competence definition

Emergent trait: a lineage is competent if it co-expresses `:channel_pore (DNA selectivity)` + `:transmembrane_anchor` + `:ligand_sensor` on a dedicated signal_key (proxy for "cAMP-like" signaling). `Phenotype.from_genome` aggregates these into `competence_score :: float()`.

### New pure module

- `lib/arkea/sim/hgt/channel/transformation.ex` — implements the `Arkea.Sim.HGT.Channel` behaviour (see Phase 16 for formalization). Logic: rate ∝ competence × `phase.dna_pool[origin].abundance`. Simplified homology-directed recombination: same `gene_id` in recipient chromosome → allelic replacement; no homology → rejected (except plasmids that re-integrate as plasmid). R-M check before integration.

### Tick integration

- `step_hgt` orchestrates in order: conjugation → transformation → (transduction in Phase 16) → phage_infection.
- Sources of `dna_pool`: phage lysis (Phase 12), cell-wall-deficiency lysis (Phase 14), routine dilution (fraction at each non-selective death).

### Property tests

- `transformation_test.exs`: lineage with competence > threshold and full dna_pool acquires ≥ 1 event per N ticks (on average).
- Conservation: every transformation event consumes 1 unit of abundance from the `dna_pool`.
- R-M gating: recipient with restriction and no matching methylase → 0 acquisitions, regardless of dna_pool size.

### Realism validation

- Transformation rates expected only for genomes mimicking naturally competent families (Streptococcus/Bacillus/Haemophilus-like). Competence threshold not trivially reached by the default seed.
- Rate on the order of 10⁻⁵–10⁻⁷ per cell per generation.

---

## Phase 14 — Specific toxicities, elemental deficiencies, continuous biomass (P0/P1)

**Objective**: add depth to metabolic selective pressures and introduce the continuous biomass balance (prerequisite for error catastrophe in Phase 17).

### Changes to existing modules

- `lib/arkea/sim/metabolism.ex`: new pure functions `toxicity_factor(metabolite_pool, phenotype)` and `elemental_constraints(metabolite_pool, phenotype)`. Each metabolite carries a coded `(toxicity_threshold, toxicity_target)`. Effect: the lineage's global kcat is multiplied by `1 - max(0, [met] - threshold)/scale` when the lineage does not possess a dedicated detoxification enzyme (e.g. catalase-like = `Catalytic(reduction, target=O₂)`).
- Elemental constraints (P, N, Fe, S): minimum uptake floor required for biomass production. Below floor for N ticks → growth block (no fission).

### New module

- `lib/arkea/sim/biomass.ex` — pure functions for `progress(membrane | wall | dna, phenotype, metabolites)`. Accumulated deficits increase lysis probability at division.

### Changes to Lineage

- `lib/arkea/ecology/lineage.ex` — field `biomass :: %{membrane: 0..1, wall: 0..1, dna: 0..1}`.

### Tick integration

- `step_expression` consults `biomass` to gate fission.
- New `step_lysis/1` applies lysis at division (probability from wall/membrane/dna progress deficit).
- `step_metabolism` applies `toxicity_factor` and `elemental_constraints` to the expression delta.

### Property tests

- `toxicity_test.exs`: anaerobic lineage (no O₂ detoxification) in a phase with [O₂] > 0.5 has effective kcat that decreases monotonically with [O₂].
- `biomass_test.exs`: lineage without PBP-like under osmotic pressure accumulates `wall` deficit → lysis probability increases.
- `elemental_test.exs`: in a P-limited phase, lineage without an efficient P transporter does not grow; a mutation reducing Km(P) restores growth.

### Realism validation

- Toxicity constants within biological orders of magnitude (O₂ toxic for obligate anaerobes at > 1 µM equivalent; H₂S on cytochromes consistent with literature).
- Calibrate with the revised seed_scenario; canary test "seed survives 1000 ticks under default conditions".

---

## Phase 15 — Xenobiotics and RAS (P0)

**Objective**: close the "selection → emergent resistance" loop. Without this the model cannot be validated end-to-end.

### Changes to existing modules

- `lib/arkea/ecology/phase.ex` — parallel xenobiotic pool (canonical IDs > 12 to avoid breaking existing lookups) or a separate `xenobiotic_pool`.
- `lib/arkea/sim/phenotype.ex` — field `target_classes :: %{atom() => float()}` (target abundance in the proteome derived from domain composition).

### New module

- `lib/arkea/sim/xenobiotic.ex` — pure module: `target_class` (`:pbp_like | :ribosome_like | :dna_polymerase_like | :membrane | :efflux_target`), `affinity (Kd)`, `mode (:cidal | :static | :mutagen)`. Effect in expression: `[drug] × [target] / Kd` reduces functionality on targets. Mode `:mutagen` raises the lineage's µ (emergent DinB-like).

### Emergent resistances

- β-lactamase-like: `[Substrate-binding(target=xenobiotic_id)][Catalytic(hydrolysis)]` → degrades xenobiotic in the pool.
- Efflux pump: `[Substrate-binding(broad)][Channel/pore][Energy-coupling][Transmembrane]` reduces the effective intracellular concentration (`intracellular_xeno_factor` field in phenotype).

### Tick integration

- Sub-step `xenobiotic_binding/effect` after `step_metabolism`, before `step_expression`.
- `lib/arkea/sim/intervention.ex` — applies xenobiotics from player intervention.

### Property tests

- `xenobiotic_test.exs`: applied β-lactam-like, lineage without β-lactamase and with PBP-like target loses fitness; with β-lactamase gains a selective boost.
- StreamData: after N ticks of constant pressure, mutations restoring fitness (low Km on PBP, presence of β-lactamase, high efflux expression) fix in the survival population.
- End-to-end RAS: seed scenario with a single β-lactamase ancestor → fixation in < N ticks under pressure (N validated against a Lenski-style timeframe).

### Realism validation

- Emergence timescales vs MIC vs mutation frequency consistent with primary literature.

---

## Phase 16 — Plasmid traits and transduction (P1)

**Objective**: complete HGT with (a) advanced plasmid refactor, (b) generalized + specialized transduction built on the phage cycle (Phase 12), (c) audit log write path.

### Advanced plasmids

- `lib/arkea/genome.ex` — refactor of `plasmids` from `[[Gene.t()]]` to `[%{genes: [Gene.t()], inc_group: integer(), copy_number: pos_integer(), oriT_present: boolean()}]` (explicit TODO Block 4:21-22).
- `inc_group` derived from codons of a "rep_like" domain via hash modulo K. Plasmids sharing the same inc_group compete → only one survives (dilution-driven displacement).
- `copy_number` derived from the `regulatory_block` of the rep_like domain (high repressor binding affinity → low copy). Replication cost ∝ copy_number × gene_count; gene-dosage benefit ∝ copy_number in expression.

### Transduction

- `lib/arkea/sim/hgt/channel/transduction.ex` — generalized: during lytic burst packaging, a fraction (~0.3%) of capsids packages random chromosomal DNA instead of viral genome; specialized: during erroneous prophage excision at induction (probability from `:repair_class` of the lysate's repair domains), a virion packages the prophage + adjacent genes.
- Both use the same `phage_infection` flow with a payload type tag that changes integration behavior.

### Formalized HGT.Channel behaviour

- New behaviour `Arkea.Sim.HGT.Channel` with shared callbacks (`donor_pool/2`, `transfer_rate/3`, `integrate/3`).
- Implementations: `Conjugation` (refactor of the current `HGT`), `Transformation` (Phase 13), `Transduction` (this phase), `PhageInfection` (Phase 12).

### Audit log write path

- `lib/arkea/persistence/audit_writer.ex` — handler for new events: `:transformation_event`, `:transduction_event`, `:phage_infection`, `:plasmid_displaced`, `:rm_digestion`, `:bacteriocin_kill`, `:error_catastrophe_death`.
- Pure sim core emits event structs in the tick return value; `Arkea.Sim.Biotope.Server` calls `AuditWriter.persist_async/1`. Batch aggregation to avoid DB explosion (HGT events can number in the thousands per tick); adaptive sampling when rate exceeds a threshold.

### Property tests

- `plasmid_test.exs`: two plasmids sharing the same inc_group in the same lineage → only one survives within N ticks.
- `plasmid_test.exs`: high copy_number produces a gene-dosage benefit, but ATP burden > threshold → observable trade-off (bell-curve of fitness vs copy_number).
- `transduction_test.exs`: chromosomal fragment transduced to a resistant but homology-compatible recipient produces allelic replacement with probability > 0.

### Realism validation

- Transduction rates in range 10⁻⁶–10⁻⁸ per phage particle.

---

## Phase 17 — SOS, error catastrophe, operons, bacteriocins (P1)

**Objective**: close the mutator strain ↔ DNA damage ↔ prophage induction loop, introduce the natural upper bound on µ (error catastrophe), refactor to operons, introduce bacteriocins as a surface_tag arms race.

### SOS response

- `lib/arkea/sim/mutator.ex` — new `dna_damage_score :: float()` per lineage: `µ_current × N_replication × (1 - repair_efficiency)`. Accumulated as state in `Lineage`.
- SOS activates when dna_damage > threshold encoded in a `:ligand_sensor` "DNA-damage-like" domain of the lineage. Effects: (a) raises µ via DinB-like activation, (b) degrades the prophage repressor → induction.
- **Replaces** the ATP-deficit-only trigger of Phase 12 with a biologically correct trigger. `µ_current` can self-amplify (mutator runaway) but selected repair efficiency blocks the amplification.

### Error catastrophe

- `lib/arkea/sim/mutator.ex` — `error_catastrophe_check`: each division with `µ_current > critical_threshold` produces, with probability `1 - (1-p_lethal)^genome_size`, a non-viable offspring. Threshold consistent with Eigen quasispecies theory (genome_size × error_rate ≈ 1).

### Operons

- `lib/arkea/genome/gene.ex` — field `operon_id :: binary | nil`.
- New module `lib/arkea/genome/operon.ex` with the operon concept: genes sharing the same operon_id share a single `regulatory_block` (present only on the first gene). Coordinated expression: kcat of all genes in the operon multiplied by the same effective sigma.
- New systems (R-M, prophage, conjugation, plasmid traits of Phases 12–16) are designed operon-ready: migration to explicit operons is additive and does not break existing behavior.

### Bacteriocins

- `lib/arkea/sim/bacteriocin.ex` — composition `[Substrate-binding(target=surface_tag_class)][Catalytic(membrane_disruption=hydrolysis)]` + `:secreted` flag derived from `n_passes` of the Transmembrane-anchor (n_passes > threshold → secreted).
- In `step_expression`: lineage with a bacteriocin produces it in `phase.toxin_pool`. Effect: target lineages with matching surface_tag sustain `wall_progress` damage proportional to toxin concentration.
- `lib/arkea/ecology/phase.ex` — new `toxin_pool`.

### Property tests

- `sos_test.exs`: lineage with low repair_efficiency and active growth accumulates dna_damage → prophage induction probability increases.
- `error_catastrophe_test.exs`: lineage with artificially raised µ collapses within N ticks (no fixation possible).
- `bacteriocin_test.exs`: two co-resident lineages, one bacteriocin producer targeting the other's surface_tag → extinction of the other within N ticks; surface_tag mutation → recovery.

### Realism validation

- Slope of µ vs error catastrophe vs Eigen's quasispecies threshold.
- Bacteriocin selectivity: target match must be narrow, not broad-spectrum.

---

## Phase 18 — Polish: cross-feeding closure, biofilm, regulator runtime, mixing (P2)

**Objective**: observationally validate the closure of C/N/S/Fe cycles; wire regulator_outputs at runtime; biofilm as a QS-driven switch; Poisson mixing events.

### Cross-feeding closure

- Integration tests: scenario with SO₄²⁻ reducers + H₂S oxidizers in the same biotope produces an emergent closed S cycle; analogous tests for C (acetate/lactate/CO₂/CH₄/H₂), N (NH₃/NO₃⁻), Fe (Fe²⁺/Fe³⁺).
- No new code required if existing pools and fluxes are sufficient; potential tuning of stoichiometric coefficients in `metabolism.ex`.

### Biofilm

- Surface_tag with sub-tag derived from the signal_key → `:adhesin/:matrix/:biofilm` atoms actually produced (currently searched by the UI but never generated).
- QS-driven switch: receiver with threshold reached → matrix-secretion regulator activated (connected to Phase 17 regulator_output).
- Aggregation = local reduction of dilution_rate for biofilm members.

### Regulator runtime

- `:regulator_output` domains (currently defined but unused in expression) finally participate in the sigma of the target gene/operon. Additive match to sigma via adjacent DNA-binding that searches for operons whose regulatory_block matches.

### Mixing event

- `lib/arkea/sim/migration.ex` — rare Poisson events (~10⁻⁴/tick) of massive inter-phase transfer. Player-triggered intervention available as "mixing intervention" at intervention_budget cost.

---

## Phase 19 — Community Mode (advanced mode)

**Objective**: extend the *Seed Lab* into a mode in which the player simultaneously designs and inoculates multiple distinct Arkeon into the same biotope, enabling emergent community ecology — niche partitioning, syntrophy, closed cross-feeding, competitive exclusion, Black Queen Hypothesis. This phase is not part of the core gap-closure plan (Phases 12–18) but a *progressive unlock* built on top of the completed model. Hard prerequisite: **Phase 18** (cross-feeding closure is the mechanic that makes co-cultures non-trivial — without closed C/N/S/Fe cycles a single specialist wins by niche).

### Biological rationale

In nature the vast majority of interesting microbial processes (anaerobic decomposition, nitrification, sulfate reduction coupled with sulfide oxidation, syntrophic methanogenesis, dental biofilm) are carried out by *consortia* of distinct species. Single-species evolution reproduces drift and adaptive sweep, but not real microbial ecology. Community Mode transforms the player from *evolutionary biologist* into *consortium designer + evolutionary biologist*, in line with the target audience (microbiologists/molecular biologists).

### Data model changes

- `Arkea.Game.SeedLibrary` (new module) — player-side store for seed designs. Each entry: `{name, genome :: Genome.t(), description, created_at}`. Persistence via new Ecto table `player_seeds` (player_id, name, genome_blob, description, inserted_at). Configurable cap (default 12 seeds per player).
- `Arkea.Ecology.Lineage` — addition of field `original_seed_id :: binary() | nil` propagated to descendants. Enables cladistic analytics ("does this lineage descend from Seed-A or Seed-B?") without traversing the phylogenetic tree. `nil` for wild residents pre-seeding.

### Multi-seed provisioning

- `lib/arkea/game/seed_lab.ex` extended with `provision_community/3(player, biotope_id, seed_ids)`. Each seed creates an independent founder lineage (`new_founder/3`) with a distinct clade_ref_id. Maximum simultaneous seeds: `@max_community_seeds = 3` (configurable).
- When the player activates Community Mode, the seed lab selector switches from single-radio to multi-checkbox; the UI shows a comparative preview of the emergent traits of the chosen seeds (target_classes, detoxify_targets, hydrolase_capacity, competence_score, n_transmembrane → invariant per cell).

### Progressive unlock (anti-deck-building)

Community Mode is not available from day 1. It unlocks when the player has completed at least *one* of the following milestones:

- **A. Endurance**: has maintained a single-seed colony beyond 500 real ticks.
- **B. Mutator emergence**: in one of their biotopes, a lineage with `repair_efficiency < 0.2` appeared for ≥ 10 ticks (a survived mutator strain).
- **C. Successful HGT**: has received at least 1 `:hgt_transfer` or `:transformation_event` event in their home biotope.

Milestones are tracked via `player_progression` (new schema: `player_id`, `endurance_unlocked_at`, `mutator_unlocked_at`, `hgt_unlocked_at`). When one is satisfied, it unlocks the "Community Designer" tab of the Seed Lab. **Why**: prevents new players from importing pre-packaged diversity, bypassing the evolutionary experience. Preserves Arkea's pedagogical framing (evolution *must* be felt before it can be "engineered" as a community).

### UI viewport changes

- Color palette per founder: each clade_ref_id receives a stable color from `original_seed_id` → hash (consistent across ticks). Differentiated glyph (circle/square/triangle) to visually distinguish the 3 founders.
- Lineage board: new "Per founder" filter that groups lineages by `original_seed_id`. Shows each founder's contribution to the total biotope population (temporal heatmap).
- Phylogenetic compact view: parallel trees per founder (3 small trees instead of 1 large one), highlighting cross-clade HGT events as dashed arcs.

### Carrying capacity and lineage cap

The `@lineage_cap = 100` cap remains. With 3 founders, each starts with 1 lineage; mutation and HGT produce new lineages that compete for slots. Abundance-based pruning (Phase 4) naturally manages the pressure: the three founders compete via metabolism + cross-feeding, and *the community that wins* is the ecologically robust one. This is the game-design signal: **the winner is not the player who inoculates the most seeds, but the one who chose complementary seeds**.

### Extended audit log

- New event `:community_provisioned` emitted when a biotope receives > 1 seed simultaneously. Payload: `[seed_id_1, seed_id_2, seed_id_3]`, `tick_count`.
- New event `:cross_clade_hgt` when an HGT event (any channel) transfers material between lineages with distinct `original_seed_id`. Enables analytics to measure community *connectedness* (healthy communities → high HGT connectivity).

### Integration with Phase 18

Phase 18 must have closed at least these two points for Community Mode to emerge correctly:

- **Cross-feeding stoichiometry**: integration scenario with SO₄²⁻-reducer + H₂S-oxidiser shows a closed S cycle. Without this, two specialists cannot mutually potentiate each other.
- **QS-driven biofilm switch**: without biofilm, sedentary species cannot stably coexist in low-turnover phases.

Phase 18's regulator_output runtime and mixing events are not blockers but refine the dynamics.

### Property tests

- `community_test.exs` (new): 2-seed inoculum where seed-A produces H₂S and seed-B consumes it → after N ticks both founders have abundance > threshold (emergent cross-feeding). Without Phase 18 this test fails — it also serves as a canary for validating closure.
- `community_test.exs`: 2-seed inoculum with identical phenotype → one of the two is excluded within N ticks (neutral selection → stochastic lock-in). Verifies that multi-seed does *not* trivialize competition.
- `seed_library_test.exs`: seed library persistence across restarts, cap respected, cascade deletion.
- `seed_lab_test.exs` (extended): `provision_community/3` with 3 seeds creates 3 founders with distinct clade_ref_id and `original_seed_id` correctly propagated.
- StreamData property: for every multi-seed inoculum, `Σ(abundance per founder)` ≤ `lineage_cap × max_abundance_per_lineage` (no artificial population inflation).

### Realism validation

- **Cross-feeding rates**: 2-seed inoculum scenario (sulfate-reducer + sulfide-oxidiser) must reach a steady state in ~10²–10³ ticks, consistent with timescales observed for syntrophic consortia in chemostat (Stams & Plugge 2009). The `biological-realism-reviewer` must validate that the H₂S → SO₄²⁻ flux is quantitatively within the stoichiometric range.
- **Anti-monoculture invariant**: in 100 random multi-seed inocula, at least 30% must yield persistent communities (≥ 2 founders survive ≥ 100 ticks). Lower ratio = carrying-capacity tuning required.
- **Cross-clade HGT rate**: with 3 distinct founders at least 1 `:cross_clade_hgt` event should emerge per 50 ticks on average (non-isolated communities). Consistent with Smillie et al. 2011 for natural microbiomes.

### Critical files touched

- `lib/arkea/game/seed_library.ex` (new)
- `lib/arkea/game/seed_lab.ex` — `provision_community/3`
- `lib/arkea/game/player_progression.ex` (new) — milestone tracking
- `lib/arkea/persistence/player_seed.ex` (new Ecto schema)
- `lib/arkea/persistence/player_progression.ex` (new Ecto schema)
- `lib/arkea/ecology/lineage.ex` — field `original_seed_id`
- `lib/arkea_web/live/seed_lab_live.ex` — Community Designer tab
- `lib/arkea_web/live/sim_live.ex` — color/glyph per founder, founder filter on lineage board
- `lib/arkea/persistence/audit_writer.ex` — handler for `:community_provisioned`, `:cross_clade_hgt`

### Ecto migrations

- `player_seeds` (player_id, name, genome_blob bytea, description, inserted_at). Unique index `(player_id, name)`.
- `player_progression` (player_id PRIMARY KEY, endurance_unlocked_at, mutator_unlocked_at, hgt_unlocked_at).
- `lineages` ALTER adds `original_seed_id text NULL` with backfill `NULL` for existing wild residents.

### Time estimate

- 2 weeks of development (new UI + schema + multi-seed provisioning) + 1 week of tests/balance/realism reviewer = ~3 weeks total.

### Specific risks

- **Game balance**: with 3 strong founders the player can create "OP" biotopes that dominate the network. Mitigation: the intervention budget limit does not scale with n_seeds; the total throughput of the community is capped by the biotope's carrying capacity.
- **Onboarding regression**: new players may confuse Community Mode with the standard mode. Mitigation: the Community Designer is a *separate* tab, accessible only after unlock; the default flow remains single-seed.
- **Cluttered visualisation**: 3 clades in the viewport can become illegible. Mitigation: density-based clustering in the PixiJS scene (cells visually clustered per founder as separate colour bands, not mixed particles).

---

## Execution sequence and dependencies

```
Phase 12 (R-M + phage cycle) ──┬──→ Phase 13 (Transformation)──┐
                               └──→ Phase 16 (Plasmid+Transd.)──┤
Phase 14 (Toxicity+biomass) ──────→ Phase 15 (Xeno/RAS)─────────┤
                                                               ├──→ Phase 17 (SOS, error cat., operons, bact.)
                                                               │
                                                               └──→ Phase 18 (polish + cycle closure) ──→ Phase 19 (Community Mode)
```

- Phase 12 is blocking for 13 and 16 (Phase 13 uses `dna_pool`; Phase 16 uses `phage_pool` and packaging).
- Phase 14 is blocking for 15 (xenobiotics use biomass for "target abundance") and 17 (error catastrophe uses biomass).
- Phase 17 depends on 12 (SOS-induction) and 14 (error catastrophe).
- **Phase 19 depends on Phase 18** (cross-feeding closure is a prerequisite for community ecology; without it, multi-seed trade-offs degenerate into winner-takes-all).

Estimated time: 1 week of development + property tests + 1 round of biological-realism-reviewer per phase for Phases 12–18 = ~7 weeks. Phase 19 adds ~3 weeks (UI + schema + balance) for a total of ~10 weeks if executed in series.

---

## Critical files touched (summary)

- `lib/arkea/genome.ex` — refactor `prophages` (Phase 12), `plasmids` (Phase 16); addition of `operon_id` on Gene (Phase 17).
- `lib/arkea/ecology/phase.ex` — refactor `phage_pool`, new `dna_pool` (Phase 12), `xenobiotic_pool` (Phase 15), `toxin_pool` (Phase 17).
- `lib/arkea/ecology/lineage.ex` — fields `biomass`, `dna_damage_score` (Phases 14, 17).
- `lib/arkea/sim/hgt.ex` — HGT channel orchestration (refactored across all phases).
- `lib/arkea/sim/tick.ex` — new steps `step_phage_infection`, `step_lysis`, xenobiotic sub-step.
- `lib/arkea/sim/phenotype.ex` — fields `competence_score`, `target_classes`, `restriction_profile`, `intracellular_xeno_factor`.
- `lib/arkea/sim/metabolism.ex` — `toxicity_factor`, `elemental_constraints`.
- `lib/arkea/sim/mutator.ex` — `dna_damage_score`, `error_catastrophe_check`.
- `lib/arkea/sim/migration.ex` — Poisson mixing events.
- `lib/arkea/persistence/audit_writer.ex` — handler for new event types; connection to sim core via Server.

### New pure modules

- `lib/arkea/sim/hgt/defense.ex`, `lib/arkea/sim/hgt/phage.ex`, `lib/arkea/sim/hgt/channel/transformation.ex`, `lib/arkea/sim/hgt/channel/transduction.ex`, `lib/arkea/sim/hgt/channel.ex` (behaviour), `lib/arkea/sim/hgt/plasmid.ex`.
- `lib/arkea/sim/biomass.ex`, `lib/arkea/sim/xenobiotic.ex`, `lib/arkea/sim/bacteriocin.ex`.
- `lib/arkea/genome/operon.ex`.
- **Phase 19**: `lib/arkea/game/seed_library.ex`, `lib/arkea/game/player_progression.ex`, `lib/arkea/persistence/player_seed.ex`, `lib/arkea/persistence/player_progression.ex`.

---

## End-to-end verification

For each phase:

1. **Unit + property tests pass**: `mix test` must remain green after each phase. StreamData property tests with at least 100 runs per invariant.
2. **Benchmark**: for each phase a `bench_*.exs` test (excluded from fast CI) runs 1000 ticks with N=50 lineages and verifies:
   - Average time per tick < 5× pre-phase baseline.
   - Memory does not grow (no leak).
   - Expected events from the new mechanism > 0 and < N (no zeros, no spam).
3. **Canary scenario**: re-run the "Chronicles of a contested estuary" scenario (DESIGN_STRESS-TEST.md) and verify that the expected narrative phenomena are observable with the new implementation (mutator strain, prophage induction + RM/loss-of-receptor defenses, anti-griefing dilution of burdened plasmids, chimera via translocation).
4. **Realism validation**: manual invocation of the `biological-realism-reviewer` agent on the phase diff, before consolidation. Stop on merge if: (a) a mechanism is observationally "special" and does not emerge from the genome, (b) parametric ranges outside biologically known orders of magnitude, (c) a test passes only because of a magic number without derivation.
5. **Documentation**: update DESIGN.md with the evolution of the biological model; synchronize DESIGN.en.md via `bilingual-docs-maintainer` agent.
6. **Audit log integrity**: after Phase 16, verify via Postgres query that every HGT event from a channel produces exactly one `mobile_elements` row with `origin_lineage_id`, `origin_biotope_id`, `created_at_tick` populated.

---

## Risks and mitigations

- **Combinatorial test blow-up**: 4 HGT channels × M defense types × K lineage states. Mitigate with a `HGTSituation.build/1` factory that instantiates reproducible scenarios.
- **`phage_pool` as persistent state carrying genomes**: grows in size; mitigate with a `@phage_pool_cap` cap (e.g. 50/phase) and pruning by abundance.
- **Audit log explosion**: HGT events can number in the thousands per tick; batch aggregation + adaptive sampling.
- **Performance of restriction_check**: O(M×N) for payload × recipient. Pre-compute `restriction_profile` per lineage as part of the `Phenotype`, cache as a hit-set lookup.
- **Balance regressions**: toxicities and deficiencies may make the default seed too harsh → sterility within 10 ticks. Calibrate with the revised `seed_scenario.ex` and the canary test "seed survives 1000 ticks under default conditions" mentioned above.

---

## Expected final outputs at plan completion

- 4 HGT channels operational and R-M-gated, written uniformly over the `HGT.Channel` behaviour.
- Persistent free phages with complete dynamics (decay, infection, lysogeny, SOS-driven induction).
- 11 metabolic strategies differentiated by specific toxicities and elemental deficiencies.
- Xenobiotics as special metabolites; RAS observable end-to-end.
- Operons as coherent units of expression.
- Bacteriocins and surface_tag arms race.
- Continuous biomass → lysis at division → error catastrophe as natural upper bound on µ.
- SOS response as emergent trait from DNA damage.
- Inc-group and copy_number enabling plasmid coexistence/displacement.
- Audit log populated for every HGT event, with complete origin tracking.
- Full coherence with DESIGN.md Blocks 5, 7, 8, 13.

### Additional output Phase 19 (Community Mode)

- Player-side persistent Seed Library (cap 12 seeds/player, Ecto-backed).
- Multi-seed provisioning (up to 3 simultaneous seeds in the same biotope).
- Progressive unlock: Community Mode unlocks via endurance / mutator emergence / successful HGT.
- `Lineage.original_seed_id` propagated throughout the entire genealogy → cladistic analytics per founder.
- UI viewport with color/glyph palette per founder + "Per founder" lineage board filter.
- Audit events `:community_provisioned` and `:cross_clade_hgt`.
- Syntrophic property test scenario (sulfate-reducer + sulfide-oxidiser) as canary for Phases 18 + 19 together.
