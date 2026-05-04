> 🇮🇹 Italiano (questa pagina) · [🇬🇧 English](CALIBRATION.en.md)

# Calibrazione del modello biologico Arkea

Questo documento è l'appendice di calibrazione del modello biologico, raccomandata dalla revisione scientifica post-Fase 19. Funzione: dichiarare *esplicitamente* le scale temporali e di concentrazione interne del simulatore, e mappare ogni costante chiave del codice al range biologico noto in letteratura.

**Senza questa appendice un microbiologo professionista che apre il codice troverà costanti che "sembrano" troppo basse o troppo alte e farà domande imbarazzanti** (testuale dalla revisione scientifica). Con questa appendice il modello è difendibile come *individual-based evolutionary sandbox con generative-grammar genomes e pathway-level Michaelis-Menten metabolism, con regimi parametrici calibrati per visibilità di fenomeno entro le time-scale in-silico del simulatore piuttosto che fitted a kinetics organism-specific* — framing che la community computazionale microbiologica riconosce per sandbox didattici e ricerca qualitativa.

> **Nota terminologica**: nei documenti interni di progetto (DESIGN.md "decisione 2026-04-25", BIOLOGICAL-MODEL-REVIEW.md) si fa riferimento a "livello B+C" come shorthand per "cellular-architecture (B) + pathway-level metabolism (C)". Quella sigla è interna al brainstorm di scoping del progetto, **non** una tassonomia pubblicata; per comunicazione esterna usare la descrizione completa sopra. Confronto con il landscape: più astratto di Karr (whole-cell), più dettagliato di Avida sul versante metabolico, comparabile ad Aevol sul versante genome.

## Principi di calibrazione

1. **Astrazione esplicita, non kinetics fitted**. Arkea è un *individual-based evolutionary sandbox* a livello di architettura cellulare + metabolismo pathway-level (vedi nota terminologica sopra), non un solver di equazioni cinetiche. Le costanti sono calibrate per surfaceare i fenomeni biologici nei tempi di gioco, non per replicare misure assolute.
2. **Time-compression dichiarata**. 1 tick simulato = 5 minuti wall-clock. Una "generazione" Arkeon di riferimento = 1 tick. Generazioni reali variano (Lenski-style E. coli: 30 min; mutator strains: 20 min; stationary: ore); la time-compression mappa al ciclo cellulare dell'organismo medio modellato.
3. **Concentration scale dichiarata**. Le concentrazioni nei `Phase.metabolite_pool` sono in unità *dimensionless*, scalate in modo che *valori "tipici" per nutrient inflow nel canary* siano nell'intervallo `100..500`. Nessuna conversione 1:1 con mol/L.
4. **Calibrazione per visibilità nei canary**. Eventi rari in vivo (transduzione, hypermutazione SOS) sono *amplificati* quanto basta per essere osservabili in scenari di centinaia o poche migliaia di tick. Override config-tunable disponibili per esperimenti di benchmark scientifico.

## Time scales

| Costrutto | Valore Arkea | Realtà biologica |
|---|---|---|
| 1 tick | 5 minuti wall-clock | 1 generazione di riferimento |
| Phage decay half-life | 3–5 tick | ore–giorni in surface waters (Suttle 1994) — coerente se 1 tick ≈ 1h |
| Bacteriocin kill | 80–160 tick | colicin in vivo: 30–60 min (Cascales 2007) — *deliberatamente lento*: warfare cronica > acuta |
| SOS attivazione | 4–10 tick sotto stress | minuti in vivo (Cox 2000) — *time-compression* |
| Mutator emergence | 50–200 tick | 100–1000 generazioni in Lenski-style — comparabile |
| Cycle closure cross-feeding | 100–500 tick a stato stazionario | giorni in chemostat (Stams & Plugge 2009) — coerente |

## Constanti chiave del codice (post-Fase 20)

### HGT — coniugazione

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `@conj_base_rate` | `hgt.ex:53` | 0.005 | F-plasmid 10⁻²/cell/h alta densità | Sotto-stima a basse densità; OK in canary "estuario" |
| `@p_conj_max` | `hgt.ex:54` | 0.30 | Saturation cap | Conservativo |

### HGT — trasformazione

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `@uptake_base` | `transformation.ex` | 0.0006 | Streptococcus / Bacillus / Haemophilus competenti: 10⁻⁵–10⁻⁷/cell/gen | Calibrato per visibilità in canary |
| `competence_score` threshold | derivato | 0.10 | Solo specie con triade ComEC + TM + sensor | Realistico — competenza non-default |

### HGT — fagi e R-M

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `@cleave_p` | `defense.ex:62` | **0.95** (Phase 20: era 0.70) | Tipo II 95–99 % per sito (Tock & Dryden 2005) | ✅ Allineato post-Phase-20 |
| `@transduction_probability` | `phage.ex:71` | 0.05 (override-able) | 10⁻⁶–10⁻³ per phage particle (Chen 2018) | **Amplificato per visibilità in canary**. Override: `config :arkea, :transduction_probability, 0.001` |
| `@transducing_burst_fraction` | `phage.ex:84` | 0.03 | ~3 % dei capsidi mis-packaged | Realistico |
| `@base_decay` | `phage.ex:75` | 0.20/tick | Free phage half-life (Suttle 1994) | Coerente con time scale |
| `@p_infect_base` | `phage.ex:78` | 0.0008 | Adsorption rate constant 10⁻⁹–10⁻⁷ mL/min | Calibrato per visibilità |
| `@lytic_decision_base` | `phage.ex:82` | 0.40 | Lambda lysis frequency under stress | Plausibile |

