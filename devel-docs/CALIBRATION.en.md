> [🇮🇹 Italiano](CALIBRATION.md) · 🇬🇧 English (this page)

# Arkea biological model calibration

This document is the calibration appendix of the biological model, recommended by the scientific review conducted after Phase 19. Its purpose: to *explicitly* declare the internal time and concentration scales of the simulator, and to map every key constant in the code to the known biological range found in the literature.

**Without this appendix, a professional microbiologist opening the code will find constants that "look" too low or too high and will ask embarrassing questions** (verbatim from the scientific review). With this appendix the model is defensible as an *individual-based evolutionary sandbox with generative-grammar genomes and pathway-level Michaelis-Menten metabolism, with parameter regimes calibrated for phenomenon visibility within the simulator's in-silico time-scales rather than fitted to organism-specific kinetics* — a framing the computational microbiology community recognises for educational sandboxes and qualitative research.

> **Terminology note**: internal project docs (DESIGN.md "decision 2026-04-25", BIOLOGICAL-MODEL-REVIEW.md) refer to "level B+C" as shorthand for "cellular-architecture (B) + pathway-level metabolism (C)". That shorthand is internal to the project scoping brainstorm, **not** a published taxonomy; for external communication use the full description above. Landscape comparison: more abstract than Karr (whole-cell), more detailed than Avida on the metabolic side, comparable to Aevol on the genome side.

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
| `@conj_base_rate` | `hgt.ex:53` | 0.005 | F-plasmid 10⁻²/cell/h at high density | Under-estimate at low densities; OK in "estuary" canary |
| `@p_conj_max` | `hgt.ex:54` | 0.30 | Saturation cap | Conservative |

### HGT — transformation

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `@uptake_base` | `transformation.ex` | 0.0006 | Competent *Streptococcus* / *Bacillus* / *Haemophilus*: 10⁻⁵–10⁻⁷/cell/gen | Calibrated for canary visibility |
| `competence_score` threshold | derived | 0.10 | Only species with the ComEC + TM + sensor triad | Realistic — competence is non-default |

### HGT — phages and R-M

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `@cleave_p` | `defense.ex:62` | **0.95** (Phase 20: was 0.70) | Type II 95–99 % per site (Tock & Dryden 2005) | ✅ Aligned post-Phase 20 |
| `@transduction_probability` | `phage.ex:71` | 0.05 (override-able) | 10⁻⁶–10⁻³ per phage particle (Chen 2018) | **Amplified for canary visibility**. Override: `config :arkea, :transduction_probability, 0.001` |
| `@transducing_burst_fraction` | `phage.ex:84` | 0.03 | ~3 % mis-packaged capsids | Realistic |
| `@base_decay` | `phage.ex:75` | 0.20/tick | Free phage half-life (Suttle 1994) | Consistent with time scale |
| `@p_infect_base` | `phage.ex:78` | 0.0008 | Adsorption rate constant 10⁻⁹–10⁻⁷ mL/min | Calibrated for visibility |
| `@lytic_decision_base` | `phage.ex:82` | 0.40 | Lambda lysis frequency under stress | Plausible |

### Selection pressures

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `oxygen` toxic threshold | `metabolism.ex:140` | **50** (Phase 20: was 200) | µM for obligate anaerobes, Imlay 2008 | ✅ Phase 20: obligate anaerobes discriminated |
| `oxygen` toxic scale | `metabolism.ex:140` | 200 | Slope towards full toxicity | OK |
| `h2s` toxic threshold | `metabolism.ex:141` | 20 | 10–100 µM on cytochrome c (Cooper & Brown 2008) | OK |
| `lactate` toxic threshold | `metabolism.ex:142` | 30 | Not toxic per se (it is pH) | **To be removed** when Phase 21 implements dynamic pH |
| `@elemental_floor_per_cell` | `metabolism.ex` | 0.001 | Stoichiometry-derived | Conservative |

### Aerobic respiration (Phase 20)

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `@aerobic_boost` | `metabolism.ex:127` | 7.0 | Glucose: 32 ATP aerobic vs 2 fermentation = 16× | Conservative (8× max effective vs 16× textbook) |

