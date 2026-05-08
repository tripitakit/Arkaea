> 🇮🇹 Italiano (questa pagina)

# Piano integrato — Miglioramenti dalla review microbiologo + biologo molecolare

**Data**: 2026-05-08
**Scope**: aggregazione delle due review utente (`13-MICROBIOLOGIST-PERSPECTIVE-REVIEW.md` e `14-BIOMOL-PERSPECTIVE-REVIEW.md`) in un unico piano di lavoro **senza duplicazioni**, organizzato per *tracce funzionali* anziché per persona target. Dove le due prospettive convergono (es. limitazioni dichiarate, lab notebook, polish UX, eventi audit muti) gli item sono fusi; dove restano genuinamente distinte per livello di osservazione (codon-level viewer vs mappa metabolica del biotopo) sono mantenute separate. La roadmap finale propone una sequenza di fasi con dipendenze esplicite.

---

## 1. Note sull'integrazione

### 1.1 Voci fuse (originariamente duplicate fra 13- e 14-)

| Tema | Microbiologo (13-) | Biolmol (14-) | Voce fusa |
|------|--------------------|---------------|-----------|
| Limitazioni note v1 | §10 + Top 5 #5 | §10 + Top 5 #5 | Traccia 7.8 |
| Audit events muti | §3 (HGT split, R-M, SOS, bacteriocine, biofilm, migrazione) | §3 A.5 (`:domain_flip`, `:gene_chimera_birth`) | Traccia 1 |
| Trait tracker | §4 B.1 (per fenotipo macro) | §4 B.2 (per gene/expression) | Traccia 2.1 + 2.2 (livelli) |
| Diff genoma | §4 B.2 | §3 A.4 (codonico) | Traccia 2.3 (multilivello) |
| Filogenesi avanzata | §7 | §7 | Traccia 3 unificata |
| Onboarding | §5 | §5 | Traccia 4 unificata |
| Lab notebook + permalink + replay | §8 | §8 | Traccia 6 unificata |
| Polish UX | §9 | §9 | Traccia 8 unificata |
| Bug ribosome / SOS / coniugazione / operoni / regulator_output | §10 | §10 | Traccia 7 unificata |
| Glossario espanso | §5 C.4 | §5 C.2 | Traccia 4.4 unificata |

### 1.2 Voci mantenute distinte (specifiche di livello)

| Voce | Origine | Motivo distinto |
|------|---------|-----------------|
| Quick-start scenari "ipotesi pronte" | 13- §5 C.1 | Operano a livello popolazione |
| Mappa metabolica del biotopo | 13- §4 B.3 | Network ecologico |
| Distribuzione fenotipica violin plot | 13- §4 B.4 | Macroscopica |
| Codon-level viewer | 14- §3 A.1 | Zoom intra-dominio |
| Mappa lineare gene con annotazioni | 14- §3 A.2 | Sub-dominio |
| Mutation hotspot map per gene | 14- §3 A.3 | Codonica |
| Network regolatorio molecolare | 14- §4 B.1 | Sub-cellulare |
| Landscape struttura-funzione dominio | 14- §4 B.3 | Enzymology |
| Espressione per-gene per-tick | 14- §4 B.2 | Granularità mol |
| Plasmide custom + xenobiotici multipli + nutrienti specifici | 13- §6 | Interventi macro |
| Mutagenesi in silico, KO/KD, heterologous | 14- §6 | Interventi mol |

---

## 2. Premessa generale

Il modello biologico di Arkea è internamente solido a tutti i livelli (popolazione, fase, lignaggio, fenotipo, dominio, codone). Ma la **superficie utente** copre bene solo i due livelli intermedi (lignaggio + fenotipo). I due livelli estremi sono sotto-serviti:

- **Macro (popolazione/ecosistema)**: meccaniche girano "mute" in audit (HGT split, R-M, SOS, bacteriocine, biofilm, migrazione); manca mappa metabolica del biotopo, distribuzione fenotipica per archetipo, scenari guidati.
- **Mol (codone/sequenza/regolazione)**: niente vista codonica, niente diff codonico, niente network regolatorio; `promoter_block` e `regulatory_block` sono `nil` in Phase 1; `:regulator_output` parsato ma non aggregato; operoni dato-only; ribosoma costante.

Inoltre alcuni gap sono **trasversali**: limitazioni note non dichiarate, lab notebook assente, glossario non in-context, polish UX disuniforme.

Il piano sotto organizza queste lacune in 8 tracce indipendenti con dipendenze esplicite, e propone una roadmap a 9 fasi (Fase 21 → 29 nella numerazione esistente del progetto).

---

## 3. Le 8 tracce di lavoro

### Traccia 1 — Visibilità delle meccaniche oggi mute (audit events)

**Obiettivo**: ogni meccanica già implementata nel sim core deve emettere un evento audit identificabile, in modo che `HGTLedgerLive` e `AuditLive` non siano "promesse" del manuale.

