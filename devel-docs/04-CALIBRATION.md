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
| **L1.1** | `Gene.promoter_block` e `Gene.regulatory_block` sono `nil` in Phase 1 (parsing differito a Phase 3 generativa). | Promotori e riboswitch non sono ispezionabili, non mutano, non guidano l'espressione. La "regolazione" promessa nel manuale è ridotta a uno scalare globale. | Fase 25 (Operoni e regolazione) |
| **L1.2** | `:regulator_output` è parsato (mode, cooperativity) ma **non aggregato** in un σ-factor multi-componente. | Le mutazioni in `:regulator_output` non hanno effetto osservabile sull'espressione del target. | ✅ **Closed Phase 21 #5 (strutturalmente)** — `Phenotype.regulatory_outputs` aggrega ogni gene con `:regulator_output` enriching mode/cooperativity con il `binding_affinity` del `:dna_binding` co-locato e il `signal_key` del `:ligand_sensor` co-locato; `Phenotype.sigma_factor_components/1` produce sommario `{net_activation, total_activation, total_repression, n_activators, n_repressors}`; nuovo trait `regulatory_net_activation` esposto via TimeSeries + Trends tab; campi `regulatory_outputs` + `sigma_factor_components` esposti nel snapshot export. **Runtime σ wiring volutamente differito**: `step_expression/1` usa ancora `dna_binding_affinity` come scalare singolo per preservare la calibrazione Phase 5/6/7. Cabling runtime nel network regolatorio = Fase 25. |
| **L1.3** | `Gene.operon_id` è un campo dato (UUID) ma **non esiste il modulo `Arkea.Genome.Operon`** né runtime di espressione coordinata. Geni sotto stesso operone non sono trascritti insieme. | L'operone come unità di regolazione non funziona; il manuale non deve usarlo come concetto operativo. | Fase 25 |
| **L1.4** | `ribosome_like = 1.0` è **hardcoded** in `phenotype.ex:291`, in violazione del principio Blocco 5 ("tutto è genoma"). | Tutti i lignaggi hanno la stessa "macchina di traduzione" a prescindere dal genoma; nessuna evoluzione del macchinario ribosomiale. | Fase 29 |
| **L1.5** | Coniugazione: `hgt.ex` usa solo conteggio di `:transmembrane_anchor` come proxy del pilo sex. **Manca la triade prescritta** `pili_like + relaxase_like + oriT_like`. | Non si distinguono plasmidi mobilizable (richiedono relaxase ma non pili) da quelli auto-coniugativi; entry exclusion e compatibility groups non hanno base molecolare. | Fase 28 |
| **L1.6** | SOS: `@sos_active_threshold = 0.20` è una costante **modulo-level** in `mutator.ex:86`, non derivata da domini `:ligand_sensor(target: :dna_damage)` espressi nel lignaggio. | La sensibilità al DNA damage non evolve; tutti i lignaggi hanno la stessa soglia. Anti-realistico per chi conosce la regolazione LexA/RecA. | Fase 25 |
| **L1.7** | R-M (`defense.ex`): `signal_key` opachi a 4 codoni rappresentano i siti di riconoscimento. **Nessuna sequenza di nucleotidi modello**, nessuna distinzione tra Type I / II / III. Methylation tracciata come lista di chiavi (no per-nucleotide). | La specificità delle restrittasi non è ispezionabile a livello di sequenza; metilazione non visualizzabile come pattern. | Fase 28 (parziale: tag-sequence di N codoni) |

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
| **L2.13** | `:domain_flip` (mutazione in `type_tag` cambia categoria del dominio) | `genome/mutation/applicator.ex` | ❌ Pending Fase 26 |
| **L2.14** | `:gene_chimera_birth` (translocazione fonde due geni) | `genome/mutation/applicator.ex` | ❌ Pending Fase 26 |

**Stato corrente**: 12/14 chiusi. Phase 21 Top 5 #1 ha aggiunto la sezione "Limitazioni note v1"; Top 5 #2 ha chiuso L2.1 (kind promotion del channel `conjugation` nel view layer); Top 5 #3 ha chiuso L2.8/9/11/12 (`:sos_active`, `:mutator_emergence`, `:biofilm_formation`/`_dispersal`, `:migration_pulse` rinominato dal precedente `:migration`). L2.2-L2.7 e L2.10 erano già chiusi in remediation pre-Phase 21 (Sub-tasks 1.2-1.6) ma non documentati come tali — gli aggiornamenti precedenti hanno allineato la documentazione alla realtà del codice. Restano solo L2.13, L2.14, chiusi in Phase 26 (codon-level events).

