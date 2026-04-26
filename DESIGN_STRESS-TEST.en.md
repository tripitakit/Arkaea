> 🇮🇹 [Italiano](DESIGN_STRESS-TEST.md) · 🇬🇧 English (this page)

# Arkea — Tabletop design stress test

**References**: [DESIGN.en.md](DESIGN.en.md) (Blocks 1–14), [INCEPTION.en.md](INCEPTION.en.md)
**Walk-through date**: 2026-04-26
**Purpose**: validate the internal coherence of the integral design before the implementation phase, traversing in a continuous scenario all 14 blocks of the design document.

---

## 1. Method

Narrative walk-through of a **multi-week campaign** with two players in different zones of the biotope network. The scenario is designed to simultaneously exercise mechanisms of:

- design and adaptation of an Arkeon (Blocks 1, 2, 7)
- evolution (drift, duplications, rearrangements, composite innovations) (Blocks 5, 7)
- multiple selective pressures (antibiotic, phages, competition) (Blocks 5, 8)
- cell-cell communication and density-dependence (Block 9)
- emergent phase distribution (Block 12)
- world topology, colonization and migration (Blocks 3, 10)
- anti-griefing defenses (Block 13)
- keeping simulation costs within time budgets (Blocks 4, 11, 14)

For each event, the design blocks actually exercised are annotated, in order to build a **coverage matrix** at the end of the walk-through.

---

## 2. Setup

### 2.1 Cast of players

**Anna** — starter account (Tier 1). Chooses **Eutrophic pond** archetype. Receives home biotope `STAGNO-A` in the marshy zone of the map. Configures a seed Arkeon: Gram-positive, thick wall, baseline metabolic repertoire (facultative aerobic heterotroph + fermenter under O₂ scarcity).

**Bartolomeo** — advanced account (has unlocked Tier 2). Chooses **Saline estuary** in a coastal zone of the map. Receives home biotope `ESTUARIO-B`. Configures a halophilic Arkeon, Gram-negative with selective porins.

### 2.2 Relevant topology