| ID | Evento da emettere | File emittente | Status |
|----|-------------------|----------------|--------|
| 1.1 | `:conjugation_event` (rimpiazza `:hgt_transfer` quando il canale è coniugazione) | `arkea/lib/arkea/sim/hgt.ex` | Atteso da ledger, non emesso |
| 1.2 | `:transformation_event` (DNA uptake + integrazione) | `arkea/lib/arkea/sim/hgt/channel/transformation.ex` | Atteso da ledger, non emesso |
| 1.3 | `:transduction_event` (capside fagico veicola DNA cromosomale) | `arkea/lib/arkea/sim/hgt/phage.ex` | Atteso da ledger, non emesso |
| 1.4 | `:phage_infection` (adsorbimento + iniezione, distinto da `:phage_burst`) | `phage.ex` | Atteso da ledger, non emesso |
| 1.5 | `:rm_digestion` (R-M taglia DNA esogeno non metilato) | `arkea/lib/arkea/sim/hgt/defense.ex` | Solo gate interno |
| 1.6 | `:plasmid_displaced` (incompatibilità o entry exclusion) | `hgt.ex` | Non implementato |
| 1.7 | `:bacteriocin_kill` (con coppia killer/target lineage) | `arkea/lib/arkea/sim/bacteriocin.ex` | Non emesso |
| 1.8 | `:sos_active` (con `dna_damage_score` + trigger source) | `arkea/lib/arkea/sim/mutator.ex` | Non emesso |
| 1.9 | `:mutator_emergence` (lignaggio sale a hypermutator) | `mutator.ex` | Non emesso |
| 1.10 | `:error_catastrophe_death` (Eigen criterion superato) | `mutator.ex` | Non emesso |
| 1.11 | `:biofilm_formation` / `:biofilm_dispersal` | `arkea/lib/arkea/sim/phenotype.ex` + `tick.ex` | Non emessi |
| 1.12 | `:migration_pulse` (aggregato per arco top-N per tick) | `arkea/lib/arkea/sim/migration/` | Non emesso |
| 1.13 | `:domain_flip` (mutazione in `type_tag` cambia categoria del dominio) | `arkea/lib/arkea/genome/mutation/applicator.ex` | Non emesso |
| 1.14 | `:gene_chimera_birth` (translocazione fonde due geni) | `applicator.ex` | Non emesso |

**Verifica**: scenario "arms race fagico + xenobiotic pulse" deve produrre nei primi 200 tick almeno un evento per ciascuna delle 14 categorie nei log `AuditLive`/`HGTLedgerLive`.

---

### Traccia 2 — Strumenti di analisi (live + post-hoc)

**Obiettivo**: ridurre il flusso "esporta JSON → notebook → analizza" alle 5–6 domande più ricorrenti, offrendole live.

| ID | Strumento | Livello | Note di realizzazione |
|----|-----------|---------|----------------------|
| 2.1 | Trait tracker time-series per fenotipo (uno o più lineage selezionati, con eventi audit sovrapposti) | Macro | Estende `population_trajectory.ex` a tratti generici (`hydrolase_capacity`, `repair_efficiency`, `n_transmembrane`) |
| 2.2 | Espressione per-gene per-tick (livello di espressione di un gene specifico in un lignaggio) | Mol | Richiede aggregazione per-gene in `phenotype.ex`, oggi solo scalari globali |
| 2.3a | Diff genoma macro (geni condivisi/unici, presenza plasmidi/profagi) | Macro | Selezione multipla nel dendrogramma → pannello |
| 2.3b | Diff codonico fra due varianti dello stesso gene (allineamento posizionale + highlight `type_tag` vs `parameter_codons`) | Mol | Subentra a 2.3a quando si seleziona un gene specifico |
| 2.4 | Mappa metabolica del biotopo (heatmap / network 13 metaboliti × fasi, flussi inter-lineage) | Macro | Dichiara visivamente la sintrofia oggi solo numerica |
| 2.5 | Network regolatorio del lignaggio (`:dna_binding` + `:regulator_output` → target promoter) | Mol | **Dipende da Traccia 7.1** (aggregare `:regulator_output`) |
| 2.6 | Codon-level viewer (zoom: cromosoma → operone → gene → 50–200 codoni alfabeto 20, bande `type_tag` vs `parameter_codons`) | Mol | Nuovo componente, non esiste niente di simile oggi |
| 2.7 | Mutation hotspot map per gene (n. mutazioni accumulate per codone dal MRCA, distinte synonymous-like / non-synonymous-like / missense-like) | Mol | Richiede annotazione delle mutazioni per posizione codonica |
| 2.8 | Distribuzione fenotipica del biotopo (violin plot di un tratto across lineage, pesato per abbondanza) | Macro | Componente leggero |
| 2.9 | Landscape struttura-funzione di un dominio (scatter 2D `kcat × Km` di tutte le varianti di un `:catalytic_site` nel clade) | Mol | Vista altamente specifica di enzymology |

**Verifica**: per ogni strumento, screenshot prodotto su biotopo seedato con scenario "evoluzione resistenza β-lattamico" mostra evoluzione/diversità nei primi 500 tick.

---

### Traccia 3 — Filogenesi avanzata

**Obiettivo**: trasformare il dendrogramma da "vista statica" a strumento di analisi evolutiva.

