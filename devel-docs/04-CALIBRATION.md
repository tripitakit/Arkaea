> 🇮🇹 Italiano (questa pagina) · [🇬🇧 English](04-CALIBRATION.en.md)

# Calibrazione del modello biologico Arkea

Questo documento è l'appendice di calibrazione del modello biologico, raccomandata dalla revisione scientifica post-Fase 19. Funzione: dichiarare *esplicitamente* le scale temporali e di concentrazione interne del simulatore, e mappare ogni costante chiave del codice al range biologico noto in letteratura.

**Senza questa appendice un microbiologo professionista che apre il codice troverà costanti che "sembrano" troppo basse o troppo alte e farà domande imbarazzanti** (testuale dalla revisione scientifica). Con questa appendice il modello è difendibile come *individual-based evolutionary sandbox con generative-grammar genomes e pathway-level Michaelis-Menten metabolism, con regimi parametrici calibrati per visibilità di fenomeno entro le time-scale in-silico del simulatore piuttosto che fitted a kinetics organism-specific* — framing che la community computazionale microbiologica riconosce per sandbox didattici e ricerca qualitativa.

> **Nota terminologica**: nei documenti interni di progetto (01-DESIGN.md "decisione 2026-04-25", 05-BIOLOGICAL-MODEL-REVIEW.md) si fa riferimento a "livello B+C" come shorthand per "cellular-architecture (B) + pathway-level metabolism (C)". Quella sigla è interna al brainstorm di scoping del progetto, **non** una tassonomia pubblicata; per comunicazione esterna usare la descrizione completa sopra. Confronto con il landscape: più astratto di Karr (whole-cell), più dettagliato di Avida sul versante metabolico, comparabile ad Aevol sul versante genome.

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
| `@conj_base_rate` | `hgt.ex:55` | 0.005 | F-plasmid 10⁻²/cell/h alta densità | Sotto-stima a basse densità; OK in canary "estuario" |
| `@p_conj_max` | `hgt.ex:56` | 0.30 | Saturation cap | Conservativo |

### HGT — trasformazione

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `@uptake_base` | `transformation.ex` | 0.0006 | Streptococcus / Bacillus / Haemophilus competenti: 10⁻⁵–10⁻⁷/cell/gen | Calibrato per visibilità in canary |
| `competence_score` threshold | derivato | 0.10 | Solo specie con triade ComEC + TM + sensor | Realistico — competenza non-default |

### HGT — fagi e R-M

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `@cleave_p` | `defense.ex:67` | **0.95** (Phase 20: era 0.70) | Tipo II 95–99 % per sito (Tock & Dryden 2005) | ✅ Allineato post-Phase-20 |
| `@transduction_probability` | `phage.ex:76` | **0.005** (post-Review-2; era 0.05) | 10⁻⁶–10⁻³ per phage particle (Chen 2018) | ~1 ordine di magnitudine sopra letteratura (canary visibility); override realistico: `config :arkea, :transduction_probability, 0.001` |
| `@transducing_burst_fraction` | `phage.ex:77` | 0.03 | ~3 % dei capsidi mis-packaged | Realistico |
| `@base_decay` | `phage.ex:84` | 0.20/tick | Free phage half-life (Suttle 1994) | Coerente con time scale |
| `@p_infect_base` | `phage.ex:92` | 0.0008 | Adsorption rate constant 10⁻⁹–10⁻⁷ mL/min | Calibrato per visibilità |
| `@lytic_decision_base` | `phage.ex:104` | **0.50** (post-Review-2; era 0.40) | Lambda lysis frequency under stress | Saturazione p_lytic=1 con repressor=0 (commit `d922365`) |

### Selection pressures

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `oxygen` toxic threshold | `metabolism.ex:160` | **50** (Phase 20: era 200) | µM per anaerobi obbligati, Imlay 2008 | ✅ Phase 20: anaerobi ora discriminati |
| `oxygen` toxic scale | `metabolism.ex:160` | 200 | Slope verso piena tossicità | OK |
| `h2s` toxic threshold | `metabolism.ex:161` | 20 | 10–100 µM su citocromo c (Cooper & Brown 2008) | OK |
| `lactate` toxic threshold | `metabolism.ex:162` | 30 | Non tossico ex sé (è il pH) | **Da rimuovere** quando Phase 21 implementa pH dinamico |
| `@elemental_floor_per_cell` | `metabolism.ex` | 0.001 | Stoichiometry-derived | Conservativo |

### Aerobic respiration (Phase 20)

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `@aerobic_boost` | `metabolism.ex:120` | 7.0 | Glucose: 32 ATP aerobic vs 2 fermentation = 16× | Conservativo (8× max effective vs 16× textbook) |

### SOS / error catastrophe

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `@sos_active_threshold` | `mutator.ex:86` | **0.20** (Phase 20: era 0.50) | SOS quasi-immediato in vivo (Cox 2000) | ✅ Phase 20: ora routine sotto stress |
| `@sos_mutation_amplifier` | `mutator.ex:87` | 4.0× | DinB-like fold-change µ: 10²–10⁴ × in vivo | Conservativo |
| `@sos_induction_amplifier` | `mutator.ex:88` | 3.0× | RecA cleaves cI fold-change | Plausibile |
| `@dna_damage_decay` | `mutator.ex:74` | 0.10/tick | Repair half-life ~min in vivo | Coerente con tick ≈ ore |
| `@ros_damage_max_per_tick` | `mutator.ex:99` | 0.05 | Per-tick increment ceiling sotto piena exposure | Phase 20 add |
| `@critical_mu_per_gene` | `mutator.ex:89` | 0.20 | Eigen quasispecies threshold (legacy hint) | Esposta come API; non più usata in lethality |
| `@selection_coefficient_default` | `mutator.ex:80` | 2.0 | Master sequence fitness 2× mutant medio (Bull et al. 2005) | σ usato in `error_catastrophe_lethality/2` |

