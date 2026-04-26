> 🇮🇹 Italiano (questa pagina) · [🇬🇧 English](IMPLEMENTATION-PLAN.en.md)

# Arkea — Piano di implementazione (alto livello)

**Riferimenti**: [DESIGN.md](DESIGN.md), [DESIGN_STRESS-TEST.md](DESIGN_STRESS-TEST.md), [INCEPTION.md](INCEPTION.md)
**Data**: 2026-04-26
**Stato**: scelta architetturale consolidata; roadmap di fasi definita; pronto per Fase 0.

---

## 1. Contesto

Il design (15 blocchi consolidati in DESIGN.md, validato dallo stress test di DESIGN_STRESS-TEST.md) è coerente e pronto per implementazione. Lo stack è fissato (Blocco 14):

- **Sim core + orchestrazione**: Elixir + OTP
- **Web framework**: Phoenix (LiveView per ~80% UI + PixiJS in LV Hook per la vista 2D WebGL)
- **DB**: PostgreSQL via Ecto
- **Hosting prototipo**: VPS DigitalOcean 1 CPU / 1 GB RAM
- **Scope prototipo**: 5–10 biotopi, cap 100 lignaggi/biotopo, 1–4 player

Questo documento definisce **come** costruire il sistema: la scelta architetturale principale (con analisi delle alternative considerate), la roadmap di fasi incrementali, e la disciplina di sviluppo da seguire.

---

## 2. Scelta architetturale principale

### 2.1 Decisione

**Pattern Active Record (BEAM-canonical)** per la gestione di stato e tick, con due **caveat strutturali** che mitigano le debolezze del pattern e tengono aperto un path di evoluzione futura.

**Modello**:
- Un `Biotope.Server` GenServer per biotopo. Lo stato (lignaggi, fasi, metaboliti, segnali, fagi liberi) vive **in memoria del processo**, in struct Elixir.
- Il tick è una **funzione pura** `tick(state) -> {new_state, events}`, applicata sequenzialmente dal GenServer. Internamente parallelizzabile per fase via `Task.async_stream` quando il profiling lo giustifica.
- La **migrazione** inter-biotopo è orchestrata dal `Migration.Coordinator` dopo ogni tick: fan-out via `Phoenix.PubSub`.
- La **persistenza** è snapshot periodico via worker Oban (ogni 10 tick = 50 minuti reali, da Blocco 11).

### 2.2 I due caveat strutturali

**Caveat 1 — Audit log strutturato dal giorno 1**.
Anche se non adottiamo full event sourcing, il tick scrive in una tabella `audit_log` ben tipizzata gli eventi rilevanti: mutazioni notabili, HGT events, lisi massive, comparsa di chimere, interventi del giocatore, eventi di colonizzazione. Soddisfa il Blocco 13 (anti-griefing, origin tracking) e fornisce un parziale time-travel debugging senza pagare il prezzo full-CQRS. È un **subset** di event sourcing dove conserviamo solo gli eventi di interesse.

**Caveat 2 — Disciplina pure-functional del tick**.
Il tick è strettamente `state -> {new_state, events}`. Niente side-effect interni alla funzione di tick (le scritture DB, i broadcast, le notifiche avvengono *dopo* il calcolo, dal GenServer che orchestrano). Questa disciplina:
- Rende il tick massimamente testabile (property-based testing diventa naturale)
- Tiene **aperto il path di migrazione verso full event sourcing** se mai necessario in futuro: basterebbe persistere `events` invece di applicare immediatamente
- Permette di parallelizzare il tick per fasi senza problemi di concorrenza

### 2.3 Rationale

La combinazione "Active Record + audit subset + pure functions" cattura **l'80% dei benefici di event sourcing al 30% del suo costo**:

| Beneficio Event Sourcing | Soddisfatto da AR + caveat? |
|---|---|
| Audit log nativo (Blocco 13) | ✅ via tabella audit_log strutturata (caveat 1) |
| Testability del tick | ✅ via pure function (caveat 2) |
| Time-travel debugging | ⚠️ parziale: snapshot ogni 10 tick + audit log per eventi notevoli |
| Replay perfetto per analisi | ❌ richiederebbe full ES |