| ID | Funzionalità | Note |
|----|--------------|------|
| 3.1 | Filtro per tratto (colora il dendrogramma per `hydrolase_capacity`, `repair_efficiency`, presenza prophage X, etc.) | Oggi colora solo per abbondanza |
| 3.2 | Highlight delle convergenze fenotipiche (due lineage indipendenti acquisiscono soglia di tratto simile) | Macro |
| 3.3 | Highlight delle convergenze a livello di dominio (drift parametrico verso stesso valore di kcat/Kd) | Mol |
| 3.4 | Tasso di mutazione per branch normalizzato per branch length (`mutation_summary` / branch_length) | Identifica mutator a colpo d'occhio |
| 3.5 | Rate eventi HGT in linea (per branch: HGT ricevuti/inviati) | Identifica hub di scambio |
| 3.6 | Click su nodo ancestrale → ricostruzione genoma ancestrale (lista geni MRCA) | Macro |
| 3.7 | Click su nodo ancestrale + selezione gene → ricostruzione sequenza codonica ancestrale (majority rule) | Mol |
| 3.8 | Filogenesi di un singolo gene (gene tree distinto dal species tree del lignaggio) | Mol — espone HGT come incongruenza topologica |

**Verifica**: scenario "speciazione comunicativa QS dialect drift" deve mostrare in 3.8 una topologia di gene tree del recettore QS divergente dal species tree dei lignaggi che lo portano.

---

### Traccia 4 — Onboarding e modello mentale

**Obiettivo**: un nuovo utente (microbiologo o biolmol) deve poter usare l'app produttivamente in <30 minuti senza dover leggere il manuale dall'inizio.

| ID | Feature | Note |
|----|---------|------|
| 4.1 | Quick-start scenari "ipotesi pronte" (es. "Evoluzione resistenza β-lattamico sotto dosaggi ripetuti", "Arms race ospite-fago con perdita di recettore vs R-M", "Speciazione comunicativa sotto QS dialect drift"). Ogni scenario dichiara: ipotesi attesa, KPI da osservare, tempo stimato in tick reali. | Estende `arkea/lib/arkea/scenarios.ex` (oggi 3 scenari generici → +5 ipotesi-driven) |
| 4.2a | Tutorial guidato sul biotopo demo (3–5 step, "questa è una fase", "questo è un lignaggio", "clicca questo gene per vedere i suoi domini", "questo evento è una coniugazione") | Macro |
| 4.2b | Tutorial "anatomia di un gene Arkea" (4 step: sequenza di codoni → domini parsati → parametri continui derivati → effetto di una mutazione) | Mol |
| 4.3 | Cheat-sheet 13 metaboliti × 8 archetipi (matrice "metabolita abbondante in archetipo X → nicchie metaboliche aperte") | In `/help` o popup |
| 4.4 | Glossario espanso a tutti i campi dei pannelli + termini molecolari (`codone logico`, `type_tag`, `parameter_codons`, `domain flip`, `chimeric gene`, `weighted_sum`, `signature 4D`, `dna_damage`, `repair_efficiency`, `efflux_capacity`...) | Estende `arkea/lib/arkea_web/components/help.ex` |
| 4.5 | Help context-sensitive: pulsante "?" per ogni sezione di pannello apre il glossario alla voce giusta | Hook LV minimale |
| 4.6 | Mappa "dominio → funzione reale" (gli 11 tipi di dominio spiegati con esempio gene reale: β-lactamasi = substrate-binding + catalytic, lac repressor = dna_binding + ligand_sensor + regulator_output) | Sezione manuale + tooltip |

**Verifica**: test su 1–2 utenti microbiologi/biolmol non coinvolti nello sviluppo: 30 min di esplorazione + 15 min di task ("trova un evento di trasformazione", "descrivi la struttura di un gene", "dimmi quando emerge il primo mutator"). Criterio: ≥80% task completati senza assistenza.

---

### Traccia 5 — Interventi del giocatore (entro intervention budget esistente)

**Obiettivo**: arricchire qualitativamente i 4 interventi attuali (`:nutrient_pulse`, `:plasmid_inoculation`, `:xenobiotic_pulse`, `:mixing_event`) senza aumentare la frequenza, restando entro l'anti-griefing budget rigenerativo dichiarato nel design.

| ID | Intervento | Livello | Note |
|----|-----------|---------|------|
| 5.1 | Plasmide custom inoculabile (pescato dal Seed Lab del giocatore o costruito in mini-editor con subset di domini) | Macro+Mol | Sostituisce hardcoded 1-gene attuale |
| 5.2 | Xenobiotici multipli (aminoglycoside → target `ribosome_like` quando esisterà davvero, fluorochinolone → topoisomerasi/repair, polimixina → membrana) | Macro | Framework `target_class` già generativo, basta UI |
| 5.3 | Pulse di nutrienti specifici (scelta del metabolita anziché mix fisso `{glucose, nh3, po4}`; permette anche metaboliti tossici come H₂S, NO₃⁻ per selezione) | Macro | Modifica `Intervention.apply/2` |
| 5.4 | Shift environment (pH/temperatura/osmolarità entro range) | Macro | |
| 5.5 | Inoculazione di un lignaggio osservato altrove (lignaggio del biotopo A → B per testare invasione) | Macro | |
| 5.6 | Dosaggio temporale schedulato (pulse ogni N tick anziché one-shot) | Macro | Essenziale per studi di resistenza |
| 5.7 | In silico mutagenesi guidata (lignaggio + gene + codone/range + tipo mutazione → nuovo lignaggio child) | Mol | Espone `Mutation.Substitution.apply/2` etc. come azione UI |
| 5.8 | Knockout / knockdown (rimuovi gene da copia del lignaggio o riducine espressione modificando `promoter_block` quando esisterà) | Mol | KD dipende da Traccia 7.3 |
| 5.9 | Heterologous expression (gene/operone da lignaggio A → ricevente B) | Mol | Versione mirata della trasformazione naturale stocastica |
| 5.10 | Pulse mutageno UV/MMS-like (alza temporaneamente `dna_damage_score` di una fase → induce SOS → accelera evoluzione in tempi compressi) | Mol | Implementa il pulse come variante di `:xenobiotic_pulse` con `target_class: :dna` |