### Error catastrophe — soglia Eigen (post-Review-2)

`Mutator.error_catastrophe_lethality(mu, genome_size, sigma \\ 2.0)` implementa il
criterio di Eigen *strictly*: la fidelity per replicazione è `(1 − µ/L)^L` e la
lethality è il deficit relativo di fidelity rispetto alla soglia `1/σ`:

```
fidelity = (1 − µ/L)^L
lethality = max(0, 1 − fidelity × σ)
```

- Per `σ = 2.0` (master sequence con fitness ~2× il mutante medio, valore di
  riferimento Bull et al. 2005) la soglia per-cell è ≈ `ln(σ) = 0.693`,
  *quasi indipendente da L* per L moderati.
- La transizione è **smooth**, non una saturation cliff (vs la formula pre-Review-2
  che innescava la barriera già a `µ × L ≥ 1`).

#### Conseguenza biologica

Sotto la formula Eigen-aderente Arkea — i cui valori massimi di `mu_per_cell` sono
≈ 0.04 (`base_rate 0.01 × repair=0 × SOS×4`) — opera **molto sotto la soglia
Eigen**. Questo è coerente con la realtà microbiologica:

| Organismo | µ per replication | Distanza dalla soglia |
|---|---|---|
| Virus a RNA (poliovirus) | ~10⁰ (≈ 1 mut/genome) | *near* threshold (Eigen 1971) |
| *E. coli* | ~10⁻³ (4.6×10⁻⁴) | far below |
| Arkea SOS-amplificato | ~4×10⁻² | far below |

`error_catastrophe_lethality` agisce quindi come **theoretical ceiling**: enforced
ma raramente raggiunto durante una simulazione tipica. Per scenari di
hypermutation estrema (es. test sintetici con `µ > ln(2)`) la formula produce
una transizione smooth verso 1.

Reference: **Bull JJ, Meyers LA, Lachmann M**. *Quasispecies Made Simple*. PLOS
Comput Biol 2005; **Eigen M**. *Self-organization of matter and the evolution of
biological macromolecules*. Naturwissenschaften 1971.

### Bacteriocins

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `@secretion_per_cell` | `bacteriocin.ex:62` | 0.0001/tick | Colicin nM concentrations | Calibrato per warfare *cronica* |
| `@damage_rate` | `bacteriocin.ex:70` | 0.005 | Kill in 50–100 tick = giorni a tick=1h | Lento ma realistico |
| `@max_damage_per_pool` | `bacteriocin.ex:76` | 0.05 | Per-pool damage cap | Conservativo |

### Plasmidi (Fase 16)

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `@inc_group_modulus` | `genome.ex` | 7 | Inc gruppi: ~30 famiglie note | Semplificazione |
| `@max_copy_number` | `genome.ex` | 10 | High-copy plasmidi: 10–100 in vivo | Semplificazione |

### Biofilm (Fase 18)

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `@biofilm_dilution_relief` | `tick.ex:118` | 0.5 | EPS retention 50–95 % in nature | Conservativo |

### Mixing (Fase 18)

| Costante | Path:linea | Valore | Range biologico | Note |
|---|---|---|---|---|
| `@mixing_event_probability` | `tick.ex:126` | 1.0e-4/tick | Storm cadence ~settimane | Coerente con time-compression |

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

## Limitazioni note del modello v1

Questa sezione **dichiara onestamente i gap tra ciò che il design promette (`01-DESIGN.md`) e ciò che il codice fa attualmente**. Origine: review utente da prospettiva microbiologo (`13-MICROBIOLOGIST-PERSPECTIVE-REVIEW.md`) e biologo molecolare (`14-BIOMOL-PERSPECTIVE-REVIEW.md`); piano di chiusura in `15-MICRO-BIO-MOL-INTEGRATION-PLAN.md`.

**Razionale**: il pubblico target — microbiologi e biologi molecolari professionisti — preferisce limitazioni dichiarate apertamente a meccanismi pubblicizzati che non funzionano. Ogni voce sotto è un *honesty marker*: rimossa quando la fase corrispondente viene mergiata.

### L1. Modello molecolare semplificato