### L3. Interventi player limitati

Solo 4 interventi disponibili in `Intervention.apply/2`, tutti a livello di fase:

- `:nutrient_pulse` con mix fisso `{glucose, nh3, po4}` (non scelta del metabolita)
- `:plasmid_inoculation` con plasmide modello hardcoded a 1 gene (non personalizzabile)
- `:xenobiotic_pulse` con solo `:beta_lactam` esposto in UI (il framework `target_class` è generativo)
- `:mixing_event` (omogeneizzazione fasi)

**Mancano**: mutagenesi guidata, knockout / knockdown, heterologous expression, pulse mutageno UV/MMS-like, shift environment (pH/T/osmolarità), inoculazione di un lignaggio osservato altrove, dosaggio temporale schedulato, xenobiotici aminoglycoside/fluorochinolone/polimixina.

**Chiusura**: Fase 27 (Interventi avanzati).

### L4. Strumenti di analisi mancanti

I dati esistono in `phenotype.ex` e nel snapshot export, ma **mancano viste live**:

- ✅ **Trait tracker time-series** per fenotipo macro (uno o più lineage selezionati) — *Closed Phase 21 Top 5 #4*: `kind: "phenotype_trait"` samples persistiti ogni `cell_sampling_period` tick (default 10), payload con 10 tratti scalari/booleani (`base_growth_rate`, `repair_efficiency`, `energy_cost`, `dna_binding_affinity`, `competence_score`, `hydrolase_capacity`, `efflux_capacity`, `structural_stability`, `n_transmembrane`, `biofilm_capable`); `Arkea.Views.PopulationTrajectory.build_trait/3` produce la serie multi-lineage; UI `SimLive` Trends tab espone selettore di tratto.
- Espressione per-gene per-tick (oggi `Phenotype.from_genome/1` aggrega tutto in scalari globali) — Fase 25
- Diff genoma fra due lineage (selezione multipla nel dendrogramma) — Fase 22 (macro) + Fase 26 (codonico)
- Mappa metabolica del biotopo (heatmap / network 13 metaboliti × fasi, flussi inter-lineage) — Fase 22
- Network regolatorio molecolare (`:dna_binding` + `:regulator_output` → target promoter) — Fase 25
- Codon-level viewer (zoom: cromosoma → operone → gene → 50–200 codoni alfabeto 20) — Fase 26
- Mutation hotspot map per gene — Fase 26
- ✅ **Distribuzione fenotipica del biotopo** (strip plot pesato per abbondanza con linea di centro-di-massa) — *Closed Phase 22 / 2.8*: `Arkea.Views.PhenotypeDistribution.build/3` produce un modello scatter `{tick, x_domain, y_domain, weighted_mean, total_abundance, points}` per il tratto selezionato all'ultimo tick campionato; `Chart.phenotype_distribution` lo renderizza nel Trends tab sotto la time-series. Booleani mappati a 0/1, raggio ∝ √abbondanza, linea verticale tratteggiata sulla media pesata. Sostituisce semanticamente il violin plot tradizionale (no kernel density estimation) con una vista più diretta per il pubblico target — due cluster visibili sull'asse X = polarizzazione/speciazione incipiente.
- Landscape struttura-funzione di un dominio (scatter 2D `kcat × Km` di tutte le varianti) — Fase 26

### L5. Filogenesi — capacità mancanti

Il dendrogramma in `phylogeny.ex` mostra lineage, abbondanza, branch length, ma:

- Nessun filtro per tratto (oggi colora solo per abbondanza) — Fase 25
- Nessun highlight delle convergenze fenotipiche o a livello di dominio — Fase 25
- Tasso di mutazione per branch non normalizzato per branch length — Fase 25
- Nessuna ricostruzione del genoma ancestrale o della sequenza ancestrale di un gene — Fase 26
- Nessun gene tree distinto dallo species tree (HGT come incongruenza topologica) — Fase 26

### L6. Lab notebook assente

Il sistema esporta JSON/CSV/blueprint ma:

- Nessuna annotazione utente attaccabile a uno specifico tick — Fase 24
- Nessun permalink temporale (link che riapre il biotopo allo stato del tick X) — Fase 24
- Nessun bookmark di evento (con label utente, visibili sulla time-series) — Fase 24
- Nessun replay con scrubbing — Fase 24
- Nessun export FASTA-like (sequenze codoniche) o GFF-like (annotazione genomica) — Fase 27
- Nessun export "notebook-ready" (parquet, AnnData) — Fase 24

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