**Verifica**: ogni intervento, applicato in scenario di test dedicato, produce una traiettoria fenotipica/audit distinguibile dal controllo no-intervention entro 100 tick.

---

### Traccia 6 — Lab notebook + replay + condivisione

**Obiettivo**: trasformare l'app da "demo" a "lab notebook" — capacità di annotare, condividere, ripercorrere, esportare in formati standard.

| ID | Feature | Note |
|----|---------|------|
| 6.1 | Annotazioni / lab notebook per biotopo (campo testo libero attaccato a uno specifico tick) | Persistenza su `biotopes` o tabella dedicata |
| 6.2 | Permalink temporali (link che riapre il biotopo allo stato del tick X) | Stato ricostruibile da snapshot ogni 10 tick + WAL |
| 6.3 | Snapshot bookmarkati (marcatori a un certo tick con label utente, visibili sulla time-series) | UI: clic destro su time-series → "bookmark this tick" |
| 6.4 | Replay con scrubbing (cursore temporale sul biotope viewport per scorrere ultimi N tick) | Read-only navigation |
| 6.5 | Bookmark di evento molecolare specifico ("tick 2104, gene G7 nel lignaggio L19, codone 33: SNP da `:tyr` a `:phe` → kcat 8.2→12.4 s⁻¹") | Mol — link da `domain_flip` o `:substitution` audit a vista codonica |
| 6.6 | Export FASTA-like (sequenze di codoni come stringhe alfabeto 20 con header `>lineage_id|gene_id|tick=N`) | Mol |
| 6.7 | Export GFF-like (annotazione genomica: posizioni di geni, domini, intergenic blocks) | Mol |
| 6.8 | Export "notebook-ready" (parquet via `polars`, AnnData per single-cell-like) | Macro+Mol |

**Verifica**: workflow "trovo evento interessante → bookmark + annoto → condivido permalink con collega → collega riapre allo stesso stato + esporta in pandas/polars" completabile in <5 minuti.

---

### Traccia 7 — Bug e correzioni di credibilità del modello

**Obiettivo**: correggere o dichiarare onestamente i gap di implementazione che impattano la credibilità scientifica del sistema. Sono i deal-breaker per il pubblico target.

| ID | Bug / gap | Stato attuale | Correzione proposta | Priorità |
|----|-----------|---------------|---------------------|----------|
| 7.1 | `:regulator_output` parsato ma non aggregato in σ multi-componente | Domain parsato (mode, cooperativity, target) ma ignorato in `phenotype.ex:521-523` con commento esplicito | Aggregare in σ-factor map per-target; partecipa al calcolo del livello di espressione del target | Alta |
| 7.2 | `Gene.operon_id` campo dato senza modulo `Operon` né runtime | Campo UUID presente, ma nessuna logica di espressione coordinata | Implementare `Arkea.Genome.Operon`; espressione coordinata dei geni nello stesso operone (uno σ vincola tutti) | Alta |
| 7.3 | `promoter_block` e `regulatory_block` in `Gene` sono `nil` in Phase 1 | Schema dichiarato ma deferred a Phase 3 | Implementare (almeno strict subset) o **dichiarare in 7.8** | Alta (la regolazione promessa nel manuale dipende da questo) |
| 7.4 | `ribosome_like = 1.0` hardcoded in `phenotype.ex:291` | Costante globale | Derivare da conteggio domini specifici (es. somma `:catalytic_site(reaction_class: :translation)` se esistesse) o **dichiarare in 7.8** | Media |
| 7.5 | Coniugazione con proxy `:transmembrane_anchor` anziché triade `pili_like + relaxase_like + oriT_like` | Solo conteggio anchor in `hgt.ex` | Introdurre i tre tag come `reaction_class` o sub-categorie di domini; coniugazione richiede tutti e tre | Media |
| 7.6 | SOS threshold `0.20` modulo-level, non derivato da `:ligand_sensor` DNA-damage-like | Costante in `mutator.ex` | Derivare da media `threshold` di domini `:ligand_sensor(target: :dna_damage)` espressi nel lignaggio | Media |
| 7.7 | R-M senza recognition sequence DNA esplicita | `signal_key` opachi a 4 codoni | Estendere a tag-sequence di N codoni (es. 6) per modellare specificità Type II vs III; opzionale | Bassa |
| 7.8 | **Sezione "Limitazioni note del modello v1"** in `04-CALIBRATION.md` o `USER-MANUAL.md` | Inesistente | Dichiarare onestamente: niente promotori/regulatory parsati, σ scalar invece che cascata, operoni dato-only, ribosoma costante, coniugazione con proxy minimo, R-M senza sequenza DNA, SOS threshold globale. **Bloccante per credibilità** | Massima — rilascio rapido |