| ID | Limitazione | Conseguenza per l'utente | Fase di chiusura |
|---|---|---|---|
| **L1.1** | `Gene.promoter_block` e `Gene.regulatory_block` sono `nil` in Phase 1 (parsing differito a Phase 3 generativa). | Promotori e riboswitch non sono ispezionabili, non mutano, non guidano l'espressione. La "regolazione" promessa nel manuale è ridotta a uno scalare globale. | ✅ **Closed Phase 25 / 7.3 (parser) + Phase 31 / L1.1 (builder)**: il *parser* `Arkea.Genome.Regulation` ships in Phase 25 (`promoter_sites/1` 4-codoni stride, `riboswitches/1` 5-codoni stride). Il *builder* ships in Phase 31: `Gene.from_codons/2` accetta `:promoter_block` e `:regulatory_block` opts che popolano i campi corrispondenti del Gene; il 1-arity form `from_codons/1` resta backward-compatible (blocchi default `nil`). Il runtime σ operon-aware (Phase 25.5 / 7.2b) consuma le strutture parsate quando i blocchi sono popolati. |
| **L1.2** | `:regulator_output` è parsato (mode, cooperativity) ma **non aggregato** in un σ-factor multi-componente. | Le mutazioni in `:regulator_output` non hanno effetto osservabile sull'espressione del target. | ✅ **Closed Phase 21 #5 (strutturalmente)** — `Phenotype.regulatory_outputs` aggrega ogni gene con `:regulator_output` enriching mode/cooperativity con il `binding_affinity` del `:dna_binding` co-locato e il `signal_key` del `:ligand_sensor` co-locato; `Phenotype.sigma_factor_components/1` produce sommario `{net_activation, total_activation, total_repression, n_activators, n_repressors}`; nuovo trait `regulatory_net_activation` esposto via TimeSeries + Trends tab; campi `regulatory_outputs` + `sigma_factor_components` esposti nel snapshot export. **Runtime σ wiring volutamente differito**: `step_expression/1` usa ancora `dna_binding_affinity` come scalare singolo per preservare la calibrazione Phase 5/6/7. Cabling runtime nel network regolatorio = Fase 25. |
| **L1.3** | `Gene.operon_id` è un campo dato (UUID) ma **non esiste il modulo `Arkea.Genome.Operon`** né runtime di espressione coordinata. Geni sotto stesso operone non sono trascritti insieme. | L'operone come unità di regolazione non funziona; il manuale non deve usarlo come concetto operativo. | ✅ **Closed Phase 25 / 7.2a + Phase 25.5 / 7.2b**: modulo `Arkea.Genome.Operon` (Phase 25) fornisce il *surface* strutturale (`operons/1`, `solo_genes/1`, `containing/2`, `same_operon?/3`, `leader_gene/2`). Runtime σ-coordination (Phase 25.5) tramite `Phenotype.operon_aware_sigma_input/2`: per genomi con `operon_id` esplicitamente popolati il σ-input è la media delle *unità trascrizionali* (operoni + solo genes), dove ogni operone contribuisce con la sola `dna_binding_affinity` del *leader gene* (5 `:dna_binding` in un operone = 1 evento di trascrizione, non 5). Il `compute_growth_deltas_v5` consuma `operon_aware_sigma_input` invece di `dna_binding_affinity`. Per genomi senza operoni esplicitati il fallback è il legacy (preserva calibrazione Phase 5/6/7). |
| **L1.4** | `ribosome_like = 1.0` è **hardcoded** in `phenotype.ex:291`, in violazione del principio Blocco 5 ("tutto è genoma"). | Tutti i lignaggi hanno la stessa "macchina di traduzione" a prescindere dal genoma; nessuna evoluzione del macchinario ribosomiale. | ✅ **Closed Phase 29 / 29.1**: `Phenotype.translation_efficiency/1` deriva un scalare `0..1` dalla composizione genomica del proxy `ribosome_like` (`:structural_fold` con `multimerization_n >= 4` co-locato con `:catalytic_site` `reaction_class :ligation`). Per-gene quality = `(stability / 0.57) × (kcat / 10.0)`, clamped; cell-level efficiency = `max` across ribosome-like genes (best ribosome paces the cell). `Tick.compute_growth_deltas_v5/5` moltiplica il `net` term per `translation_efficiency`, rendendo le mutazioni in domini ribosomiali un **tratto selezionabile** — chiude la violazione Blocco 5. Genomi senza il proxy → fall-through a `1.0` (preserva calibrazione Phase 5/6/7, gate-with-fallback come Phase 25.5). |
| **L1.5** | Coniugazione: `hgt.ex` usa solo conteggio di `:transmembrane_anchor` come proxy del pilo sex. **Manca la triade prescritta** `pili_like + relaxase_like + oriT_like`. | Non si distinguono plasmidi mobilizable (richiedono relaxase ma non pili) da quelli auto-coniugativi; entry exclusion e compatibility groups non hanno base molecolare. | ✅ **Closed Phase 28 / 28.1**: la triade ora *gate* la conjugation runtime. `HGT.self_conjugative?/1` richiede `pili_strength > 0` (count `:transmembrane_anchor` su geni del plasmide) AND `relaxase_strength > 0` (geni del plasmide che co-encodano `:dna_binding` + `:catalytic_site` reaction_class `:hydrolysis`) AND `oriT_present` (intergenic block `transfer: ["orit_site"]`). `HGT.mobilizable?/1` separa i plasmidi relaxase+oriT-only (es. ColE1) da quelli pili-only (gateway distinction biologically meaningful — Smillie et al. 2010). `HGT.helper_plasmid/2` trova un plasmide self-conjugative co-residente nel donatore che possa fornire l'apparato di pili al mob plasmid; le mobilizzazioni helper-mediate firmano `transfer_mode: :mobilized` nell'audit event vs `:self_conjugative` per le triadi-complete. La throughput strength factor resta il *pili count* (preservata calibrazione Phase 5/6/7); il `@mobilisation_efficiency = 0.5` aggiunge una penalità realistica per le mob-mediate. |
| **L1.6** | SOS: `@sos_active_threshold = 0.20` è una costante **modulo-level** in `mutator.ex:86`, non derivata da domini `:ligand_sensor(target: :dna_damage)` espressi nel lignaggio. | La sensibilità al DNA damage non evolve; tutti i lignaggi hanno la stessa soglia. Anti-realistico per chi conosce la regolazione LexA/RecA. | ✅ **Closed Phase 25.5 / 7.6**: `Mutator.sos_threshold/1` legge i domini `:ligand_sensor` con `signal_key == "dna_damage"` (LexA-like SOS sensor) e calcola `min(threshold) × Lineage.dna_damage_max()` come soglia assoluta del lignaggio (most-sensitive sensor wins, OR-gate sui SOS-box). Quando il genoma non ha SOS sensor il fallback è la costante legacy (`@sos_active_threshold = 0.20`). I tre call site runtime (`Tick.detect_sos_transitions`, `Tick.apply_spawn_outcome`, `HGT.lysogeny_induction_check`) ora usano la soglia per-lignaggio via `sos_active?(damage, threshold)`. |
| **L1.7** | R-M (`defense.ex`): `signal_key` opachi a 4 codoni rappresentano i siti di riconoscimento. **Nessuna sequenza di nucleotidi modello**, nessuna distinzione tra Type I / II / III. Methylation tracciata come lista di chiavi (no per-nucleotide). | La specificità delle restrittasi non è ispezionabile a livello di sequenza; metilazione non visualizzabile come pattern. | ✅ **Closed Phase 30 (view-layer) + Phase 31 (sequence-level matching + per-position methylation)**: Phase 30 ships `RecognitionSite` struct (full 20-codon pattern + Type I/II/III classificazione) + `Phenotype.rm_profiles_detailed/1` + `Views.RestrictionInspector` per UI inspection. Phase 31 chiude il loop runtime: `RecognitionSite.methylated_positions :: MapSet` traccia per-codon-position methylation; `RecognitionSite.protected_by?/2` valida coverage completo (signature + pattern equality + per-position MapSet.subset). `Defense.restriction_check_sequence/3` (e la sua variante virion) matcha a livello di sequenza con per-position protection. `Virion.methylation_sites` e `DnaFragment.methylation_sites` carry rich profiles dalla burst donor; `Phage.run_rm_and_outcome/5` preferisce il sequence-level path quando entrambi i lati hanno dati ricchi, fallback alla legacy 4-codon signature path quando uno o entrambi sono vuoti (preserva calibrazione Phase 12 per virion pre-31 / lineage delta-encoded). **Resta deferred**: codon-complement involution `c → 19-c` per palindromi non-esatti (Type II refinement); kcat-modulated partial methylation (oggi metilasi → coverage piena, future track potrà scalare le posizioni metilate al kcat della metilasi). |

