# Revisione di coerenza implementazione ↔ design — Arkea

**Reviewer**: design-coherence-reviewer
**Data**: 2026-05-06
**Stato implementativo analizzato**: Fasi 0-20 consolidate
**Documenti canonici**: `01-DESIGN.md`, `03-IMPLEMENTATION-PLAN.md`, `05-BIOLOGICAL-MODEL-REVIEW.md`, `04-CALIBRATION.md`
**Documento parallelo**: `09-BIOLOGICAL-MODEL-REVIEW-2.md` (review scientifica del modello)

---

## Executive summary

L'implementazione attuale (Fasi 12-20) è strutturalmente allineata con i principi fondanti del `01-DESIGN.md` Blocco 5 per i meccanismi principali: il tick è puro, i meccanismi metabolici emergono da composizione di domini, i canali HGT esistono. Tuttavia il report identifica **tre aree di deriva concreta** che richiedono azione:

1. il behaviour `HGT.Channel` non copre la coniugazione,
2. l'audit log non emette eventi per-meccanismo per trasformazione, trasduzione, R-M digestion, bacteriocin kill, SOS attivo ed error catastrophe,
3. la soglia SOS è una costante modulo-level anziché derivata dal genoma come prescritto da `05-BIOLOGICAL-MODEL-REVIEW.md` Fase 17.

Il sim core è pulito da I/O nei moduli di calcolo puro; i moduli orchestratori (Server, WorldClock, Coordinator, Scenario) hanno I/O dove atteso. Il modello generativo regge: non si trova nessun lookup table hardcoded per organismi specifici.

---

## 1. Principio: "tutto è metabolismo" e "tutto è codificato nel genoma" (Blocco 5)

### Conformi

- `Arkea.Sim.Phenotype` (`lib/arkea/sim/phenotype.ex`) deriva tutti i tratti dal genoma tramite composizione di domini: `competence_score` (linea 74-80), `restriction_profile`, `methylation_profile`, `biofilm_capable?`, `target_classes`, `hydrolase_capacity`, `efflux_capacity`, `detoxify_targets`. Nessun flag esplicito non derivabile.
- La coniugazione è condizionata dalla presenza di `:transmembrane_anchor` nei plasmidi (`lib/arkea/sim/hgt.ex:68-84`), proxy generativo per `pili_like`.
- La competenza per trasformazione è proxy generativo basato su co-occorrenza `:channel_pore + :transmembrane_anchor + :ligand_sensor` (`lib/arkea/sim/hgt/channel/transformation.ex:107-113`).
- Bacteriocin: co-occorrenza `:substrate_binding + :catalytic_site(:hydrolysis) + :transmembrane_anchor` (`lib/arkea/sim/bacteriocin.ex:15-17`).
- Biofilm: co-occorrenza `:surface_tag + :structural_fold(multimerization_n >= 2)` (`lib/arkea/sim/phenotype.ex`, `lib/arkea/sim/tick.ex:691-695`).

### Deviazioni

#### Deviazione — SOS threshold come costante modulo-level

`05-BIOLOGICAL-MODEL-REVIEW.md` Fase 17 prescrive: "SOS attiva quando dna_damage > threshold codificato in un `:ligand_sensor` DNA-damage-like del lineage". L'implementazione usa invece `@sos_active_threshold = 0.20` come modulo-attribute globale in `lib/arkea/sim/mutator.ex:80`. La soglia non è derivata dal genoma: è identica per tutti i lignaggi indipendentemente dai loro `:ligand_sensor`. Questo viola il principio "tutto è codificato nel genoma" per questo specifico trait.

- **File**: `lib/arkea/sim/mutator.ex:80`
- **Design prescrive**: threshold derivata da `:ligand_sensor` (DNA-damage-like) del lignaggio
- **Codice fa**: `@sos_active_threshold 0.20` uniforme per tutti
- **Severità**: 🟡 Drift (la costante calibrata è documentata in `03-IMPLEMENTATION-PLAN.md` come Phase 20 update; il principio generativo è disatteso)
- **Raccomandazione**: aggiornare `05-BIOLOGICAL-MODEL-REVIEW.md` Fase 17 riflettendo la scelta semplificata, oppure aggiungere un campo `sos_threshold` a `Phenotype` derivato dalla media dei `:ligand_sensor` domains del lineage.