**Verifica**: dopo 7.1+7.2 una mutazione in un `:regulator_output` deve mostrare effetto osservabile sul livello di espressione del gene target nello stesso lignaggio. Dopo 7.8 il manuale e la realtà del codice coincidono al 100%.

---

### Traccia 8 — Polish UX trasversale

**Obiettivo**: alzare la qualità percepita nei primi 5 minuti per qualunque utente.

| ID | Polish | Livello |
|----|--------|---------|
| 8.1 | Countdown al prossimo tick sul biotope panel ("prossimo tick fra 2:47") | Trasversale |
| 8.2 | Indicatore stress globale del biotopo (chip verde/giallo/rosso da `mean(dna_damage)`, `mass_lysis_rate_recent`, `xenobiotic_concentration`) | Macro |
| 8.3 | Indicatore stress molecolare del lignaggio (`dna_damage_score`, stato SOS, mutation rate effettivo recente) | Mol |
| 8.4 | Numeri formattati con notazione SI consistente (oggi `total_abundance` a volte `4.231e7`, a volte raw) | Trasversale |
| 8.5 | Unità di misura ovunque (`kcat 12 s⁻¹`, `Km 0.4 mM`, etc.) | Trasversale |
| 8.6 | Vuoto/zero state per pannelli (cosa mostrare con 0 lineage / 0 fagi / 0 audit recenti) | Trasversale |
| 8.7 | Loading skeletons LiveView nativi anziché "Loading..." | Trasversale |
| 8.8 | Mobile/tablet responsive per consultazione al banco | Trasversale |
| 8.9 | Distinzione visiva fra codoni cromosoma vs plasmide vs profago nel `GenomeCanvas` | Mol — oggi distingue plasmide ma non profago |
| 8.10 | Tooltip chimico/funzionale sui domini (hover su `:catalytic_site(reaction_class: :hydrolysis)` → "Idrolasi: catalizza taglio idrolitico. In Arkea genera restrittasi e β-lattamasi a seconda del partner `:substrate_binding`") | Mol |

**Verifica**: walk-through dei primi 5 minuti su nuovo utente non mostra unità mancanti, numeri raw, "Loading..." persistenti, o elementi non responsive su tablet.

---

## 4. Roadmap proposta (Fase 21 → 29)

Sequenza che bilancia *quick wins ad alta visibilità* (Fase 21–22), *fondamenta strutturali* (Fase 25), e *capabilities profonde* (Fase 26–28). Ogni fase è autonoma e mergiabile.

> **Note di riordinamento (2026-05-08, dopo merge Fase 22)**: la Fase 23 (Onboarding) era originariamente in posizione 3, subito dopo Fase 22. È stata **spostata in coda** (post-Fase 29) perché tutti i suoi contenuti dipendono direttamente dalle fasi successive: i quick-start scenari ipotesi-driven richiedono interventi avanzati (Fase 27) e σ runtime (Fase 25); il tutorial "anatomia di un gene" richiede il codon-level viewer (Fase 26); la mappa dominio→funzione dà il suo meglio con la cascata regolatoria runtime (Fase 25). Scrivere Fase 23 in posizione 3 avrebbe richiesto 5 round di rework. La sequenza riveduta:
>
> ```
> 21 ✅ → 22 ✅ → 24 → 25 → 26 → 27 → 28 → 29 → 23
> ```
>
> Polish incrementale di onboarding (glossario, tooltip, in-line help dei nuovi pannelli) viene fatto comunque in ogni fase per la sua superficie specifica; la *Fase 23 vera e propria* (tutorial guidati, scenari ipotesi-driven, cheat-sheet completo) si scrive una volta sola, alla fine, sul prodotto v1 stabilizzato.

### Fase 21 — Visibilità + onestà del manuale ✅ DONE (tag `phase-21`)

**Goal**: l'app smette di "promettere e tacere".

- Traccia 1 (tutti i 14 audit events mancanti) — **12/14 chiusi**, restano L2.13/L2.14 → Fase 26
- Traccia 7.8 (sezione "Limitazioni note v1" nel manuale)
- Traccia 7.1 (aggregare `:regulator_output` strutturalmente) — wiring runtime σ deferred a Fase 25
- Plus: HGT ledger channel disambiguation, trait tracker time-series, smoke test E2E

---

### Fase 22 — Analisi base + polish ✅ DONE (tag `phase-22`)

**Goal**: i 3 strumenti più richiesti, e un'app che "sembra finita" nei primi 5 minuti.

- Traccia 2.1 (trait tracker time-series macro) — *anticipato in Fase 21 #4*
- Traccia 2.3a (diff genoma macroscopico) ✅
- Traccia 2.4 (mappa metabolica del biotopo) ✅
- Traccia 2.8 (distribuzione fenotipica strip plot) ✅
- Traccia 8 (polish trasversale: stress chip, Tailwind canonical) ✅
- Plus: smoke test E2E

---

### Fase 24 — Lab notebook ◀ NEXT

**Goal**: il sistema diventa uno strumento di studio condivisibile.

- Traccia 6.1 (annotazioni)
- Traccia 6.2 (permalink temporali)
- Traccia 6.3 (snapshot bookmarkati)
- Traccia 6.4 (replay con scrubbing)
- Traccia 6.8 (export notebook-ready parquet/AnnData)