### L2. Eventi audit mancanti (meccanismi muti)

Stato delle 14 categorie di evento audit identificate nelle review utente. `✅` = chiuso (evento emesso, persistito via `Arkea.Persistence.AuditWriter`, visibile nel ledger).

| ID | Evento | File emittente | Stato |
|---|---|---|---|
| **L2.1** | `conjugation` (canale coniugazione, derivato da `hgt_transfer` con `payload.channel == "conjugation"`) | `hgt.ex` | ✅ Closed Phase 21 — promozione kind in `Arkea.Views.HGTLedger` |
| **L2.2** | `:transformation_event` | `hgt/channel/transformation.ex:252` | ✅ Closed pre-Phase 21 (Sub-task 1.2 remediation) |
| **L2.3** | `:transduction_event` | `hgt/phage.ex:598` | ✅ Closed pre-Phase 21 (Sub-task 1.3 remediation) |
| **L2.4** | `:phage_infection` (adsorbimento + iniezione, distinto da `:phage_burst`) | `hgt/phage.ex:713` | ✅ Closed pre-Phase 21 (Sub-task 1.3 remediation) |
| **L2.5** | `:rm_digestion` (R-M taglia DNA esogeno non metilato) | `hgt/phage.ex:724` | ✅ Closed pre-Phase 21 (Sub-task 1.3 remediation) |
| **L2.6** | `:plasmid_displaced` (incompatibilità o entry exclusion) | `hgt.ex:381` | ✅ Closed pre-Phase 21 (Sub-task 1.4 remediation) |
| **L2.7** | `:bacteriocin_kill` (con coppia killer/target lineage) | `bacteriocin.ex` | ✅ Closed pre-Phase 21 (Sub-task 1.5 remediation) |
| **L2.8** | `:sos_active` (transition off→on quando `dna_damage` attraversa `Mutator.sos_active_threshold/0`) | `tick.ex` `detect_sos_transitions/3` | ✅ Closed Phase 21 |
| **L2.9** | `:mutator_emergence` (child con `repair_efficiency < 0.10` da parent con `repair_efficiency >= 0.30`) | `tick.ex` `detect_mutator_emergences/3` | ✅ Closed Phase 21 |
| **L2.10** | `:error_catastrophe_death` (Eigen criterion superato) | `mutator.ex` | ✅ Closed (writer + emit pronti; raggiungimento sintetico per design Eigen-aderent) |
| **L2.11** | `:biofilm_formation` / `:biofilm_dispersal` (child con `biofilm_capable?` diverso dal parent) | `tick.ex` `detect_biofilm_transitions/3` | ✅ Closed Phase 21 |
| **L2.12** | `:migration_pulse` (aggregato per biotopo ricevente: `lineage_cells`, `metabolite_mass`, `signal_mass`, `phage_particles`) | `biotope/server.ex` `apply_migration` | ✅ Closed Phase 21 |
| **L2.13** | `:domain_flip` (mutazione in `type_tag` cambia categoria del dominio) | `genome/mutation/applicator.ex` | ✅ Closed Phase 26 (1.13) |
| **L2.14** | `:gene_chimera_birth` (translocazione fonde due geni) | `genome/mutation/applicator.ex` | ✅ Closed Phase 26 (1.14) |