#### Deviazione — `ribosome_like: 1.0` hardcoded

`lib/arkea/sim/phenotype.ex:291` assegna `ribosome_like: 1.0` a tutti i lignaggi incondizionatamente, come "baseline biologica". Questo è un caso speciale hardcoded: un genoma senza alcun gene ribosomale-like riceve lo stesso `ribosome_like` score di un genoma con molti. Il `01-DESIGN.md` Blocco 5 prescrive "No special case: genoma random senza i domini chiave non triggera mai il meccanismo."

- **File**: `lib/arkea/sim/phenotype.ex:291`
- **Design prescrive**: ogni trait emerge da composizione di domini; genoma privo di domini rilevanti non triggera il meccanismo
- **Codice fa**: score `1.0` fisso per tutti, indipendentemente dal genoma
- **Severità**: 🟡 Drift (la documentazione locale lo giustifica come "ogni cellula ha ribosomi", ma rompe il principio generativo)
- **Raccomandazione**: documentare esplicitamente in `01-DESIGN.md` Blocco 5 questa eccezione deliberata, oppure derivare `ribosome_like` da un conteggio di domini `:structural_fold(multimerization_n >= 5)` come proxy per il complesso ribosomiale.

#### Deviazione — proxy coniugazione non aggiornato

`03-IMPLEMENTATION-PLAN.md` Fase 6 nota esplicitamente: "Proxy per coniugazione gene-encoded: un plasmide è coniugativo se e solo se contiene almeno 1 dominio `:transmembrane_anchor`; la verifica full domain-composition (`pili_like + relaxase_like + oriT_like`) è rinviata a Phase 8." La Fase 8 è marcata completata (migrazione inter-biotopo) ma il proxy non è stato raffinato: `lib/arkea/sim/hgt.ex:62-84` usa ancora solo `:transmembrane_anchor`. Il `01-DESIGN.md` Blocco 5 prescrive la triade completa.

- **File**: `lib/arkea/sim/hgt.ex:62-84`
- **Design prescrive**: `pili_like + relaxase_like + oriT_like` (`01-DESIGN.md` Blocco 5)
- **Codice fa**: solo `:transmembrane_anchor` count
- **Severità**: 🟡 Drift (documentato come semplificazione, ma "Phase 8" è passata senza refinement)
- **Raccomandazione**: aggiornare `05-BIOLOGICAL-MODEL-REVIEW.md` o `03-IMPLEMENTATION-PLAN.md` per indicare esplicitamente che il refinement è rinviato oltre Fase 20, con la motivazione biologica.

---

## 2. Principio: sim core puro — nessun I/O nei moduli `Arkea.Sim.*`

### Conformi — moduli di calcolo puro

Tutti i moduli di calcolo in `lib/arkea/sim/` che implementano la logica del tick sono privi di I/O:

- `lib/arkea/sim/tick.ex`: nessun `Repo.`, `Logger.`, `IO.`, PubSub, `Process.send_after`
- `lib/arkea/sim/hgt.ex`, `hgt/phage.ex`, `hgt/channel/transformation.ex`, `hgt/defense.ex`
- `lib/arkea/sim/metabolism.ex`, `biomass.ex`, `mutator.ex`, `bacteriocin.ex`, `xenobiotic.ex`, `signaling.ex`, `phenotype.ex`

### Conformi ma da verificare — moduli orchestratori

I seguenti moduli in `lib/arkea/sim/` hanno I/O ma sono moduli di orchestrazione/infrastruttura, non funzioni di tick:

- `lib/arkea/sim/biotope/server.ex:153,247,266`: `Logger.debug`, `Logger.info`, `Phoenix.PubSub.broadcast` — tutti nel `GenServer` orchestratore, non nel tick puro. Corretto.
- `lib/arkea/sim/world_clock.ex:69-70,82-83`: `Process.send_after`, `Logger.info`, `Phoenix.PubSub.broadcast` — nel WorldClock GenServer. Corretto.
- `lib/arkea/sim/migration/coordinator.ex:52,80,94,98,102`: PubSub, `Process.send_after`, `Logger.warning` — nel Coordinator GenServer. Corretto.
- `lib/arkea/sim/seed_scenario.ex:62,84,88`: `Logger.debug/info/warning` — modulo di bootstrap, non nel tick.
- `lib/arkea/sim/cronache_scenario.ex:86`: `Logger.info` — idem.

Il boundary I/O è rispettato: tutto il calcolo puro (`Tick.tick/1` e funzioni chiamate da esso) è privo di side effect.

### Nota — `Intervention.apply` fuori dal tick

`lib/arkea/sim/intervention.ex` viene chiamato da `Biotope.Server.handle_call({:apply_intervention, _})` (linea 198-207), dove `post_transition` esegue broadcast e persistenza dopo la trasformazione pura. Questa è la disciplina corretta. `Intervention.apply/2` ritorna `{:ok, new_state, events, payload}` — pattern pulito.

**Nessuna violazione critica trovata per questo principio.**

---

## 3. Principio: audit log write path — event structs dal tick, persistiti da Server

### Conformi

- `lib/arkea/sim/tick.ex` `derive_events/2` (linee 1018-1071) emette: `:lineage_born`, `:lineage_extinct`, `:hgt_transfer` (per plasmidi guadagnati), `:mutation_notable`, `:mass_lysis`, `:colonization`, `:phage_burst`. Tutti ritornati come lista di event structs nel tuple `{new_state, events}`.
- `lib/arkea/sim/biotope/server.ex:255-258` (`do_tick`) chiama `Tick.tick(state)` poi `post_transition(state.id, new_state, events, :tick)` che internamente fa `Store.persist_transition/3`.
- `lib/arkea/persistence/store.ex` esegue `AuditWriter.insert_events/5` nel Multi transazionale.
- `community_provisioned` è correttamente emesso da `lib/arkea/game/seed_lab.ex:836-840` e persistito via `Store.persist_transition`.

### Deviazione critica — eventi per-meccanismo HGT non emessi

`05-BIOLOGICAL-MODEL-REVIEW.md` Fase 16 (linea 202) prescrive: "audit_writer handler per nuovi event: `:transformation_event`, `:transduction_event`, `:phage_infection`, `:plasmid_displaced`, `:rm_digestion`, `:bacteriocin_kill`, `:error_catastrophe_death`." La stessa sezione nota che "Emissione esplicita... sarà cablata in Fase 16/17."

Grep conferma che nessuno di questi event type è emesso da `tick.ex` o dai moduli HGT. `derive_events/2` emette `:hgt_transfer` solo se un nuovo lignaggio ha guadagnato plasmidi rispetto al parent — non distingue se la fonte è coniugazione, trasformazione o trasduzione. I canali `:transformation_event`, `:rm_digestion`, ecc. non sono mai generati.