`STAGNO-A` is in the marshy zone; `ESTUARIO-B` in the coastal zone. The two zones are connected by **a rare bridge edge** (~1% of the graph's arcs). Distance ~5 hops. Between the two zones there are intermediate wild biotopes of mixed archetypes.

### 2.3 World time

The world runs 24/7. The narrative follows **30 days of real time ≈ 8,640 ticks ≈ 8,600 reference generations** (Block 11: 1 tick = 5 minutes = 1 ideal generation). Anna and Bartolomeo log in for sessions of 1–2 hours, alternating.

[Blocks: 1, 4, 7, 10, 11]

---

## 3. Narrative walk-through

### 3.1 Week 1 — Settlement and emergent biofilm

**Day 1, t=0**. Anna inoculates 10 cells of the seed Arkeon in `STAGNO-A`. Three phases of the biotope: `surface` (oxic, illuminated), `water_column` (semi-mixed, heterotrophic), `sediment` (anoxic, rich in organics). [Block 12]

**Tick 1–50** (~4 real hours). The 10 cells divide. The seed's "facultative heterotroph" phenotype is well adapted to `water_column`. Exponential growth → 100 → 10⁴ cells of the root lineage. The **phase distribution emerges from the genome**: 70% in water_column, 25% in surface, 5% in sediment (the few that manage to tolerate partial anoxia). [Blocks: 4, 6, 12]

**Tick 50–300** (days 1–3). Baseline mutation. The first 30–40 daughter lineages appear with point drift on parameters (Km of transporters, kcat of enzymes). Mild selection: lineages with better glucose affinity and better `wall_integrity` are slightly favored. **Active pruning**: lineages with N<1 locally extinct, preserved in the global phylogenetic tree. [Blocks: 4, 5, 7, 8]

**Days 4–7, tick 300–2000**. Density in the water_column reaches 10⁶ cells. Anna decides to try to make a biofilm emerge. Strategy: she uses an "introduce an inducer metabolite" intervention (feeds extra-glucose in `surface`). Cost: **1 intervention budget action consumed** (Block 13). Effect on the next tick (latency 5 real min). [Blocks: 3, 13]

The high density in surface activates the seed's **emergent QS**: the synthase of a signal `signature ≈ (0.3, 0.7, 0.1, 0.4)` (4D) reaches the receptor's activation threshold. The program under QS control activates the adhesion genes (`Surface tag(adhesin)` + `Structural fold(rigid)`) → emergence of a **biofilm in surface**. Phase distribution shifts: 50% surface (biofilm), 35% water_column, 15% sediment. [Blocks: 7, 9, 12]

### 3.2 Week 2 — Stress, mutator, resistance

**Day 8**. Anna introduces a **β-lactam-like** in `water_column` (phase-level intervention, budget −1). Concentration 0.5× MIC in the water_column (not in surface or sediment). [Blocks: 5, 13]

**Tick 2000–2050** (~4 real hours, ~50 generations). Massive lysis in the water_column during division (compromised wall). Water_column population: 10⁶ → 10⁴. The cells in surface (biofilm) are protected: the drug does not penetrate the biofilm; those in sediment are protected by poor diffusion. [Blocks: 5, 8, 12]

**Tick 2050–2200**. Stress σ-factor activates in the water_column survivors. Expression of **DinB-like (error-prone polymerase)** rises → mutation rate µ × 50 in the survivors. In ~50 generations a point mutation in the parameter codon of a **PBP-like** shifts the Km for the β-lactam from 0.1 µM to 1 µM (reduced affinity → partial resistance). Mutation fixed by selection. [Blocks: 5, 7]

**Tick 2200–2400**. Anna raises the dose to 1× MIC (budget −1). New cycle. In 30 generations a **duplication** of a pre-existing efflux transporter appears in a lineage. The copy, under pressure, accumulates point mutations that broaden its specificity → expels the β-lactam. Fitness ↑ → fixation. **Three evolutionary regimes of Block 7 exercised**: parametric drift (PBP Km), duplication, neofunctionalization. Apparent MIC is 4×. [Blocks: 4, 5, 7]

Anna saves the case and removes the drug. The resistant mutations are slightly costly (the modified PBP is less efficient at peptidoglycan synthesis) → **balanced polymorphism** stabilizes.

### 3.3 Week 3 — Prophage, defenses, first colonization

**Day 14**. Systemic event (Block 3): a free phage arrives in `STAGNO-A` from an adjacent wild biotope (Poisson migration event, Block 5). The phage has a Surface tag compatible with a receptor of some of Anna's lineages. **Direct lysis** in some cells of the water_column. **Lysogeny** in others: the prophage integrates into the chromosome and the lysogenic repressor keeps the lytic program off. [Blocks: 3, 5, 8]

**Tick 2700–3000**. Lineages with the integrated prophage are frequent (phenotype similar to wild type, modest cost of the prophage). **Defenses against residual free phages evolve**:

- Some lineages mutate the `Surface tag` of the receptor (**loss-of-receptor**) → fitness ↓ relative to wild because the receptor also had a function (it was a transporter for a rare metabolite), but phage protection ↑.
- Other lineages gain a **Restriction-Modification system** via translocation + generative system: two genes in tandem (a DNA hydrolase + a methylase of the same specificity) appear by fusion/scission of existing genes. The RM cuts foreign phage DNA, protects its own.

[Blocks: 5, 7, 8]

**Tick 3000–3500**. Anna decides to **expand**. A sub-lineage (planktonic variant with water_column preference) naturally diffuses toward neighboring biotopes. It reaches **30% of the population** of the adjacent wild biotope `LAGO-W`, maintained for 100 ticks. **Claim activated** (Block 10): `LAGO-W` becomes Anna's first colonized biotope. **24h real cooldown** triggers (Block 13). [Blocks: 5, 10, 13]

**Tick 3500–4000**. Anna now controls 2 biotopes (`STAGNO-A` home + `LAGO-W` colonized). She runs a **communicative separation** experiment: in LAGO-W she introduces an artificial pressure (nutrient variation) that favors lineages with mutated signal synthase. In 200 generations the signal signature in LAGO-W drifts to `(0.5, 0.6, 0.3, 0.2)`. The receptor of the main STAGNO-A lineage no longer recognizes this signal (drift > σ of the receptor). **Partial communicative speciation**: the two strains are still genetically close but no longer "talk" to each other. [Blocks: 7, 9]

### 3.4 Week 4 — The indirect attack

**Day 22**. Bartolomeo, in `ESTUARIO-B`, has a well-evolved Arkeon. Out of pure mischief, he decides to **release a burden plasmid**: a non-conjugative plasmid with a large operon of costly genes that confers no benefit. He introduces it into `ESTUARIO-B` via intervention (1 intervention budget). **Origin tracking** active (Block 13): `origin_lineage_id=B-7402`, `origin_biotope_id=ESTUARIO-B`. [Blocks: 5, 13]

**Tick 4400–4800**. In its own biotope, the plasmid spreads via passive transformation and some conjugation events (cells that already had pili). But the **plasmid cost** (Block 5: replication + transcriptional burden) is high → carrier lineages are slightly less fit. Selection against within `ESTUARIO-B` itself: the plasmid spreads slowly, reaches ~5% of the cells, then stabilizes. [Blocks: 5, 8]

**Tick 4800–5500**. Migration from `ESTUARIO-B` along the arcs. The rare bridge edge connecting the coastal zone to the marshy zone carries some carrier cells into Anna's network, through 5 intermediate wild biotopes. **At each hop the fraction of carriers drops** (dilution + selection against). When it reaches a wild biotope adjacent to Anna's `LAGO-W`, the carrier fraction is < 0.1%.

A further migration brings a few carrier cells into `LAGO-W`. Conjugation possible? Only if the plasmid has `pili_like + relaxase_like + oriT_like` genes → but this plasmid is non-conjugative. So it spreads only by transformation of free DNA (rare). Stabilizes at < 0.05% of the LAGO-W cells. [Blocks: 5, 8, 10]

**Tick 5500–6000**. Selection against does the rest: in 500 generations the plasmid is eliminated from LAGO-W (the rare carrier cell loses N faster than non-carriers). **Anna doesn't even notice. No real damage.** Anti-griefing principle E confirmed (no action needed).

The audit log B (Block 13) however records the plasmid with `origin_biotope_id=ESTUARIO-B` appearing in 5 biotopes of the marshy network within 1 week. The ops system, if it were monitoring, would have the data to identify the pattern (even though in this case there was no damage). [Blocks: 5, 13]

### 3.5 Week 5 — Macro-evolution

**Day 30+**, ~8,500 generations from the start. Returning after a few days offline, Anna finds:

- In `STAGNO-A`, the founder lineage is still dominant but with ~2,000 lineages in the forest (cap=1,000 reached, **active pruning of the rarest**, decimation of the historical tree).
- In `LAGO-W`, a **chimera has emerged via translocation**: a gene fuses a `Substrate-binding(Fe³⁺)` domain with an existing `Catalytic(reduction)` domain — result: a **new ferric reductase**, qualitatively different from anything it had before. It opens a niche in sub-oxic phases of LAGO-W (some Fe³⁺ present from mineral leaching). **Composite innovation** of Block 7.
- The signal of LAGO-W is further drifted from that of STAGNO-A: now the two strains are **communicatively distinct** even though HGT-linked by migration.

[Blocks: 4, 7, 9]

---

## 4. Result

### 4.1 Block coverage matrix

| Block | Exercised | Notes |
|---|---|---|
| 1. Architecture | ✅ | MMO with two players, persistent world, Designer+Breeder roles |
| 2. Biological model | ✅ | operons (QS), σ-factor (stress), riboswitch (regulation), rearrangements (duplication + translocation) |
| 3. Environment | ✅ | systemic events (phage, migration), phase-level player interventions, no direct PvP |
| 4. Population | ✅ | delta encoding, cap 1,000, pruning, phylogenetic tree, decimation |
| 5. Biological engine | ✅ | xenobiotics-as-metabolites, modulable µ (DinB), gene-encoded conjugation, plasmid cost, drip migration |
| 6. Metabolic inventory | ⚠️ | partial: glucose, O₂, Fe³⁺ used; H₂/CH₄/SO₄²⁻/H₂S/NH₃/NO₃⁻ not exercised (chemolithotrophy not touched) |
| 7. Generative system | ✅ | all three regimes: parametric drift, categorical jump (loss-of-receptor), composite innovation (ferric reductase chimera) |
| 8. Selective pressures | ✅ | A,B,C,D covered: physico-chemical stress, lysis at division, phage lysis, dilution, emergent competition |
| 9. Quorum sensing | ✅ | density-dependent emergence, biofilm-induction, induced communicative speciation |
| 10. Network topology | ✅ | multiple archetypes (eutrophic, saline, oligotrophic lake), zones, bridge edge, colonization with sustainability |
| 11. Time | ✅ | scales respected (weeks = thousands of gen), 5 min tick, 1–2 hour sessions |
| 12. Micro/macroscale boundary | ✅ | 3 phases in the pond, emergent distribution, phase-level intervention |
| 13. Anti-griefing | ✅ | colonization cooldown, intervention budget, audit log with origin tracking, principle E confirmed |
| 14. Technological stack | ✅ | implicit: every mechanism maps to GenServer + Ecto sustainable within the prototype's limits |

### 4.2 Partial coverage to reinforce in future use cases

These are not design gaps, but areas that the single walk-through has not exercised sufficiently:

- **Chemolithotrophy**: a use case that exercises H₂/H₂S/CH₄ is needed (e.g. hydrogenotrophic thermophile that settles in a hydrothermal vent)
- **Toxicity of accumulated natural metabolites**: H₂S as cytochrome inhibitor, lactate that acidifies
- **Bacteriocins**: target-specific biological warfare between strains
- **Long-term phage-host co-evolution** (>10⁴ generations): deep arms race, recurrent mutations of receptors and RM palindromes

### 4.3 Design gaps emerged

Unlike the first use case (Block 5 of DESIGN.en.md, which produced 8 design gaps fixed during subsequent iterations), the integral walk-through **does not reveal serious inconsistencies**. Three minor considerations, of balancing/implementation:

1. **Intervention budget vs exploratory sessions**. 1 action/30 real min may be tight for those who experiment intensively (e.g. testing different antibiotics in sequence). Possible mitigation: pool accumulable up to N stored actions (e.g. 5), regenerating at the same cadence. **Future balancing decision**, not design.
2. **Phase distribution for newborn lineage**. When a new lineage is born by mutation/HGT, it inherits the phase distribution of the parent (snapshot at the instant of birth) and recomputes it on the next tick. **To be clarified in implementation**, does not reopen the design decision.
3. **Cap 1,000 lineages in just-colonized wild biotope**. Resident wild lineages stay and follow the same rules (selection, migration, pruning) without mechanical differences. "Wildness" is only a flag of player-non-control. **To be confirmed in implementation**.

### 4.4 Verdict

The design is **internally coherent**. All 14 blocks integrate into a continuous scenario that produces biologically plausible phenomena recognizable by the target expert audience:

- emergence of biofilm from quorum sensing
- evolution of antibiotic resistance through drift + duplication/neofunctionalization
- arrival of a prophage and arms race with encoded defenses (loss-of-receptor + RM)
- emergent colonization of an adjacent wild
- induced communicative speciation
- composite innovation via translocation (ferric reductase chimera)
- failure of an indirect attack (burden plasmid) by pure ecological forces, without ops intervention

The 3 residual points are balancing or implementation refinements, not design gaps. **The design is ready for the implementation phase.**