L'unico beneficio **non** soddisfatto è il replay perfetto. Lo accettiamo come trade-off finché non emerga un'esigenza concreta.

---

## 3. Alternative considerate

### 3.1 Alternativa scartata: Event Sourcing pieno (CQRS-like)

Stato derivato interamente da uno stream di eventi appended in Postgres. Tick = command handler che produce eventi; stato corrente = projection ricostruita.

**Pro**: audit nativo, time-travel perfetto, replay arbitrario, pattern adatto a sistemi maturi con audit critico.

**Contro**: complessità di implementazione (event store, projections, idempotenza, consistency), footprint storage in crescita lineare, performance per tick ridotta (write event + apply projection per ogni cambio), non idiomatico in Elixir puro (richiede librerie come Commanded).

### 3.2 Valutazione pesata (per ricostruibilità della decisione)

Pesatura sui criteri rilevanti per il **profilo del progetto** (prototipo su 1 GB VPS + lifetime pluriennale + pubblico esperto + audit critico per Blocco 13):

| Criterio | Peso | Active Record | Event Sourcing |
|---|---|---|---|
| Semplicità di sviluppo iniziale | 3 | 9/10 | 4/10 |
| Performance per tick | 2 | 8/10 | 5/10 |
| Footprint memoria (1 GB VPS) | 2 | 9/10 | 6/10 |
| Footprint storage DB | 2 | 8/10 | 4/10 |
| Audit log nativo (Blocco 13) | 3 | 5/10 (alzato a ~9/10 col caveat 1) | 10/10 |
| Time-travel debugging / replay | 2 | 3/10 | 10/10 |
| Testabilità | 3 | 8/10 (alzato a 9/10 col caveat 2) | 8/10 |
| Resilience / fault tolerance | 2 | 8/10 | 8/10 |
| Debugging / observability | 3 | 7/10 | 8/10 |
| Path migrazione NIF Rust | 2 | 9/10 | 7/10 |
| Scalabilità multi-nodo | 2 | 7/10 | 8/10 |
| Aderenza pattern Elixir/OTP | 2 | 10/10 | 6/10 |
| Maturità ecosystem in Elixir | 2 | 10/10 | 7/10 |

**Punteggio pesato base**: AR = 7.7/10, ES = 6.7/10
**Con caveat 1+2 applicati ad AR**: AR ≈ 8.3/10

### 3.3 Path di evoluzione futura

Se in futuro emergesse un'esigenza forte (replay scientifico, dispute formali su griefing, analisi retrospettiva di lunga campagna), una **migrazione parziale verso event sourcing per i sotto-sistemi critici** (es. solo elementi mobili e interventi giocatore) è fattibile senza riscrivere il core. La disciplina pure-functional di partenza è il punto di forza che abilita questo path.

---

## 4. Architettura process-level (Elixir)

```
Application Supervisor
├── WorldClock (GenServer, batte tick ogni 5 min wall-clock)
├── Biotope.Supervisor (DynamicSupervisor)
│   └── Biotope.Server × N (uno per biotopo attivo)
│       state: phases, lignaggi (con delta_genome), metabolites, signals, phages
│       handle_tick: tick(state) → {new_state, events}; persist + broadcast post-calcolo
├── Migration.Coordinator (orchestra step inter-biotopo dopo ogni tick)
├── Player.Supervisor (DynamicSupervisor)
│   └── Player.Session × M
├── Phoenix.PubSub (broadcast eventi al client + coordinamento Biotope ↔ Migration)
├── Persistence.Snapshot (Oban worker, ogni 10 tick: serializza state)
├── Persistence.AuditLog (insert su tabella eventi rilevanti, transazionale)
└── Persistence.Recovery (al boot: ricostruisce stato dall'ultimo snapshot)
```

### 4.1 Forma del tick

```elixir
# Pure function — il cuore della disciplina
def tick(%BiotopeState{} = state) do
  new_state =
    state
    |> step_metabolism()
    |> step_expression()
    |> step_cell_events()    # divisione, lisi, mutazione → nuovi lignaggi
    |> step_hgt()
    |> step_environment()    # decadimento, dilution
    |> step_pruning()

  events = derive_events(state, new_state)
  {new_state, events}
end

# GenServer — orchestrazione side-effects
def handle_info(:tick, state) do
  {new_state, events} = Tick.tick(state)
  AuditLog.persist(events)
  PubSub.broadcast(Topic.biotope(state.id), {:tick, new_state, events})
  Migration.notify_neighbors(new_state)
  Snapshot.maybe_persist(new_state)
  {:noreply, new_state}
end
```