- **File**: `lib/arkea/sim/tick.ex:1018-1071`, `lib/arkea/sim/hgt/channel/transformation.ex`, `lib/arkea/sim/hgt/phage.ex`, `lib/arkea/sim/hgt/defense.ex`
- **Design prescrive**: eventi tipizzati per ogni meccanismo HGT nel return del tick
- **Codice fa**: un unico `:hgt_transfer` generico, derivato post-hoc da diff dei plasmidi, senza origin channel
- **Severità**: 🔴 Drift (i canali sono implementati, l'audit del channel non lo è)
- **Raccomandazione**: in `run_transformation` e `HGT.induction_step` accumulare event structs tipizzati (`transformation_event`, `rm_digestion`) da aggiungere al return di `step_hgt`, poi includere in `derive_events` o passarli direttamente da `tick/1`. La View `HgtLedger` già si aspetta `hgt_transformation_event` e `hgt_transduction_event` (`lib/arkea/views/hgt_ledger.ex:21`): c'è disallineamento tra la View e il sim core.

### Deviazione — View HgtLedger aspetta event type che il sim non emette

`lib/arkea/views/hgt_ledger.ex:21-22` filtra su `hgt_transformation_event`, `hgt_transduction_event`, `rm_digestion`, `plasmid_displaced`, `phage_burst`, `phage_infection`. Di questi, solo `phage_burst` è emesso da `derive_events/2` (tramite `detect_phage_burst`). Gli altri non vengono mai scritti in `audit_log`.

- **File**: `lib/arkea/views/hgt_ledger.ex:21-22` vs `lib/arkea/sim/tick.ex:1018-1071`
- **Severità**: 🟡 Drift (la View è incompleta perché il write path sim non è chiuso)
- **Raccomandazione**: allineato alla deviazione sopra; la View può restare, ma il write path sim va completato.

---

## 4. Principio: sequenza step nel tick (Fase 18)

`03-IMPLEMENTATION-PLAN.md` Fase 18 (linea 471) prescrive la sequenza finale:

```
step_metabolism → step_xenobiotic → step_biomass → step_signaling → step_bacteriocin →
step_expression → step_cell_events → step_dna_damage → step_hgt → step_phage_infection →
step_environment → step_lysis → step_mixing_event → step_pruning
```

L'implementazione in `lib/arkea/sim/tick.ex:117-133`:

```elixir
|> step_metabolism()
|> step_xenobiotic()
|> step_biomass()
|> step_signaling()
|> step_bacteriocin()
|> step_expression()
|> step_cell_events()
|> step_dna_damage()
|> step_hgt()
|> step_phage_infection()
|> step_environment()
|> step_lysis()
|> step_mixing_event()
|> step_pruning()
|> increment_tick()
```

La sequenza è **identica** a quella prescritta. Nessuna anomalia.

`05-BIOLOGICAL-MODEL-REVIEW.md` (round 1) prescriveva una sequenza precedente (Fasi 12-15). La sequenza attuale riflette l'evoluzione finale documentata in `03-IMPLEMENTATION-PLAN.md` Fase 18 ed è quella autoritativa.

### Divergenza minore

La sequenza dell'HGT interno: `05-BIOLOGICAL-MODEL-REVIEW.md` descrive `step_hgt` come orchestratore di "conjugation→transformation→transduction→phage_infection". L'implementazione in `step_hgt` esegue conjugation → transformation → prophage induction, poi `step_phage_infection` è uno step separato al livello superiore. La trasduzione generalizzata è implementata dentro `HGT.Phage.lytic_burst` (all'interno di `induction_step`), non come un sub-step esplicito "transduction" nel tick. È coerente con quanto scritto in `03-IMPLEMENTATION-PLAN.md` Fase 16, ma diverge leggermente dalla descrizione in `05-BIOLOGICAL-MODEL-REVIEW.md` che prevedeva un `transduction.ex` separato.

---

## 5. Principio: behaviour `HGT.Channel` con callback uniformi

### Conformi

- `lib/arkea/sim/hgt/channel.ex` definisce il behaviour con `@callback step/4` e `@callback name/0`.
- `lib/arkea/sim/hgt/channel/transformation.ex:47` adotta `@behaviour Arkea.Sim.HGT.Channel` e implementa `step/4` e `name/0`.
- `lib/arkea/sim/hgt/phage.ex:35` adotta `@behaviour Arkea.Sim.HGT.Channel`, implementa `step/4` delegato a `infection_step/4`, e `name/0`.

### Deviazione — la coniugazione non implementa il behaviour

`05-BIOLOGICAL-MODEL-REVIEW.md` Fase 16 e `03-IMPLEMENTATION-PLAN.md` Fase 16 prescrivono quattro implementazioni del behaviour: `Conjugation` (refactor dell'attuale `HGT`), `Transformation`, `Transduction`, `PhageInfection`. Il documento nota "conformance al behaviour rinviata a Fase 17".

Grep conferma: `lib/arkea/sim/hgt.ex` NON ha `@behaviour Arkea.Sim.HGT.Channel`. La firma di `HGT.step/4` è `(phase_name, lineages, tick, rng)` mentre il behaviour richiede `(lineages, phase, tick, rng)`: le firme sono incompatibili.

- **File**: `lib/arkea/sim/hgt.ex:101-106` vs `lib/arkea/sim/hgt/channel.ex:45-51`
- **Design prescrive**: `Conjugation` come implementazione di `HGT.Channel`
- **Codice fa**: `HGT.step/4` con firma diversa, nessun `@behaviour`
- **Severità**: 🔴 Drift (documentato come "rinviato", ma Fase 17 è marcata completata senza il refactor)
- **Raccomandazione**: o eseguire il refactor di `HGT.step` per conformarsi al behaviour (aggiustando la firma e aggiungendo `name/0 -> :conjugation`), o aggiornare `03-IMPLEMENTATION-PLAN.md` per indicare esplicitamente che il refactor della coniugazione è rinviato oltre Fase 20 con motivazione.

### Deviazione — il behaviour definisce solo `step` e `name`, non `donor_pool/2`, `transfer_rate/3`, `integrate/3`

`05-BIOLOGICAL-MODEL-REVIEW.md` Fase 16 prescrive callback `donor_pool/2`, `transfer_rate/3`, `integrate/3`. Il behaviour implementato definisce solo `step/4` e `name/0` — un'interfaccia più compatta ma diversa da quella prescritta.

- **File**: `lib/arkea/sim/hgt/channel.ex:44-57` vs `05-BIOLOGICAL-MODEL-REVIEW.md` Fase 16
- **Severità**: 🟡 Drift (l'interfaccia implementata è funzionalmente equivalente; la granularità dei callback è diversa)
- **Raccomandazione**: aggiornare `05-BIOLOGICAL-MODEL-REVIEW.md` per riflettere l'interfaccia effettiva (`step/4, name/0`), oppure aggiungere i callback mancanti se servono per dialyzer o polimorfismo futuro.

### Deviazione — il modulo `HGT.Channel.Transduction` non esiste

`03-IMPLEMENTATION-PLAN.md` Fase 16 descrive la trasduzione generalizzata come implementata tramite `Virion.payload_kind :: :generalized_transduction` in `HGT.Phage.lytic_burst`. Non esiste un `lib/arkea/sim/hgt/channel/transduction.ex` separato. La trasduzione è folded nel ciclo fagico esistente. Questo è architetturalmente pulito, ma diverge dalla struttura a 4 canali distinti prescritta in `05-BIOLOGICAL-MODEL-REVIEW.md` Fase 16.

- **File**: `lib/arkea/sim/hgt/phage.ex:163-224` vs `05-BIOLOGICAL-MODEL-REVIEW.md` Fase 16
- **Severità**: 🟢 Cosmetic (la funzionalità c'è; l'astrazione manca)
- **Raccomandazione**: documentare la decisione di integrare la trasduzione nel ciclo fagico invece di creare un canale separato.

---

## 6. Sospetti di "special case" hardcoded

### Candidato 1 — `ribosome_like: 1.0`

`lib/arkea/sim/phenotype.ex:291` — pattern matching diretto su un target_class con valore fisso. Non deriva dal genoma. Vedi §1.

### Candidato 2 — `@toxicity_profile` lookup table hardcoded

`lib/arkea/sim/metabolism.ex:159-163`:
```elixir
@toxicity_profile %{
  oxygen: {50.0, 200.0},
  h2s: {20.0, 80.0},
  lactate: {30.0, 100.0}
}
```

Solo 3 metaboliti su 13 sono tossici, con threshold numeriche fisse. Questa è una lookup table hardcoded: i valori non emergono da composizione di domini. Il `01-DESIGN.md` Blocco 5 dice "tutto è metabolismo", ma qui la tossicità è codificata come tabella di costanti per specifici atom. La linea 113-121 documenta l'intenzione calibrativa.

- **File**: `lib/arkea/sim/metabolism.ex:159-163`
- **Severità**: 🟡 Drift — i valori sono documentati come "Phase 14 first-pass conservative" e "Phase 17 will refine", ma nessuno è derivato dal genoma
- **Raccomandazione**: documentare in `01-DESIGN.md` che il profilo di tossicità è un parametro del biotopo/ambiente (non del genoma), e aggiornare Blocco 8 di conseguenza.

### Candidato 3 — `@atp_coefficients` lookup table hardcoded

`lib/arkea/sim/metabolism.ex:81-95` — mappa da metabolita atom a coefficiente ATP numerico. Questi non emergono da composizione di domini: due genomi con diversa composizione ma stessa affinità per glucosio ricevono lo stesso coefficiente ATP.

- **File**: `lib/arkea/sim/metabolism.ex:81-95`
- **Severità**: 🟡 Drift (documentato come "Phase 5 simplification"; la stechiometria reale è incomprimibile in un sistema generativo puro)
- **Raccomandazione**: allineato al `01-DESIGN.md` che già descrive "Proto-FBA stazionario ricalcolato per tick" — questo è il FBA semplificato, corretto per design.

### Candidato 4 — `@aerobic_substrates` lista hardcoded

`lib/arkea/sim/metabolism.ex:121`: `@aerobic_substrates [:glucose, :acetate, :lactate, :ch4]` — lista fissa di metaboliti che ricevono il boost aerobico. Un genoma con substrati non in questa lista non riceve il boost.

- **File**: `lib/arkea/sim/metabolism.ex:121`
- **Severità**: 🟡 Drift (giustificabile biologicamente: solo substrati organici beneficiano della respirazione aerobia)
- **Raccomandazione**: documentare in `04-CALIBRATION.md` o `01-DESIGN.md` la lista come parametro del modello metabolico.

### Candidato 5 — `@catalog` xenobiotici con un solo entry

`lib/arkea/sim/xenobiotic.ex:57-69` — catalogo con un solo xenobiotico (`beta_lactam`). Il `01-DESIGN.md` Blocco 8 descrive il framework come "un catalogo additivo". Il catalogo è estendibile by design, ma attualmente hardcoded a uno.

- **File**: `lib/arkea/sim/xenobiotic.ex:57-69`
- **Severità**: 🟢 Non-issue (è intenzionale, documentato come "Phase 15 ships one canonical antibiotic")

### Candidato 6 — `@mode_severity` mappa atom → float

`lib/arkea/sim/xenobiotic.ex:75-79` — i valori di severità (`cidal: 0.95, static: 0.50, mutagen: 0.0`) non emergono da composizione di domini.

- **File**: `lib/arkea/sim/xenobiotic.ex:75-79`
- **Severità**: 🟢 Non-issue (sono parametri del drug, non del genoma; la drug ha `:mode` per design)

---

## 7. Property test coverage — matrice meccanismo × invariante

| Meccanismo | Conservation | Monotonicity | No-special-case |
|---|---|---|---|
| **HGT coniugazione** | Parziale | Assente | Presente (`hgt_test:218`) |
| **HGT difesa R-M** | Assente | Assente | Presente (`defense_test:48`) |
| **HGT trasformazione** | Parziale | Assente | Parziale |
| **HGT phage cycle** | Parziale | Assente | Parziale |
| **Trasduzione** | Assente | Assente | Assente |
| **Biomassa** | Presente | Presente (toxicity in O₂) | Parziale |
| **Xenobiotici** | Assente | Presente (`xenobiotic_test:49-55`) | Presente (`xenobiotic_test:78-80`) |
| **Bacteriocine** | Assente | Assente | Parziale (`bacteriocin_test:55-58`) |
| **SOS response** | Assente | Parziale (`sos_test`) | Assente come property StreamData |
| **Error catastrophe** | Assente | Presente (`sos_test:113`) | Assente come property StreamData |
| **Community mode** | Parziale | Assente | Parziale |
| **Biofilm** | Assente | Assente | Presente (`biofilm_test:46-57`) |
| **Mixing event** | Assente | N/A | N/A |
| **Cross-feeding** | Assente | Assente | N/A |

### Gap principali

- **Conservation** mancano per: coniugazione (Σ abundance + virioni post-burst), trasformazione (`fragment.abundance` decremento), bacteriocin (`toxin_pool` accumulo+decay), SOS (`dna_damage` in [0, max]).
- **No-special-case** via StreamData mancano per: bacteriocin, SOS, error catastrophe.

---

## 8. Documentazione disallineata

### Docs che descrivono qualcosa NON implementato

1. `05-BIOLOGICAL-MODEL-REVIEW.md` Fase 16: "Behaviour HGT.Channel con callback `donor_pool/2`, `transfer_rate/3`, `integrate/3`" — il behaviour ha solo `step/4` e `name/0`.
2. `05-BIOLOGICAL-MODEL-REVIEW.md` Fase 16: "lib/arkea/sim/hgt/channel/transduction.ex" — file non esiste.
3. `05-BIOLOGICAL-MODEL-REVIEW.md` Fase 17: "SOS attiva quando dna_damage > threshold codificato in un `:ligand_sensor`" — implementato come costante modulo-level.
4. `05-BIOLOGICAL-MODEL-REVIEW.md` Fase 17: "lib/arkea/genome/operon.ex con concetto di operone... espressione coordinata" — il campo `operon_id` esiste in `Gene` ma `Arkea.Genome.Operon` non esiste e il runtime non usa `operon_id` per nulla. **L'espressione coordinata operonica non è implementata.**
5. `05-BIOLOGICAL-MODEL-REVIEW.md` Fase 18: "I `:regulator_output` (oggi definiti ma non utilizzati nell'expression) finalmente partecipano al sigma del gene/operon target" — `lib/arkea/sim/phenotype.ex:521-523` ha un commento esplicito "All other domain types (`regulator_output`, `channel_pore`, etc.) are parsed but not yet aggregated." **I `regulator_output` non partecipano al sigma.**
6. `05-BIOLOGICAL-MODEL-REVIEW.md` Fase 16: i 7 nuovi event types per audit — nessuno è emesso.

### Codice che implementa qualcosa NON documentato

1. `lib/arkea/sim/tick.ex:991-1012`: eventi `derive_events` emette `:mutation_notable`, `:mass_lysis`, `:colonization`, `:phage_burst` — aggiunti come "UI Phase B data pipeline backfill". Non documentati in `05-BIOLOGICAL-MODEL-REVIEW.md` o `03-IMPLEMENTATION-PLAN.md` come event types formali.
2. `lib/arkea/sim/hgt/phage.ex:75`: `@transduction_probability Application.compile_env(...)` come compile-time configurable — documentato in `03-IMPLEMENTATION-PLAN.md` Fase 20 come Phase 20 feature ma non nella sezione architetturale principale.
3. `lib/arkea/sim/biotope/server.ex` espone `recolonize/3` — non documentato in `05-BIOLOGICAL-MODEL-REVIEW.md` o `03-IMPLEMENTATION-PLAN.md`; aggiunto come feature post-Fase 10.

---

## Roadmap di consolidamento — Top 5 azioni concrete

### 1. Chiudere il write path audit per eventi HGT per-canale (bloccante per feature completeness)

Aggiungere event struct accumulation nei sub-step di `step_hgt` (`run_transformation`, `HGT.induction_step`) e in `step_phage_infection`. I canali devono ritornare una lista di eventi oltre al tuple standard. `derive_events` (o un meccanismo equivalente) aggrega e ritorna questi eventi nella coppia `{new_state, events}` del tick. Allineare `lib/arkea/views/hgt_ledger.ex` con i tipi effettivamente emessi.

**File coinvolti**: `lib/arkea/sim/tick.ex`, `lib/arkea/sim/hgt.ex`, `lib/arkea/sim/hgt/channel/transformation.ex`, `lib/arkea/sim/hgt/phage.ex`.

### 2. Conformare la coniugazione al behaviour `HGT.Channel` o aggiornare il design

O refactorare `HGT.step/4` in `HGT.Channel.Conjugation.step/4` con firma `(lineages, phase, tick, rng)` e aggiungere `@behaviour Arkea.Sim.HGT.Channel`, oppure aggiornare `05-BIOLOGICAL-MODEL-REVIEW.md` e `03-IMPLEMENTATION-PLAN.md` per documentare esplicitamente che il refactor della coniugazione è rimandato e perché.

**File**: `lib/arkea/sim/hgt.ex`, `lib/arkea/sim/hgt/channel.ex`.

### 3. Documentare o correggere il SOS threshold come costante vs trait generativo

La scelta implementata (`@sos_active_threshold = 0.20` costante) è biologicamente difendibile e calibrata (Phase 20), ma contraddice `05-BIOLOGICAL-MODEL-REVIEW.md` Fase 17. Scegliere: (a) aggiornare `05-BIOLOGICAL-MODEL-REVIEW.md` riflettendo la scelta semplificata, o (b) aggiungere `sos_sensitivity` a `Phenotype` derivato dalla media dei `:ligand_sensor` con `reaction_class: :DNA_damage` come soglia per-lignaggio.

**File**: `lib/arkea/sim/mutator.ex:80`, `lib/arkea/sim/phenotype.ex`.

### 4. Documentare i meccanismi non implementati come debito esplicito

Le seguenti feature di `05-BIOLOGICAL-MODEL-REVIEW.md` Fase 17-18 hanno il campo dati ma non il runtime:

- `operon_id` in `Gene` senza `Operon` module e senza runtime expression coordinata,
- `:regulator_output` parsati ma non aggregati in sigma.

Aggiornare `03-IMPLEMENTATION-PLAN.md` con una sezione "Debito documentato post-Fase 20" che elenca questi gap esplicitamente. Impedisce false aspettative su quanto il runtime faccia.

### 5. Aggiungere property test conservation e no-special-case mancanti per Fasi 12-19

`05-BIOLOGICAL-MODEL-REVIEW.md` §Principi guida: "property tests obbligatori: (a) conservation, (b) monotonicity, (c) no-special-case". Gap più urgenti:

- `phage_test.exs`: property StreamData che `Σ(abundance_pre_burst) = Σ(abundance_post_burst) + virion_count` (conservation)
- `transformation_test.exs`: property StreamData che `fragment.abundance` decresce di esattamente 1 per uptake riuscito
- `bacteriocin_test.exs`: property che genoma random senza la triade non è producer
- `sos_test.exs`: property StreamData che `dna_damage in [0, Lineage.dna_damage_max()]` dopo N incrementi con decay

**File**: `test/arkea/sim/hgt/phage_test.exs`, `test/arkea/sim/hgt/transformation_test.exs`, `test/arkea/sim/bacteriocin_test.exs`, `test/arkea/sim/sos_test.exs`.

---

## Riepilogo finale

L'architettura core di Arkea — tick puro, un GenServer per biotopo, genoma generativo, persistenza WAL+snapshot — è **pienamente rispettata**. I meccanismi biologici delle Fasi 12-20 sono implementati e funzionanti. Le deviazioni più rilevanti sono tre:

1. l'audit log non emette eventi per-canale per trasformazione, R-M, bacteriocin kill e SOS, lasciando la View `HgtLedger` senza dati;
2. la coniugazione non aderisce al behaviour `HGT.Channel` definito;
3. due feature di Fase 17-18 (operoni runtime e `regulator_output` in sigma) hanno i campi dati ma non il runtime, senza che questo sia documentato come debito esplicito.