**Effort**: ~1.5 settimane. Replay scrubbing è la voce più costosa (richiede ricostruzione da snapshot+WAL).

---

### Fase 25 — Operoni e regolazione (fondamenta molecolari) ✅ DONE (tag `phase-25`)

**Split deliberato (2026-05-08)**: la Fase 25 originale aveva 6 sotto-tracce mescolando *strutturali* (additive, basso rischio) e *runtime-cabling* (alto rischio sulla calibrazione Phase 5/6/7). Per "fare le cose per bene" ho splittato in due tranche e consegnato la prima:

**Phase 25 (consegnata)** — 5 sub-deliverable strutturali / view-layer additivi:

- ✅ Traccia 7.2a (`Arkea.Genome.Operon` — grouping helper)
- ✅ Traccia 7.3 (`Arkea.Genome.Regulation` — parser promoter/riboswitch)
- ✅ Traccia 2.5 (`Arkea.Views.RegulatoryNetwork` — graph builder)
- ✅ Traccia 3.1/3.4/3.5 (`Phylogeny.enrich_with_branch_metrics/2` + `colour_by_trait/2`)
- ✅ Traccia 2.2 (`Arkea.Views.GeneExpression.derive/2` — per-gene view)
- Plus: smoke test E2E

Zero impatto runtime — Phase 5/6/7 calibration intatta. Le 5 tracce sono già consumabili da Fase 26 (codon viewer / ancestral reconstruction).

**Phase 25.5 (deferred)** — runtime cabling:

- Traccia 7.2b (operon-aware σ in `Tick.step_expression/1`; kcat scaling polycistronico per i membri)
- Traccia 7.6 (SOS threshold derivato dai `:ligand_sensor(:dna_damage)` del lignaggio invece della costante modulo-level)

Questa tranche è esplicitamente *invasiva* sul runtime e va affrontata con cura dedicata: pre-scrittura di property-test sugli invarianti evolutivi, calibration dance per non rompere Phase 5/6/7, possibile config flag a 0-effetto di default per soft-rollout. Effort stimato 1-2 settimane in una sessione dedicata.

---

### Fase 26 — Codon level

**Goal**: il livello sub-dominio diventa visibile e analizzabile.

- Traccia 2.6 (codon-level viewer con zoom progressivo)
- Traccia 2.7 (mutation hotspot map per gene)
- Traccia 2.9 (landscape struttura-funzione di dominio)
- Traccia 2.3b (diff codonico fra varianti)
- Traccia 3.6, 3.7, 3.8 (ricostruzione ancestrale + gene tree)
- Traccia 8.9, 8.10 (distinzione visiva replicon, tooltip chimico)
- Traccia 1.13, 1.14 (audit `:domain_flip` e `:gene_chimera_birth`) — possono anche stare in Fase 21, qui solo se serve la vista per renderli utili

**Effort**: ~2.5 settimane. La maggior parte UI nuovo, ma la pipeline dati c'è già.

---

### Fase 27 — Interventi avanzati

**Goal**: il giocatore può fare esperimenti, non solo osservare.

- Traccia 5.1 (plasmide custom inoculabile)
- Traccia 5.2 (xenobiotici multipli)
- Traccia 5.3 (nutrienti specifici)
- Traccia 5.4 (shift environment)
- Traccia 5.5 (inoculazione lignaggio cross-biotope)
- Traccia 5.6 (dosaggio temporale schedulato)
- Traccia 5.7 (mutagenesi in silico guidata)
- Traccia 5.8 (KO/KD) — KD dipende da 7.3 (Fase 25)
- Traccia 5.9 (heterologous expression)
- Traccia 5.10 (pulse mutageno)
- Traccia 6.5, 6.6, 6.7 (bookmark eventi molecolari + export FASTA/GFF)

**Effort**: ~2.5 settimane. Distribuibile in sotto-PR per intervento.

---

### Fase 28 — Triade coniugazione + R-M sequence

**Goal**: HGT a livello molecolare credibile.

- Traccia 7.5 (triade `pili_like + relaxase_like + oriT_like` come `reaction_class` espliciti; coniugazione richiede tutti e tre)
- Traccia 7.7 (R-M con tag-sequence di N codoni per modellare specificità Type II/III)

**Effort**: ~1.5 settimane. **Rischio**: medio (riequilibratura tassi, richiede ri-calibrazione).

---

### Fase 29 — Ribosoma derivato

**Goal**: chiudere l'ultimo "tutto è genoma" outstanding.

- Traccia 7.4 (ribosome derivato dai domini, non hardcoded)

**Effort**: ~3 giorni se delegato a un sotto-modello semplice, fino a 1 settimana se modellato come operone rRNA-like + r-protein-like.

---

### Fase 23 — Onboarding (LAST — sequenza riveduta)

**Goal**: utente nuovo produttivo in 30 minuti **sul prodotto v1 stabilizzato**.

Spostata in coda perché tutti i suoi sotto-item dipendono dalle fasi precedenti:

- Traccia 4.1 (quick-start scenari ipotesi-driven) — richiede `:xenobiotic_pulse` schedulato (Fase 27) e σ runtime (Fase 25) per produrre scenari completi anziché monchi.
- Traccia 4.2a + 4.2b (tutorial guidati biotopo + anatomia gene) — il tutorial molecolare richiede il codon-level viewer (Fase 26) per chiudere il loop didattico.
- Traccia 4.3 (cheat-sheet metaboliti × archetipi) — l'unico item *parzialmente* indipendente; può essere anticipato come quick win se serve.
- Traccia 4.4 (glossario espanso a campi panel + termini molecolari) — accumulato in modo incrementale dalle fasi precedenti; alla Fase 23 si rivede e completa.
- Traccia 4.5 (help context-sensitive con "?") — UI infrastruttura.
- Traccia 4.6 (mappa dominio → funzione reale) — gli esempi danno il loro meglio con la cascata regolatoria runtime (Fase 25) attiva.

**Effort**: ~1 settimana, prevalentemente UI + scrittura. Eccezione: polish di onboarding incrementale (glossario/tooltip della feature corrente) viene fatto comunque in ogni fase per la sua superficie specifica — la *Fase 23 vera e propria* si scrive una volta sola sul prodotto completo.

---

## 5. Dipendenze critiche

```
7.8 (Limitazioni note v1)  →  PRECEDE TUTTO (≤ 1 giorno, blocca rilascio)

7.1 (regulator_output → σ)  →  abilita  2.5 (network regolatorio)
                            →  abilita  parte di 3.X (filtri per σ)

7.2 (Operon module)         →  abilita  2.5 (network regolatorio)
                            →  abilita  espressione coordinata

7.3 (promoter/regulatory)   →  abilita  5.8 KD (knockdown via promoter)
                            →  abilita  parte di 2.5

5.8 KD                      →  dipende da 7.3
5.7 mutagenesi guidata      →  indipendente, espone API esistente

2.6 (codon viewer)          →  indipendente, ma 2.7 e 3.7 ne dipendono per UX
2.5 (network regolatorio)   →  dipende da 7.1 + 7.2 (+ idealmente 7.3)
3.7 (sequenza ancestrale)   →  dipende da 2.6 per visualizzazione
3.8 (gene tree)             →  dipende da 1.1–1.4 per disambiguare HGT
```

---

## 6. File critici (riferimento — non modificati in questa pianificazione)

### Sim core
- `arkea/lib/arkea/sim/hgt.ex` — coniugazione (7.5, 1.1)
- `arkea/lib/arkea/sim/hgt/channel/transformation.ex` — trasformazione (1.2)
- `arkea/lib/arkea/sim/hgt/phage.ex` — fagi (1.3, 1.4)
- `arkea/lib/arkea/sim/hgt/defense.ex` — R-M (1.5, 7.7)
- `arkea/lib/arkea/sim/bacteriocin.ex` — bacteriocine (1.7)
- `arkea/lib/arkea/sim/mutator.ex` — SOS, mutator, Eigen (1.8, 1.9, 1.10, 7.6)
- `arkea/lib/arkea/sim/migration/` — migrazione (1.12)
- `arkea/lib/arkea/sim/phenotype.ex` — aggregazione, ribosome hardcoded (7.1, 7.4, 1.11)
- `arkea/lib/arkea/sim/intervention.ex` (path da verificare) — interventi (5.1–5.10)
- `arkea/lib/arkea/sim/tick.ex` — biofilm formation (1.11)

### Genome
- `arkea/lib/arkea/genome/gene.ex` — operon_id, promoter_block, regulatory_block (7.2, 7.3)
- `arkea/lib/arkea/genome/codon.ex` — alfabeto 20, weighted_sum (riferimento 2.6)
- `arkea/lib/arkea/genome/mutation/` — substitution, indel, dup, inv, transl (5.7)
- `arkea/lib/arkea/genome/mutation/applicator.ex` — emissione `:domain_flip`, `:gene_chimera_birth` (1.13, 1.14)
- *(da creare)* `arkea/lib/arkea/genome/operon.ex` (7.2)

### UI LiveView
- `arkea/lib/arkea_web/live/sim_live.ex` — biotope viewport (host di 2.X, 5.X, 6.X)
- `arkea/lib/arkea_web/live/hgt_ledger_live.ex` — ledger (consumer di 1.1–1.7)
- `arkea/lib/arkea_web/live/audit_live.ex` — audit feed (consumer di tutti gli eventi)
- `arkea/lib/arkea_web/live/seed_lab_live.ex` — Seed Lab (estensione 5.1 plasmide custom)
- `arkea/lib/arkea_web/live/help_live.ex` — help (estensione 4.X)

### UI components
- `arkea/lib/arkea_web/components/genome_canvas.ex` — cromosoma circolare (estensione 8.9)
- `arkea/lib/arkea_web/components/phylogeny.ex` — dendrogramma (estensione 3.X)
- `arkea/lib/arkea_web/components/chart.ex` + `population_trajectory.ex` — time-series (estensione 2.1, 2.2)
- `arkea/lib/arkea_web/components/help.ex` — glossario (estensione 4.4, 4.5)
- *(da creare)* `arkea/lib/arkea_web/components/codon_viewer.ex` (2.6)
- *(da creare)* `arkea/lib/arkea_web/components/regulatory_network.ex` (2.5)
- *(da creare)* `arkea/lib/arkea_web/components/metabolic_map.ex` (2.4)

### Dati
- `arkea/lib/arkea/scenarios.ex` — scenari (estensione 4.1)
- *(da creare)* migration per `biotope_annotations` (6.1) e `biotope_bookmarks` (6.3)