**Stato corrente**: **14/14 chiusi** (Phase 26 chiude gli ultimi due). `Applicator.detect_mutation_events/4` confronta old/new genome dopo ogni `apply/2` e produce un `:domain_flip` per ogni posizione il cui `Domain.type` è cambiato + un `:gene_chimera_birth` per ogni `Translocation` riuscita; gli eventi attraversano `Tick.attempt_spawn` → `pending_events` → `AuditWriter` → audit_log con shape channel-direct (`gene_id`, `domain_index`, `from_type`/`to_type` stringificati per i flip; `source_gene_id`, `dest_gene_id`, `codons_moved` per i chimera).

### L3. Interventi player limitati

✅ **Closed Phase 27 (Advanced player interventions)** — `Intervention.apply/2` ora espone 9 comandi (4 pre-Fase-27 + 5 nuovi), tutti pure transforms su `BiotopeState` con eventi audit tipizzati. La catalog xenobiotica copre 4 target_classes (PBP, ribosome, gyrase, membrane) con 4 antibiotici.

**Pre-esistenti**:
- `:nutrient_pulse` con mix fisso `{glucose, nh3, po4}` (mix fisso resta come scelta deliberata di v1: pulse "buffet" generico).
- `:plasmid_inoculation` con plasmide modello a 1 gene (resta v1 — il `:lineage_inoculation` di 27.5 sostituisce questo workflow per genomi custom).
- `:xenobiotic_pulse` (Phase 27 / 27.1): catalog estesa a `:beta_lactam` + `:aminoglycoside` (`:ribosome_like`, cidal) + `:fluoroquinolone` (`:dna_polymerase_like`, mutagen — Cirz et al. 2005) + `:polymyxin` (`:membrane`, cidal — Velkov 2010). Il dose e il `:xenobiotic_id` sono parametri del command.
- `:mixing_event` (omogeneizzazione fasi).

**Phase 27 nuovi**:
- ✅ `:mutagen_pulse` (27.2) — UV / MMS-like, dose come fraction di `Lineage.dna_damage_max/0`. Hit ogni lignaggio resident nella fase, clamp al cap. Emette `:dna_damage_pulse` per-lignaggio + umbrella `:intervention`.
- ✅ `:environmental_shift` (27.3) — aggiorna `temperature` / `ph` / `osmolarity` / `dilution_rate` di una fase, validato contro `Phase.validate/1`. Out-of-range respinto con `{:error, :temperature_out_of_range}` etc.
- ✅ `:gene_knockout` (27.4) — zerifica i codoni di un gene cromosomico target preservando il gene count (grammar invariant: codon count == multiplo di 23). I domini ricostruiti parsano a `:substrate_binding` all-zero (≡ gene non-funzionale: kcat=0, affinity=0). Phenotype cache invalidata.
- ✅ `:lineage_inoculation` (27.5) — introduce un genoma user-supplied come nuovo founder lineage al tick corrente. Workflow "save & retry" — ricarica un lignaggio osservato altrove. Genome validato; abundance > 0; opzionale `:original_seed_id` per tagging Community Mode.

**Resta deferred**: `:scheduled_dosing` (orchestration layer, non `Intervention` core — è un thin wrapper di `apply/2` su Oban / cron job). Heterologous expression as a *single* surgical command resta open: il workflow corrente è `:lineage_inoculation` con un genoma custom — funzionalmente equivalente, ma manca un comando esplicito "inietta questo singolo gene in un lignaggio esistente".

### L4. Strumenti di analisi mancanti

I dati esistono in `phenotype.ex` e nel snapshot export, ma **mancano viste live**:

- ✅ **Trait tracker time-series** per fenotipo macro (uno o più lineage selezionati) — *Closed Phase 21 Top 5 #4*: `kind: "phenotype_trait"` samples persistiti ogni `cell_sampling_period` tick (default 10), payload con 10 tratti scalari/booleani (`base_growth_rate`, `repair_efficiency`, `energy_cost`, `dna_binding_affinity`, `competence_score`, `hydrolase_capacity`, `efflux_capacity`, `structural_stability`, `n_transmembrane`, `biofilm_capable`); `Arkea.Views.PopulationTrajectory.build_trait/3` produce la serie multi-lineage; UI `SimLive` Trends tab espone selettore di tratto.
- ✅ **Espressione per-gene** (view layer + runtime σ) — *Closed Phase 25 / 2.2 (view) + Phase 25.5 / 7.2b (runtime)*: `Arkea.Views.GeneExpression.derive(genome, signal_pool)` produce `[%{gene_id, base_level, modulation, expression}]` per ogni gene cromosomale (view-layer self-modulation). Il *runtime* σ è ora operon-aware via `Phenotype.operon_aware_sigma_input/2` (Phase 25.5): per genomi con operoni esplicitamente popolati il σ-input collassa multi-`:dna_binding` operons a una singola unità trascrizionale (leader-driven). Il time-series sample `kind: "gene_expression"` (persistenza per-tick) resta additivo per quando il Trends tab consumer sarà pronto.
- ✅ **Diff genoma fra due lineage** (livello macro: geni / plasmidi / profagi condivisi vs unici + Δ fenotipo) — *Closed Phase 22 / 2.3a*: `Arkea.Views.GenomeDiff.build/2` partiziona cromosoma, plasmidi e profagi in `{shared, a_only, b_only}` con identità basata su `:erlang.phash2(gene.codons)` (immune ai UUID v4 randomici di `Gene.id`); plasmid identity = `{inc_group, sorted gene signatures}`; phenotype delta su 7 scalari + flag `biofilm_capable_changed`. UX nel `lineage_drawer`: bottone "Pin as compare" + sezione "Genome diff vs ⟨pinned⟩" inline quando entrambi i lineage sono pinned. **Codon-level diff** (Δ per posizione, flip dominio) — *Closed Phase 26 / 2.3b*: `Arkea.Views.GeneDiff.build/2` zoomma su una coppia di geni omologhi e produce per-codon `{change, role, domain_index}` + per-domain summary (type_a/b, type_changed?, substitutions_in_tag/in_params). Allineamento posizionale v1; vere indel-aware alignment richiede 3.7-precise.
- ✅ **Mappa metabolica del biotopo** (heatmap 13 metaboliti × fasi con normalizzazione per-riga) — *Closed Phase 22 / 2.4*: `Arkea.Views.MetabolicMap.build/1` produce un modello `{phases, metabolites, rows, biotope_max}` con `rows` uno per metabolita canonico (ordinati per ciclo: C → C1 → accettori/donatori → N → S → micronutrienti) e `cells` con `intensity ∈ 0.0..1.0` normalizzata *per-riga* (così la sulfur cycle resta visibile accanto al glucosio). Renderizzata in `SimLive` Chemistry tab con label chimicamente corrette (CO₂, H₂S, SO₄²⁻, Fe²⁺/³⁺, etc.) e tooltip con valore raw. Flussi inter-lineage (cross-feeding visualization) restano deferred a Fase 22 stretch / Fase 25.
- ⚠️ **Network regolatorio molecolare (view-only)** — *Closed Phase 25 / 2.5 (view layer)*: `Arkea.Views.RegulatoryNetwork.build/1` produce un modello `{nodes, edges, gene_count, operon_count, regulator_count, riboswitch_count}` consumando tre surface strutturali (regulatory_outputs di 7.1, operons di 7.2a, riboswitches di 7.3). Nodi: `:gene`, `:operon`, `:metabolite`, `:signal`. Edges: `:operon_member` (gene→operon, leader flag), `:regulator_output` (genome→signal, mode), `:riboswitch` (metabolite→gene, mode). Pure data shape — la UI consumer (network diagram nel Phylogeny tab o pannello dedicato) ships in fase di polish. Il *runtime* di σ-coordination consuma le stesse strutture in 7.2b.
- ✅ **Codon-level viewer** (zoom: cromosoma → operone → gene → 50–200 codoni alfabeto 20) — *Closed Phase 26 / 2.6*: `Arkea.Views.CodonViewer.build/1` annotata ogni codon col suo *role* (`:type_tag` per i 3 codon che selezionano la categoria del dominio, `:parameter_codon` per i 20 che ne parametrizzano i tratti continui, `:promoter_codon`/`:regulatory_codon` per i blocchi opzionali); ritorna anche un per-domain summary con `start`/`end_pos`/`type`/`params`. La UI consumer è separata; il view layer è puro e diretto.
- ✅ **Mutation hotspot map per gene** — *Closed Phase 26 / 2.7*: `Arkea.Views.MutationHotspot.build/2` aggrega per-codon i `domain_flip` (spread `+1` sui 23 codon del dominio toccato) e i `gene_chimera_birth` (bump sull'ultimo codon, rappresentativo grossolano in v1) dalla audit list; output `bins[codon_index] = {count, contributors}` pronto per heatmap track allineato col CodonViewer. La precisione per-position richiederà 3.7 (ricostruzione ancestrale).
- ✅ **Distribuzione fenotipica del biotopo** (strip plot pesato per abbondanza con linea di centro-di-massa) — *Closed Phase 22 / 2.8*: `Arkea.Views.PhenotypeDistribution.build/3` produce un modello scatter `{tick, x_domain, y_domain, weighted_mean, total_abundance, points}` per il tratto selezionato all'ultimo tick campionato; `Chart.phenotype_distribution` lo renderizza nel Trends tab sotto la time-series. Booleani mappati a 0/1, raggio ∝ √abbondanza, linea verticale tratteggiata sulla media pesata. Sostituisce semanticamente il violin plot tradizionale (no kernel density estimation) con una vista più diretta per il pubblico target — due cluster visibili sull'asse X = polarizzazione/speciazione incipiente.
- ✅ **Landscape struttura-funzione di un dominio** (scatter 2D `kcat × Km` di tutte le varianti) — *Closed Phase 26 / 2.9*: `Arkea.Views.DomainLandscape.build/2` percorre l'intera popolazione (chromosome + plasmidi + profagi di ogni lignaggio) e produce un punto per ogni istanza del `domain_type` richiesto, annotato con `lineage_id`, `abundance`, `gene_id`, `domain_index`, `replicon`/`replicon_index` e il `params` map del dominio (`kcat`+`reaction_class`+`signal_key` per `:catalytic_site`; `binding_affinity`+`promoter_specificity` per `:dna_binding`; etc.). Il consumer sceglie quali due chiavi diventano X/Y dello scatter — il view è generico sulla `domain_type`.

### L5. Filogenesi — capacità mancanti

Il dendrogramma in `phylogeny.ex` mostra lineage, abbondanza, branch length, ma:

- ✅ **Filtro per tratto sul dendrogramma** — *Closed Phase 25 / 3.X*: `Phylogeny.colour_by_trait(model, trait)` annota ogni nodo non-sintetico con `:colour_value` letto dal `phenotype` map (`:base_growth_rate`, `:repair_efficiency`, `:energy_cost`); UI consumer può colorare il dendrogramma per quel tratto invece che per abbondanza.
- Highlight delle convergenze fenotipiche o a livello di dominio — *parzialmente abilitato Phase 26 / 3.6+3.7+3.8*: la *ricostruzione ancestrale* e il *gene tree* sono ora disponibili (vedi voci sotto); il marker convergence-highlight nel dendrogramma resta da mettere a UI come polish (Fase 26+ stretch).
- ✅ **Tasso di mutazione per branch (proxy)** — *Closed Phase 25 / 3.X*: `Phylogeny.enrich_with_branch_metrics(model, audit)` aggiunge `:phenotype_displacement = |Δgrowth| + |Δrepair| + |Δenergy_cost|` per nodo (proxy della "shift fenotipica per branch", da dividere per `branch_length` per il diagnostico tipo-mutator). La metrica non è il count di mutazioni puntiformi (richiederebbe sub/indel/dup/inv breakdown nel `mutation_summary` audit, oggi assente — TODO 3.4-precise).
- ✅ **Rate eventi HGT per branch** — *Closed Phase 25 / 3.X*: stesso enrichment aggiunge `:hgt_received` per nodo (count di `hgt_transfer` audit con `target_lineage_id == node.id`); identifica i lignaggi-hub di scambio.
- ✅ **Ricostruzione del genoma + della sequenza ancestrale di un gene** — *Closed Phase 26 / 3.6+3.7*: `Arkea.Views.AncestralReconstruction.genome_trace/2` cammina la `parent_id` chain di un lignaggio target → root e produce un'entry per ancestor con `gene_count`, `plasmid_count`, `prophage_count`, `genome_present?`; `gene_trace/3` zoomma sulla posizione `gene_chromosome_index` del cromosoma e ritorna codon sequence + type + params per ogni ancestor (con marker `:lost` se l'ancestor ha cromosoma più corto, `:delta_only` se è delta-encoded). v1 sfrutta gli ancestor genome residenti — *non* è una vera ricostruzione phylogenetica di stati su nodi non campionati (Felsenstein/parsimony, deferred a Fase 30+).
- ✅ **Gene tree distinto dallo species tree (HGT come incongruenza topologica)** — *Closed Phase 26 / 3.8*: `Arkea.Views.GeneTree.build/2` clusterizza i lignaggi per similarità del gene di interesse (greedy single-linkage su p-distance, threshold default `0.05`) e annota ogni cluster con `topology: :singleton | :congruent | :incongruent` confrontando il MRCA dei membri col loro subtree nello species tree. Un cluster è `:incongruent` quando esistono lignaggi non-membro che discendono dal MRCA — la firma classica di HGT (Doolittle 1999). v1 surface raw clustering + congruence flag; vera reconcili­ation gene-tree↔species-tree con per-edge gain/loss/transfer ships in Fase 30+.