---

## 5. Roadmap implementativa

12 fasi incrementali. Ogni fase lascia un sistema funzionante e dimostrabile, anche se incompleto. L'ordine massimizza il **feedback evolutivo precoce**: già in Fase 4 si vedono i primi fenomeni emergenti.

| Fase | Deliverable | Criterio di successo | Blocchi DESIGN coperti |
|---|---|---|---|
| **0. Bootstrap** | Phoenix scaffold + Postgres + Ecto + CI base + LiveDashboard | `mix phx.server` parte; LV "Hello Arkea" servita; pipeline CI verde | 14 (stack) |
| **1. Modello dati core** | Struct: Codone, Dominio, Gene, Genoma, Lignaggio, Fase, Biotopo + schema Ecto base | Property tests che validano invarianti delle struct | 4, 7 |
| **2. Tick engine minimale** | `WorldClock` + `Biotope.Server` con tick "vuoto" (solo crescita/decadimento aggregato) | Un biotopo, popolazione cresce ed equilibrium con dilution | 11 |
| **3. Sistema generativo dei domini** | Parser codoni → domini → fenotipo emergente | Test: dato un genoma noto, calcolo deterministico dei fenotipi | 7 |
| **4. Mutazione + selezione + lignaggi** | Mutator (puntiformi, indel, dup, inv, traslocazioni), fission lignaggi, delta encoding, pruning, fitness | **Primo test evolutivo**: da un seed, in 100 tick emerge varietà polimorfica visibile | 4, 5 (parziale), 7 |
| **5. Metabolismo + regolazione** | I 13 metaboliti, reazioni Michaelis-Menten, σ-factor + riboswitch, bilancio ATP | Test: ceppi diversi vincono in biotopi con profili metabolici diversi | 6, 7 (regolazione), 8 (parziale) |
| **6. HGT + elementi mobili** | Plasmidi, profagi, coniugazione gene-encoded, lisi fagica, costo plasmide | Test: introduzione di un plasmide → diffusione misurabile via HGT | 5, 8 |
| **7. Quorum sensing & signaling** | Synthase + recettori 4D, programma QS, density-dipendenza | Test: programma OFF a basso N, ON a alto N | 9 |
| **8. Migrazione + topologia di network** | Network di biotopi, archi pesati, biotope_compatibility, fasi (Blocco 12) | Test: 5 biotopi connessi, lignaggi diffondono coerentemente; preferenze di fase emergenti | 3, 5, 10, 12 |
| **9. UI: LiveView + PixiJS Hook** | Vista biotopo 2D (rendering procedurale), dashboard, log eventi, controlli intervento | Anna del caso d'uso può accedere via browser e vedere il proprio biotopo | 12, 14 |
| **10. Persistenza completa** | Snapshot ogni 10 tick + audit log + recovery | Crash deliberato → restart → stato preservato fino al WAL recente | 11, 13, 14 |
| **11. Caso d'uso "Cronache" abbreviato** | Riproduzione dello stress test su scala prototipo | Da seed → resistenza, biofilm, profago, colonizzazione visibili in qualche ora reale | tutti |

### 5.1 Dipendenze e parallelismo

- Fasi 0–4 sono **strettamente sequenziali** (ogni fase dipende dalla precedente)
- Fasi 5, 6, 7 possono procedere parzialmente in parallelo dopo la 4
- Fasi 9 e 10 possono iniziare dopo la 4, in parallelo con 5–8
- Fase 8 dipende da 5 (per cinetiche metaboliche cross-biotope) e 12 (fasi)
- Fase 11 chiude tutto

### 5.2 Stima di complessità relativa