### Selection pressures

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `oxygen` toxic threshold | `metabolism.ex:140` | **50** (Phase 20: era 200) | µM per anaerobi obbligati, Imlay 2008 | ✅ Phase 20: anaerobi ora discriminati |
| `oxygen` toxic scale | `metabolism.ex:140` | 200 | Slope verso piena tossicità | OK |
| `h2s` toxic threshold | `metabolism.ex:141` | 20 | 10–100 µM su citocromo c (Cooper & Brown 2008) | OK |
| `lactate` toxic threshold | `metabolism.ex:142` | 30 | Non tossico ex sé (è il pH) | **Da rimuovere** quando Phase 21 implementa pH dinamico |
| `@elemental_floor_per_cell` | `metabolism.ex` | 0.001 | Stoichiometry-derived | Conservativo |

### Aerobic respiration (Phase 20)

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `@aerobic_boost` | `metabolism.ex:127` | 7.0 | Glucose: 32 ATP aerobic vs 2 fermentation = 16× | Conservativo (8× max effective vs 16× textbook) |

### SOS / error catastrophe

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `@sos_active_threshold` | `mutator.ex:81` | **0.20** (Phase 20: era 0.50) | SOS quasi-immediato in vivo (Cox 2000) | ✅ Phase 20: ora routine sotto stress |
| `@sos_mutation_amplifier` | `mutator.ex:82` | 4.0× | DinB-like fold-change µ: 10²–10⁴ × in vivo | Conservativo |
| `@sos_induction_amplifier` | `mutator.ex:83` | 3.0× | RecA cleaves cI fold-change | Plausibile |
| `@dna_damage_decay` | `mutator.ex:80` | 0.10/tick | Repair half-life ~min in vivo | Coerente con tick ≈ ore |
| `@ros_damage_max_per_tick` | `mutator.ex:90` | 0.05 | Per-tick increment ceiling sotto piena exposure | Phase 20 add |
| `@critical_mu_per_gene` | `mutator.ex:84` | 0.20 | Eigen quasispecies threshold | Standard |

### Bacteriocins

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `@secretion_per_cell` | `bacteriocin.ex:62` | 0.0001/tick | Colicin nM concentrations | Calibrato per warfare *cronica* |
| `@damage_rate` | `bacteriocin.ex:69` | 0.005 | Kill in 50–100 tick = giorni a tick=1h | Lento ma realistico |
| `@max_damage_per_pool` | `bacteriocin.ex:73` | 0.05 | Per-pool damage cap | Conservativo |

### Plasmidi (Fase 16)

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `@inc_group_modulus` | `genome.ex` | 7 | Inc gruppi: ~30 famiglie note | Semplificazione |
| `@max_copy_number` | `genome.ex` | 10 | High-copy plasmidi: 10–100 in vivo | Semplificazione |

### Biofilm (Fase 18)

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `@biofilm_dilution_relief` | `tick.ex:91` | 0.5 | EPS retention 50–95 % in nature | Conservativo |

### Mixing (Fase 18)

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `@mixing_event_probability` | `tick.ex:107` | 1.0e-4/tick | Storm cadence ~settimane | Coerente con time-compression |

### Community Mode (Fase 19)

| Costante | Path:linea | Valore | Note |
|---|---|---|---|
| `SeedLibrary.@max_size` | `seed_library.ex` | 12 entries/player | Anti-deck-building |
| `CommunityLab.@max_community_seeds` | `community_lab.ex` | 3 seed simultanei/biotopo | Cap progressivo |

## Override per benchmark scientifici

```elixir
# config/runtime.exs (o test fixture)
config :arkea, :transduction_probability, 0.001  # rate biologico realistico
```

## Citazioni primarie raccomandate per documentazione

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

## Cambi calibrazione Phase 20 (changelog)

Phase 20 ha eseguito un *scientific calibration pass* per allineare le costanti chiave alle scale biologiche, indirizzando i punti P0 della revisione scientifica post-Fase 19.

### Bug fix
- **Receptor matching invertito** (`phage.ex:550-555` pre-Phase 20): il fallback `phenotype.surface_tags == []` accettava infezione su lineage senza tag — il contrario della biologia reale. Phase 20 richiede esplicitamente `:phage_receptor` in `surface_tags`. Loss-of-receptor mutants ora escapano correttamente.

### Aggiornamenti calibrazione
- `@cleave_p`: 0.70 → 0.95 (R-M efficiency 95–99 % per sito, Tock & Dryden 2005)
- `@sos_active_threshold`: 0.50 → 0.20 (SOS quasi-immediato in vivo, Cox 2000)
- `oxygen` toxic threshold: 200 → 50 (anaerobi obbligati discriminati, Imlay 2008)
- `@transduction_probability`: ora `Application.compile_env`-tunable (default 0.05 amplificato; override per benchmark scientifici)

### Nuovi meccanismi Phase 20
- **Aerobic ATP upregulation** (`Metabolism.aerobic_boost_factor/1`): boost moltiplicativo `1 + 7 × oxygen_share` su organic substrates (`:glucose`, `:acetate`, `:lactate`, `:ch4`) quando co-uptaken con O₂. Surface niche aerobic vs anaerobic ora distinta.
- **ROS-coupled DNA damage** (`Mutator.ros_damage_increment/1`): cellule unprotected sotto stress ossidativo accumulano DNA damage indipendentemente dalla replicazione. SOS trigger anche in starvation/stationary phase.
- **Cassette repressor_strength derivato**: `Phage.derive_repressor_strength/1` ora calcola repressor_strength dalla mean `binding_affinity` dei `:dna_binding` domains della cassetta. Cassette con repressori forti più stabili in lisogenia — selezione sul cI/cro switch ora visibile.