### L6. Lab notebook assente

Il sistema esporta JSON/CSV/blueprint ma:

- ✅ **Annotazione utente attaccabile a uno specifico tick** — *Closed Phase 24 / 6.1*: tabella `biotope_annotations` (uuid, biotope_id, player_id, tick, body, timestamps); contesto `Arkea.Notebook` con `list_for_biotope/1`, `create/4`, `delete/2` (autore-only); pannello "Notebook" come 7° bottom tab del biotope viewport con form di entry e lista per tick.
- ✅ **Permalink temporale** (link che riapre il biotopo a un tick specifico) — *Closed Phase 24 / 6.2 (banner-only v1)*: URL `/biotopes/:id?at=N` parsato da `SimLive.handle_params/3` e validato (intero ≥ 0); banner cyan-ambra mostrato sopra la scena con il tick pinned + lista delle annotation/bookmark attaccate a quel tick + bottone "Jump to live". Tick chip nelle entry del notebook è ora un link `?at=N` cliccabile. **Limitazione v1**: il viewport NON ricostruisce lo state storico del tick (continua a mostrare il live state); la *replay scrubbing* di tutto lo state storico è 6.4. Sufficiente per condividere link a "guarda la mia annotazione al tick 1827" — il collega vede la nota in evidenza.
- ✅ **Bookmark di evento (con label utente, visibili sulla time-series)** — *Closed Phase 24 / 6.3*: campo `bookmark :: boolean` aggiunto a `biotope_annotations` (default false, partial index `WHERE bookmark = true` per query veloce); `Notebook.toggle_bookmark/2` flippa il flag (autore-only); `Notebook.list_bookmarks_for_biotope/1` restituisce solo le note flagged; `PopulationTrajectory.build/3` e `build_trait/4` accettano la lista bookmarks come terzo/quarto argomento e li renderizzano come marker verticali nel Trends chart (linea solida cyan-yellow vs i dash audit-derived); UI nel pannello Notebook: bottone ★/☆ accanto al delete per toggle.
- ✅ **Replay storico via permalink** — *Closed Phase 24 / 6.4 (basic-replay v1)*: `Arkea.History.fetch_state_at(biotope_id, tick)` ricostruisce il `BiotopeState` storico più vicino-prima-di-N usando in ordine: WAL exact match → snapshot ≤ N → WAL ≤ N. `SimLive` quando riceve `?at=N` sostituisce il live `sim_state` col rebuild storico, ricalcola il phenotype_cache da zero (no BiotopeServer roundtrip) e congela le tick broadcast (`handle_info({:biotope_tick,…}, %{pinned: not nil})` ignora). Banner mostra il tick effettivo del rebuild se diverso da N (snapshot più vecchi). **v1 limitation**: non c'è uno *scrubbing slider continuo* sulla time-series (l'utente naviga tick-per-tick via permalink); slider scrubbing UI ships in Fase 24+ se servirà.
- Nessun export FASTA-like (sequenze codoniche) o GFF-like (annotazione genomica) — Fase 27
- ✅ **Export "notebook-ready"** — *Closed Phase 24 / 6.8*: due nuovi endpoint API. `GET /api/biotopes/:id/notebook-export.csv` ritorna long-format `tick,lineage_id,trait,value` (boolean → 0/1, scalari numerici as-is) consumabile direttamente con `pandas.read_csv` / `polars.read_csv`. `GET /api/biotopes/:id/notebook-export.jsonl` ritorna NDJSON con discriminator `record_type ∈ {annotation, phenotype_trait, audit_event}`, una riga per record (streaming-friendly), consumabile con `polars.read_ndjson` o reader generici. Bottoni `.csv` / `.jsonl` aggiunti nell'header del biotope viewport. Parquet/AnnData esplicitamente NON nativi (richiederebbero NIF Rust o Python interop); l'utente li deriva localmente con `pl.read_csv(...).write_parquet(...)`.