| Fase | Complessità relativa |
|---|---|
| 0 | Bassa (boilerplate) |
| 1, 2 | Media (modellazione attenta) |
| 3, 4 | **Alta** (sistema generativo è il cuore creativo) |
| 5 | **Alta** (cinetica + regolazione + bilanci) |
| 6, 7 | Media-alta |
| 8 | Media |
| 9 | Media (PixiJS + LV Hook) |
| 10 | Media |
| 11 | Bassa-media (orchestration di pezzi già esistenti) |

---

## 6. Disciplina di sviluppo

Non-negoziabili dall'inizio del progetto. Servono a tenere il design coerente con l'implementazione e ad aprire path di evoluzione futura senza debiti tecnici.

### 6.1 Pure-functional tick

Il tick e tutti i suoi sub-step (`step_metabolism`, `step_expression`, …) sono **funzioni pure**: input = `state`, output = `new_state` o `{new_state, events}`. Niente I/O, niente messaggi, niente accesso al DB dalle funzioni di tick. I side-effect (persistenza, broadcast, notifiche) avvengono nel GenServer **dopo** il calcolo del tick.

### 6.2 Property-based testing per invarianti evolutivi

ExUnit + StreamData per verificare invarianti che devono valere per ogni input:
- Conservazione della massa (la somma di metaboliti consumati = somma di prodotti + waste, modulo dilution)
- Monotonicità dell'albero filogenetico (un parent_id punta sempre a un lignaggio più vecchio)
- Determinismo del tick (stesso state + stesso seed RNG → stesso new_state)
- Nessuna fitness < 0 per nessun lignaggio
- Pruning corretto (dopo prune, nessun lignaggio con N < soglia nel biotopo, ma tutti ancora nell'albero storico)

### 6.3 Audit log dal Fase 4

Non aspettare la Fase 10 per scrivere audit. Già dalla Fase 4 (mutazione + lignaggi), il tick produce eventi tipizzati che vengono persistiti in `audit_log`. Questo:
- Forza la disciplina degli eventi tipizzati dall'inizio (più facile estendere che retrofit)
- Fornisce immediato debugging su evoluzioni complesse
- Soddisfa Blocco 13 senza essere un'aggiunta tardiva

### 6.4 Telemetria built-in

`:telemetry` instrumentato fin dalla Fase 2: tick duration, lineage count per biotope, eventi notevoli per minuto. LiveDashboard configurato per visualizzazione interna. Quando andiamo in produzione, scattiamo il Prometheus exporter.

### 6.5 Nessuna ottimizzazione prematura

Profilo prima, ottimizza dopo. Lo VPS è 1 GB / 1 CPU per il prototipo: probabilmente non vedremo mai i bottleneck a quella scala. NIF Rust, Mnesia, ETS sharing rimangono escape hatch documentati ma **non implementati** finché un benchmark reale non li giustifichi.

### 6.6 Genoma serializzato come Erlang term

Default: `:erlang.term_to_binary/1` con compressione per dump in DB (campo `bytea`). JSONB opzionale per analytics post-hoc. Niente formati custom finché non servono.

---

## 7. Prossimi passi concreti — Fase 0

Una volta confermato questo piano, la Fase 0 è una checklist meccanica:

1. `mix phx.new arkea --no-mailer --no-gettext --binary-id` (Phoenix scaffold)
2. Configurare Postgres locale + production (sul VPS DigitalOcean)
3. Aggiungere dipendenze: `oban`, `stream_data`, `dialyxir`, `credo`
4. Configurare GitHub Actions: `mix test`, `mix dialyzer`, `mix credo`
5. Configurare LiveDashboard
6. Primo deploy sul VPS (mix release + systemd + Caddy)
7. CI verde + LiveView "Hello Arkea" raggiungibile sul dominio

Output atteso: ~3–5 giorni di lavoro, ambiente pronto per la Fase 1.

---

## 8. Sintesi

**Architettura**: Active Record (BEAM-canonical) + audit log strutturato + disciplina pure-functional del tick.
**Rationale**: 80% dei benefici di Event Sourcing al 30% del costo, con path di evoluzione aperto.
**Roadmap**: 12 fasi incrementali, dimostrabili una a una, con primo feedback evolutivo in Fase 4.
**Disciplina**: pure functions, property tests, audit dal giorno 1, niente ottimizzazione prematura.
**Prossimo step**: Fase 0 — bootstrap del progetto Phoenix.