### Documentazione
- `USER-MANUAL.md` (it) + `USER-MANUAL.en.md` (en) — sezione "Limitazioni note v1" (7.8)
- `devel-docs/04-CALIBRATION.md` — sezione "Limitazioni note v1" (7.8)
- `devel-docs/13-MICROBIOLOGIST-PERSPECTIVE-REVIEW.md` — review macro (origine)
- `devel-docs/14-BIOMOL-PERSPECTIVE-REVIEW.md` — review mol (origine)

---

## 7. Verifica end-to-end

### 7.1 Test scientifico (post Fase 21)

Eseguire scenario "arms race ospite-fago + xenobiotic pulse" per 500 tick. Criteri di successo:

- [ ] Almeno 1 evento per ognuna delle 14 categorie audit (Traccia 1)
- [ ] `HGTLedgerLive` mostra eventi distinti per i 4 canali (`:conjugation_event`, `:transformation_event`, `:transduction_event`, `:phage_infection`)
- [ ] `AuditLive` mostra `:rm_digestion`, `:bacteriocin_kill`, `:sos_active`, `:mutator_emergence`
- [ ] La sezione "Limitazioni note v1" è leggibile in `/help/calibration` o `/help/manual`

### 7.2 Test usabilità (post Fase 23)

1–2 utenti microbiologi/biolmol non coinvolti, 30 min esplorazione + 15 min task strutturati:

- [ ] "Trova un evento di trasformazione" → completato senza assistenza
- [ ] "Descrivi la struttura di un gene di un lignaggio a tua scelta" → identifica codoni, type_tag, parameter_codons, almeno 2 domini con i loro params
- [ ] "Dimmi quando emerge il primo mutator" → individua evento `:mutator_emergence` o equivalente nel ledger
- [ ] "Disegna l'arms race ospite-fago vista finora" → usa Trait tracker (2.1) o mappa metabolica (2.4) o filogenesi (3.X) come strumento

Criterio: ≥80% task completati.

### 7.3 Test molecolare (post Fase 25 + 26)

Scenario "evoluzione resistenza β-lattamico" per 1000 tick:

- [ ] Codon-level viewer mostra l'accumulo di `:substitution` nel `:catalytic_site` della β-lattamasi
- [ ] Mutation hotspot map evidenzia codoni più colpiti
- [ ] Network regolatorio mostra `:regulator_output` che attiva trascrizione di geni efflux sotto stress
- [ ] Espressione per-gene per-tick mostra induzione σ-stress
- [ ] Ricostruzione ancestrale identifica il MRCA dei lignaggi resistenti

### 7.4 Test narrativo

Aprire `01-DESIGN.md` Blocco 5 (sistema generativo dei domini), trovare la promessa "gene = sequenza di codoni logici (50–200), alfabeto 20, struttura `[promoter_block] [regulatory_block opz.] domain_1 ... domain_N`". Aprire l'app. Dimostrare che ogni elemento è osservabile in <10 minuti senza spiegazioni esterne.

Criterio: tutti gli elementi della frase sono direttamente cliccabili o ispezionabili in UI.

---

## 8. Note operative

- **Sequenza non rigida**: le 9 fasi sono in ordine di valore/sforzo, ma le tracce 4 (onboarding) e 8 (polish) possono essere distribuite trasversalmente in ogni fase. La fase 21 + 7.8 è l'unica con priorità assoluta.
- **Scope per PR**: ogni traccia è autonoma. Suggerito 1 PR per Fase, con sotto-PR per traccia se diventa >800 LoC.
- **Rischio di rottura**: massimo in Fase 25 (modifiche al fenotipo). Richiede property-test estesi e validazione su scenari di calibrazione esistenti (`Scenarios`).
- **Dichiarazione di limiti progressiva**: ogni fase che implementa un item di Traccia 7 deve aggiornare la sezione "Limitazioni note v1" rimuovendo il punto correlato. Il manuale rimane sempre veritiero.
- **Bilingue**: tutti i doc utenti aggiornati in italiano + inglese (vedi `bilingual-docs-maintainer` agent).

---

## 9. Top 5 azioni di apertura (da fare per primi)

In ordine di valore/sforzo, **prima settimana**:

1. **Sezione "Limitazioni note del modello v1"** (Traccia 7.8) — onestà documentale prima di tutto. **Effort: 1 giorno**.
2. **Audit events HGT split** (Traccia 1.1–1.4) — `HGTLedgerLive` smette di essere finta. **Effort: 2 giorni**.
3. **Audit events R-M, bacteriocine, SOS, mutator, error catastrophe, biofilm, migrazione** (Traccia 1.5–1.12) — il sistema racconta tutto quello che fa. **Effort: 3 giorni**.
4. **Trait tracker time-series macro** (Traccia 2.1) — sblocca il workflow base "vedo evolvere un tratto". **Effort: 2 giorni**.
5. **Aggregare `:regulator_output` in σ multi-componente** (Traccia 7.1) — fondamenta per ogni intervento sulla regolazione successivo. **Effort: 3 giorni** (incluse property-test).

Totale: ~2 settimane di un singolo dev. Output: l'app comunica onestamente, gli eventi sono visibili, il primo strumento di analisi vero è disponibile, e si è sbloccata l'evoluzione futura del sistema regolatorio.