### SOS / error catastrophe

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `@sos_active_threshold` | `mutator.ex:81` | **0.20** (Phase 20: was 0.50) | SOS near-immediate in vivo (Cox 2000) | ✅ Phase 20: now routine under stress |
| `@sos_mutation_amplifier` | `mutator.ex:82` | 4.0× | DinB-like fold-change µ: 10²–10⁴ × in vivo | Conservative |
| `@sos_induction_amplifier` | `mutator.ex:83` | 3.0× | RecA cleaves cI fold-change | Plausible |
| `@dna_damage_decay` | `mutator.ex:80` | 0.10/tick | Repair half-life ~min in vivo | Consistent with tick ≈ hours |
| `@ros_damage_max_per_tick` | `mutator.ex:90` | 0.05 | Per-tick increment ceiling under full exposure | Phase 20 addition |
| `@critical_mu_per_gene` | `mutator.ex:84` | 0.20 | Eigen quasispecies threshold | Standard |

### Bacteriocins

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `@secretion_per_cell` | `bacteriocin.ex:62` | 0.0001/tick | Colicin nM concentrations | Calibrated for *chronic* warfare |
| `@damage_rate` | `bacteriocin.ex:69` | 0.005 | Kill in 50–100 ticks = days at tick = 1 h | Slow but realistic |
| `@max_damage_per_pool` | `bacteriocin.ex:73` | 0.05 | Per-pool damage cap | Conservative |

### Plasmids (Phase 16)

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `@inc_group_modulus` | `genome.ex` | 7 | Inc groups: ~30 known families | Simplification |
| `@max_copy_number` | `genome.ex` | 10 | High-copy plasmids: 10–100 in vivo | Simplification |

### Biofilm (Phase 18)

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `@biofilm_dilution_relief` | `tick.ex:91` | 0.5 | EPS retention 50–95 % in nature | Conservative |

### Mixing (Phase 18)

| Constant | Path:line | Value | Biological range | Note |
|---|---|---|---|---|
| `@mixing_event_probability` | `tick.ex:107` | 1.0e-4/tick | Storm cadence ~weeks | Consistent with time-compression |

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

## Recommended primary citations for documentation

- **Imlay JA**. *Cellular defenses against superoxide and hydrogen peroxide*. Annu Rev Biochem 2008.
- **Cooper CE, Brown GC**. *The inhibition of mitochondrial cytochrome oxidase by sulfide*. J Bioenerg Biomembr 2008.
- **Tock MR, Dryden DTF**. *The biology of restriction and anti-restriction*. Curr Opin Microbiol 2005.
- **Chen J et al**. *Genome hypermobility by lateral transduction*. Science 2018.
- **Cascales E et al**. *Colicin biology*. Microbiol Mol Biol Rev 2007.
- **Wommack KE, Colwell RR**. *Virioplankton: viruses in aquatic ecosystems*. Microbiol Mol Biol Rev 2000.
- **Riley MA, Wertz JE**. *Bacteriocins: evolution, ecology, and application*. Annu Rev Microbiol 2002.
- **Eigen M**. *Self-organization of matter and the evolution of biological macromolecules*. Naturwissenschaften 1971.
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
- **Inverted receptor matching** (`phage.ex:550-555` pre-Phase 20): the fallback `phenotype.surface_tags == []` accepted infection on lineages without tags — the opposite of real biology. Phase 20 explicitly requires `:phage_receptor` in `surface_tags`. Loss-of-receptor mutants now escape correctly.

### Calibration updates
- `@cleave_p`: 0.70 → 0.95 (R-M efficiency 95–99 % per site, Tock & Dryden 2005)
- `@sos_active_threshold`: 0.50 → 0.20 (SOS near-immediate in vivo, Cox 2000)
- `oxygen` toxic threshold: 200 → 50 (obligate anaerobes discriminated, Imlay 2008)
- `@transduction_probability`: now `Application.compile_env`-tunable (default 0.05 amplified; override for scientific benchmarks)

### New Phase 20 mechanisms
- **Aerobic ATP upregulation** (`Metabolism.aerobic_boost_factor/1`): multiplicative boost `1 + 7 × oxygen_share` on organic substrates (`:glucose`, `:acetate`, `:lactate`, `:ch4`) when co-uptaken with O₂. Surface aerobic vs anaerobic niche now distinct.
- **ROS-coupled DNA damage** (`Mutator.ros_damage_increment/1`): unprotected cells under oxidative stress accumulate DNA damage independently of replication. SOS trigger also fires in starvation/stationary phase.
- **Derived cassette repressor_strength**: `Phage.derive_repressor_strength/1` now computes repressor_strength from the mean `binding_affinity` of the `:dna_binding` domains in the cassette. Cassettes with stronger repressors are more stable in lysogeny — selection on the cI/cro switch is now visible.