### L7. Cosa NON è una limitazione (precisazioni)

Per evitare aspettative errate:

- **Nessun DNA reale (ATGC)**: il genoma è una sequenza di codoni logici su alfabeto 20, *deliberatamente* (Blocco 5 del design). Non è un gap, è una scelta di scope.
- **Nessun ribosoma reale, nessun replisoma reale, nessun compartimento intracellulare**: deliberatamente esclusi (vedi 01-DESIGN.md).
- **Nessun CRISPR/Cas in v1**: rinviato a v2 (decisione esplicita 2026-04-25).
- **Nessuna senescence**: batteri immortali in v1 (decisione esplicita).
- **Nessuna chemiolitotrofia completa (H₂/H₂S/CH₄ as electron donors)**: copertura parziale, non gap di design.
- **Nessuna tossicità H₂S/lattato finemente modellata**: in coda, non gap di design.

### Roadmap di chiusura

Vedi `15-MICRO-BIO-MOL-INTEGRATION-PLAN.md` §4 per la sequenza completa Fase 21 → 29. Ogni fase mergiata aggiorna questa sezione **rimuovendo** il punto chiuso (single source of truth).

## Citazioni primarie raccomandate per documentazione

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

## Cambi calibrazione Phase 20 (changelog)

Phase 20 ha eseguito un *scientific calibration pass* per allineare le costanti chiave alle scale biologiche, indirizzando i punti P0 della revisione scientifica post-Fase 19.

### Bug fix
- **Receptor matching invertito** (`phage.ex:778-786` post-fix): il fallback pre-Phase 20 `phenotype.surface_tags == []` accettava infezione su lineage senza tag — il contrario della biologia reale. Phase 20 richiede esplicitamente `:phage_receptor` in `surface_tags`. Loss-of-receptor mutants ora escapano correttamente.

### Aggiornamenti calibrazione
- `@cleave_p`: 0.70 → 0.95 (R-M efficiency 95–99 % per sito, Tock & Dryden 2005)
- `@sos_active_threshold`: 0.50 → 0.20 (SOS quasi-immediato in vivo, Cox 2000)
- `oxygen` toxic threshold: 200 → 50 (anaerobi obbligati discriminati, Imlay 2008)
- `@transduction_probability`: ora `Application.compile_env`-tunable (default 0.05 amplificato; override per benchmark scientifici). **Post-Review-2 (Task 6)**: default abbassato a 0.005 — sempre sopra letteratura per canary visibility, ma 1 ordine di magnitudine, non 3.

### Nuovi meccanismi Phase 20
- **Aerobic ATP upregulation** (`Metabolism.aerobic_boost_factor/1`): boost moltiplicativo `1 + 7 × oxygen_share` su organic substrates (`:glucose`, `:acetate`, `:lactate`, `:ch4`) quando co-uptaken con O₂. Surface niche aerobic vs anaerobic ora distinta.
- **ROS-coupled DNA damage** (`Mutator.ros_damage_increment/1`): cellule unprotected sotto stress ossidativo accumulano DNA damage indipendentemente dalla replicazione. SOS trigger anche in starvation/stationary phase.
- **Cassette repressor_strength derivato**: `Phage.derive_repressor_strength/1` ora calcola repressor_strength dalla mean `binding_affinity` dei `:dna_binding` domains della cassetta. Cassette con repressori forti più stabili in lisogenia — selezione sul cI/cro switch ora visibile.
