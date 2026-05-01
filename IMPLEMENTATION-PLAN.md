> 🇮🇹 Italiano (questa pagina) · [🇬🇧 English](IMPLEMENTATION-PLAN.en.md)

# Arkea — Piano di implementazione (alto livello)

**Riferimenti**: [DESIGN.md](DESIGN.md), [DESIGN_STRESS-TEST.md](DESIGN_STRESS-TEST.md)
**Data**: 2026-04-26
**Stato**: Fase 0 ✅ · Fase 1 ✅ · Fase 2 ✅ · Fase 3 ✅ · Fase 4 ✅ · Fase 5 ✅ · Fase 6 ✅ · (vedi §1bis).

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

## 1bis. Stato dell'implementazione

> Aggiornato: 2026-04-27. EN translation di questa sezione: ⏳ pending sync (`bilingual-docs-maintainer`).

### Fase 0 — Bootstrap ✅ completata (commit `86a3ef2`)

- ✅ Phoenix 1.8.5 scaffold in `arkea/` (`--no-mailer --no-gettext --binary-id`)
- ✅ `.tool-versions` locale: Erlang 28.1.1 + Elixir 1.19.3-otp-28
- ✅ Dipendenze del piano: Oban 2.18, StreamData 1.1, Dialyxir 1.4, Credo 1.7
- ✅ Aggiunta `typed_struct 0.3` (per i type-safe struct di Fase 1)
- ✅ `.credo.exs` (default config) + `priv/plts/.gitkeep` (PLT path)
- ✅ DB di sviluppo `arkea_dev` (Postgres 14 locale)
- ✅ `config/dev.exs` legge `PORT` da env (default 4000)
- ✅ `mix format`/`credo --strict`/`test`/`compile --warnings-as-errors`: tutto verde
- ✅ Server verificato: `PORT=4010 mix phx.server` → HTTP 200, title "Arkea · Phoenix Framework"
- ✅ GitHub Actions CI (`.github/workflows/ci.yml`): format/credo/test/dialyzer + cache
- ✅ `.gitignore` top-level per tooling esterno

### Fase 1 — Modello dati core ✅ completata (commit `142b4aa`)

**Decisioni di design** (proposta `elixir-otp-architect`, decise in conversazione 2026-04-26):

- Naming: inglese nel codice; namespace gerarchico `Arkea.Genome.*` + `Arkea.Ecology.*` + `Arkea.Persistence.*`
- Struct: TypedStruct (compile-time `@type t()` + Dialyzer-friendly)
- Codone = intero `0..19`; alfabeto = atom analoghi 20 amminoacidi (`:ala`, `:arg`, …, `:val`)
- **Pesi codoni**: log-normal con seed fisso (frozen in `Codon` per riproducibilità)
- 11 tipi di dominio come enum atom in `Domain.Type`
- Mapping `from_type_tag/1`: `rem(sum_of_3_codons, 11)` (uniforme su input random)
- Delta del lignaggio = lista tipata di 5 sub-struct di mutazione
- Soglia consolidamento `clade_ref_id`: 50 mutazioni (Fase 4)
- `genome: Genome.t() | nil` nel Lineage (per delta-encoding di Fase 4 senza breaking change)
- `phase_name` come atom; `lineage_ids` in Phase come `MapSet`
- Top-level `Arkea.Genome` = modulo+struct (pattern di `MapSet`, `Range`, `Date`)
- Helper `Arkea.UUID` come single point of indirection per UUID v4 (delegato a `Ecto.UUID`)

**Semplificazioni esplicite per Fase 1** (riprese in Fase 3):

- Gene parser: nessun promoter/regulatory block (nil), parameter_codons fisso a 20 codoni → ogni dominio = 23 codoni, gene = multipli di 23
- Domain.params: solo `%{raw_sum: float}` (Phase 3 raffinerà con chiavi tipo-specifiche)
- Mutation modules: solo struct + `valid?/1`; `apply/2` arriva in Fase 4

#### Modello dati core in-memory (struct + funzioni pure)

| Modulo | File | Stato |
|---|---|---|
| `Arkea.UUID` | `lib/arkea/uuid.ex` | ✅ |
| `Arkea.Genome.Codon` | `lib/arkea/genome/codon.ex` | ✅ |
| `Arkea.Genome.Domain.Type` | `lib/arkea/genome/domain/type.ex` | ✅ |
| `Arkea.Genome.Domain` | `lib/arkea/genome/domain.ex` | ✅ |
| `Arkea.Genome.Gene` | `lib/arkea/genome/gene.ex` | ✅ |
| `Arkea.Genome` | `lib/arkea/genome.ex` | ✅ |
| `Arkea.Genome.Mutation` (union) | `lib/arkea/genome/mutation.ex` | ✅ |
| `Arkea.Genome.Mutation.Substitution` | `lib/arkea/genome/mutation/substitution.ex` | ✅ |
| `Arkea.Genome.Mutation.Indel` | `lib/arkea/genome/mutation/indel.ex` | ✅ |
| `Arkea.Genome.Mutation.Duplication` | `lib/arkea/genome/mutation/duplication.ex` | ✅ |
| `Arkea.Genome.Mutation.Inversion` | `lib/arkea/genome/mutation/inversion.ex` | ✅ |
| `Arkea.Genome.Mutation.Translocation` | `lib/arkea/genome/mutation/translocation.ex` | ✅ |
| `Arkea.Ecology.Lineage` | `lib/arkea/ecology/lineage.ex` | ✅ |
| `Arkea.Ecology.Phase` | `lib/arkea/ecology/phase.ex` | ✅ |
| `Arkea.Ecology.Biotope` | `lib/arkea/ecology/biotope.ex` | ✅ (8 archetipi + `default_phases/1`) |

#### Schema Ecto base (Phase 1 minimale; CRUD wrapper rinviati a Fase 10)

Namespace `Arkea.Persistence.*` per non confondere con le struct in-memory `Arkea.Ecology.*`. Implementati da `ecto-postgres-modeler` (2026-04-27):

| Schema | File | Migration |
|---|---|---|
| `Arkea.Persistence.Player` | `lib/arkea/persistence/player.ex` | `20260427072227_create_players.exs` |
| `Arkea.Persistence.Biotope` | `lib/arkea/persistence/biotope.ex` | `20260427072317_create_biotopes.exs` |
| `Arkea.Persistence.Phase` | `lib/arkea/persistence/phase.ex` | `20260427072318_create_phases.exs` |
| `Arkea.Persistence.Lineage` | `lib/arkea/persistence/lineage.ex` | `20260427072319_create_lineages.exs` |
| `Arkea.Persistence.AuditLog` | `lib/arkea/persistence/audit_log.ex` | `20260427072320_create_audit_log.exs` |
| `Arkea.Persistence.MobileElement` | `lib/arkea/persistence/mobile_element.ex` | `20260427072321_create_mobile_elements.exs` |

Decisioni della persistenza:
- `binary_id` PK ovunque (coerente con `--binary-id` di Phoenix)
- Genome / delta_genome / mobile element genes serializzati come `bytea` via `:erlang.term_to_binary/1`
- `abundance_by_phase` come jsonb (chiavi atom serializzate come stringhe; conversione lato Elixir)
- FK strategy: `:delete_all` per child senza significato senza parent (phase senza biotope, lineage senza biotope); `:nilify_all` per parent_id di lineage e owner_player_id di biotope (un wild biotope sopravvive al rimosso owner)
- Audit log con `event_type`, `actor_player_id`, `target_biotope_id`, `target_lineage_id`, `payload` jsonb, `occurred_at_tick` (Blocco 13 origin tracking)
- Mobile elements con `origin_lineage_id` + `origin_biotope_id` per anti-griefing detection
- Esclusioni esplicite (rinviate a Fase 9–10): `phylogenetic_history`, `interventions_log`, `snapshots`, TimescaleDB, citext

#### Test suite

- **Module `Arkea.Generators`** in `test/support/generators.ex` — 25 generatori StreamData (codon, codon_list, type_tag, parameter_codons, domain, gene, genome, lineage, lineage_pair, abundances, growth_deltas, phase, biotope, 5 mutation generators, ecc.)
- **Property tests** in `test/arkea/genome/`, `test/arkea/ecology/` — 91 properties × 100–200 runs ciascuna
- **Plain unit tests** in `test/arkea/` — 76 unit per il dominio in-memory + 50 per la persistenza
- **Persistence smoke tests** in `test/arkea/persistence/` — verifica round-trip insert/get per ognuno dei 6 schema, vincoli base, unique constraint
- **Suite finale**: `mix test` → **91 properties, 126 tests, 0 failures** (1 test fix puntuale: `phase_test.exs` adottava una chiave errata per leggere errors_on di unique_constraint composito)

Invarianti coperti (§6.2):
- ✅ Conservation (`gene_count == length(all_genes)`, `add_plasmid` mass conservation, `integrate_prophage` mass conservation)
- ✅ Tree monotonicity (child_tick > parent_tick, raise su violazione)
- ✅ Lineage abundance non-negative (clamp a 0 dopo qualsiasi `apply_growth/2`)
- ✅ Phase dilution monotonica (∀ pool: conc dopo ≤ conc prima)
- ✅ Genoma well-formed (round-trip `from_domains`/`from_codons`)
- ✅ MapSet lineage_ids consistency (add/remove round-trip, deduplicazione)
- ✅ Domain type determinism + uniformity (1000 sample, tutti 11 tipi presenti)
- ✅ valid?/validate agreement su tutti i moduli
- ✅ Biotope archetype → zone consistente, phase count 2..3
- ⏳ Determinism del tick (Fase 4: tick engine)
- ⏳ Pruning correctness (Fase 4)
- ⏳ Phase distribution sums to 1 (Fase 5)

#### Cross-check qualità (agent reviews)

- ✅ **Biological realism review** (`biological-realism-reviewer`, 2026-04-27): pronto per sign-off. 3 docstring tightened post-review:
  1. `Lineage.abundance_by_phase` → "abundance index / cell-equivalent count" (non "absolute count of cells", per non implicare densità batteriche reali 6–9 ordini di grandezza superiori al cap simulato)
  2. `Genome.plasmids/prophages` → TODO espliciti per Fase 6: copy_number, inc_group, lysogenic state
  3. `Gene` Phase 1 simplifications → docstring del range codoni 23..207 chiarita

  Non emersi blocker; tutte le decisioni (alfabeto come aa-like, pesi log-normal, mapping uniform, fixed-length Phase 1) sono giustificate per pubblico esperto.
- ✅ **Design coherence review** (`design-coherence-reviewer`, 2026-04-30): nessuna violazione critica. Finding da ricordare:
  1. `audit_log` ha `occurred_at` (wall-clock) oltre a `occurred_at_tick` — campo intenzionale per query analytics, non documentato nel piano. Tabella append-only: nessun `timestamps/0` e nessun `inserted_at`.
  2. `acid_mine_drainage` è mappato a `:hydrothermal_zone` — semplificazione Fase 1; rivalutare topologia zone in Fase 8.
  3. Policy costruttori: costruttori "trusted" (input già validato) usano raise; costruttori "untrusted" (da input esterno) usano `{:ok, _} | {:error, _}` — da documentare come policy esplicita.
  4. `clade_ref_id` soglia 50 mutazioni non è ancora ancorata come costante in DESIGN.md Blocco 4 — da aggiungere prima di Fase 4.
  5. `:atp` e `:nadh` nei generatori di test sostituiti con `:co2` e `:h2s` (corrispondenti ai 13 metaboliti canonici di Blocco 6; ATP è valuta interna esclusa dall'inventario ambientale).

**Suite verificata** (2026-04-27, post-Ecto schemas + post-bio review):
- `mix format --check-formatted`: ✅ pulito
- `mix credo --strict`: ✅ 291 mods/funs, 0 issue
- `mix compile --warnings-as-errors`: ✅
- `mix ecto.migrate`: ✅ 6 migrazioni applicate
- `mix test`: ✅ **91 properties, 126 tests, 0 failures**

**Step rimanenti per chiudere Fase 1**:

1. ✅ Cross-check coerenza design via agent `design-coherence-reviewer`
2. ⏳ Commit + push Fase 1

**Open issues / da rivedere prima di consolidare**:

- I 6 quesiti aperti del design dell'`elixir-otp-architect` sono stati tutti decisi in conversazione (Q1–Q6), ma non sono ancora documentati formalmente in DESIGN.md. Valutare se aggiungere una nota al DESIGN o lasciarli solo in IMPLEMENTATION-PLAN.
- Il PLT di Dialyzer non è stato ancora generato localmente (rinviato; CI lo costruisce).
- Sync EN della §1bis (`bilingual-docs-maintainer`) rinviato — la sezione cresce velocemente in fase implementativa, conviene fare un singolo sync al completamento di un blocco stabile (es. fine Fase 3).

### Fase 2 — Tick engine minimale ✅ completata (commit `TBD`)

**Decisioni di design** (`elixir-otp-architect`, 2026-04-30):

- `growth_delta_by_lineage` vive su `BiotopeState` come `%{lineage_id => %{phase_name => integer()}}`, non su `Lineage` — i delta non sono proprietà genetiche ma parametri di simulazione calcolati da `step_expression` (Fase 5)
- `BiotopeState` usa lista per i lineage (lookup con `Enum.find`); Fase 4 introduce mappa per performance quando serve
- `WorldClock` configurabile via `config :arkea, :tick_interval_ms` (test.exs: 600_000 ms per evitare timer spurii)
- `Biotope.Server` registrato su `Arkea.Sim.Registry` con chiave `{:biotope, id}`; nei test si usa `GenServer.start_link` con atom name per `async: true` senza conflitti
- `manual_tick/1` su `Biotope.Server` come entry point sincrono per i test (bypass PubSub path)

**Moduli creati** (`Arkea.Sim.*`):

| Modulo | File | Tipo |
|---|---|---|
| `Arkea.Sim.BiotopeState` | `lib/arkea/sim/biotope_state.ex` | struct pura (TypedStruct) |
| `Arkea.Sim.Tick` | `lib/arkea/sim/tick.ex` | funzione pura `tick/1` + 6 sub-step |
| `Arkea.Sim.WorldClock` | `lib/arkea/sim/world_clock.ex` | GenServer (tick ogni 5 min) |
| `Arkea.Sim.Biotope.Supervisor` | `lib/arkea/sim/biotope/supervisor.ex` | DynamicSupervisor |
| `Arkea.Sim.Biotope.Server` | `lib/arkea/sim/biotope/server.ex` | GenServer (stato per biotopo) |

**Test suite** (nuovi):

- `test/arkea/sim/tick_test.exs` — 6 property tests + 7 unit test (non-negativity, dilution monotonicity, determinism, equilibrium)
- `test/arkea/sim/biotope_server_test.exs` — 8 integration test

**Suite finale**: `mix test` → **97 properties, 141 tests, 0 failures**

### Fase 3 — Sistema generativo dei domini ✅ completata (commit `TBD`)

**Decisioni di design** (`elixir-otp-architect`, 2026-04-30):

- `Domain.compute_params/1` ora fa dispatch sul tipo e aggiunge chiavi tipo-specifiche (`:km`, `:kcat`, `:reaction_class`, `:tag_class`, ecc.) mantenendo `:raw_sum` per tutti i tipi
- Normalizzazione lineare `min(raw_sum / 500.0, 1.0)`: preserva proporzionalità genotipo→fenotipo necessaria per selezione graduale; `tanh` scartato per distorsione non-lineare
- `Arkea.Genome.all_domains/1` aggiunto per traversare chromosome + plasmids + prophages
- `Arkea.Sim.Phenotype.from_genome/1`: unica passata su tutti i domini → 7 campi fenotipici aggregati
- Modello lineare Phase 3: `delta = round(base_growth_rate * 100) - round(energy_cost * 10)`, clamp `-100..500`; Michaelis-Menten rinviato a Fase 5
- Lineage con `genome: nil` (delta-encoding Fase 4+): `step_expression` preserva il delta preesistente senza sovrascrivere

**Moduli modificati/creati**:

| Modulo | File | Cambiamento |
|---|---|---|
| `Arkea.Genome.Domain` | `lib/arkea/genome/domain.ex` | `compute_params/1` type-dispatch; `valid?/1`/`validate/1` aggiornati per chiavi tipo-specifiche |
| `Arkea.Genome` | `lib/arkea/genome.ex` | `all_domains/1` aggiunto |
| `Arkea.Sim.Phenotype` | `lib/arkea/sim/phenotype.ex` | nuovo modulo puro |
| `Arkea.Sim.Tick` | `lib/arkea/sim/tick.ex` | `step_expression/1` implementato |

**Suite finale**: `mix test` → **115 properties, 156 tests, 0 failures**

### Fase 4 — Mutazione + selezione + lignaggi ✅ completata (commit `TBD`)

**Decisioni di design** (`elixir-otp-architect`, 2026-04-30):

- `Mutation.Applicator.apply/2` opera a **granularità di dominio** (23 codoni) per preservare l'invariante Phase 1 grammar: tutte le mutazioni generano geni con lunghezza multiplo di 23; indel inserisce/elimina esattamente 23 codoni; translocation sposta esattamente 23 codoni
- `Mutator.generate/2` usa `:rand.uniform_s/2` (API stateless, pura); seed initializzato da `init_seed(biotope_id)` via `:erlang.phash2/1` + algoritmo `:exsss`
- Pesi mutazione: substitution 70%, indel 15%, dup 8%, inv 5%, transloc 2% (da DESIGN.md Blocco 5)
- `mutation_probability = clamp(µ × abundance / 50.0, 0.0, 0.95)` con `µ = 0.01 × (1 - repair_efficiency)`
- `step_cell_events` esteso: spawn_mutants genera al massimo 1 figlio per lineage per tick; conservazione abbondanza (parent - 1 per ogni child)
- `step_pruning` implementato: (1) rimuove lineage con abundance 0, (2) cap a 100 (configurabile via `Application.get_env(:arkea, :lineage_cap, 100)`)
- `derive_events` emette `:lineage_born` e `:lineage_extinct`
- Gene mutato mantiene l'id originale (identità stabile attraverso mutazioni)

**Moduli creati/modificati**:

| Modulo | File | Cambiamento |
|---|---|---|
| `Arkea.Genome.Mutation.Applicator` | `lib/arkea/genome/mutation/applicator.ex` | nuovo — `apply/2` per tutti e 5 i tipi |
| `Arkea.Sim.Mutator` | `lib/arkea/sim/mutator.ex` | nuovo — generatore stocastico puro |
| `Arkea.Sim.Tick` | `lib/arkea/sim/tick.ex` | `step_cell_events` + `step_pruning` + `derive_events` implementati |
| `Arkea.Sim.BiotopeState` | `lib/arkea/sim/biotope_state.ex` | `new/3` inizializza `rng_seed` via `Mutator.init_seed/1` |

**Test suite** (nuovi):
- `test/arkea/genome/mutation_applicator_test.exs` — applicazione corretta per tutti e 5 i tipi
- `test/arkea/sim/mutator_test.exs` — property tests su valid?, pesi, probability formula
- `test/arkea/sim/evolution_test.exs` — **test evolutivo principale**: 100 tick → ≥3 lignaggi + divergenza fenotipica misurabile

**Suite finale**: `mix test` → **117 properties, 178 tests, 0 failures**

### Fase 5 — Metabolismo + regolazione ✅ completata (commit `TBD`)

**Decisioni di design** (`elixir-otp-architect`, 2026-04-30):

- `Arkea.Sim.Metabolism`: catalogo 13 metaboliti canonici (atom 0..12 → `:glucose`..`:po4`); Michaelis-Menten puro `kcat × [S] / (Km + [S])`; `@atp_coefficients` biologicamente ordinati (glucosio 2.0, acetato 1.0, lattato 0.5, ferro 0.3, accettori/prodotti 0.0) — coefficienti approssimati, documentati come tali
- Conversione `substrate_affinities` da integer a atom canonici in `Phenotype.from_genome/1` (non nel calcolo cinetico) — `Metabolism` rimane ignaro del genoma
- σ-factor Phase 5 semplificato: `sigma = 0.5 + dna_binding_affinity` come moltiplicatore scalare; σ-factor completo (binding sites multipli) rinviato a Fase 7
- `step_expression` v5: `delta = round(sigma × (atp_yield - energy_cost × 5.0))`, clamp `-200..500`
- `step_environment` esteso: ora chiama `Phase.dilute/1` su ogni fase (diluisce metabolite_pool + signal_pool) e applica `metabolite_inflow` (chemostato)
- Convergenza discreta: la coppia (popolazione, pool metabolici) forma un sistema di ODE discrete che vicino all'equilibrio può esibire limit-cycle oscillations — il test di convergenza verifica bounded non-negativity invece di fissato-punto esatto
- Divergenza genotipica (non fenotipica) come criterio del test evolutivo: mutazioni neutrali creano identità di lignaggio senza variazione fenotipica visibile — biologicamente corretto

**Moduli creati/modificati**:

| Modulo | File | Cambiamento |
|---|---|---|
| `Arkea.Sim.Metabolism` | `lib/arkea/sim/metabolism.ex` | nuovo — catalogo, MM, uptake, ATP yield |
| `Arkea.Sim.Phenotype` | `lib/arkea/sim/phenotype.ex` | `dna_binding_affinity`; chiavi `substrate_affinities` → atom |
| `Arkea.Sim.Tick` | `lib/arkea/sim/tick.ex` | `step_metabolism` implementato; `step_expression` v5; `step_environment` con `Phase.dilute` + inflow |
| `Arkea.Sim.BiotopeState` | `lib/arkea/sim/biotope_state.ex` | `atp_yield_by_lineage`, `metabolite_inflow` |
| `Arkea.Sim.SeedScenario` | `lib/arkea/sim/seed_scenario.ex` | metaboliti iniziali + inflow |

**Suite finale**: `mix test` → **121 properties, 194 tests, 0 failures**

### Fase 6 — HGT + elementi mobili ✅ completata (commit `7491a3f`)

**Decisioni di design** (`elixir-otp-architect`, 2026-05-01):

- Proxy per coniugazione gene-encoded (Phase 6 semplificazione): un plasmide è coniugativo se e solo se contiene almeno 1 dominio `:transmembrane_anchor` — proxy per `pili_like` di DESIGN.md Blocco 5; la verifica full domain-composition (`pili_like + relaxase_like + oriT_like`) è rinviata a Phase 8
- Formula coniugazione: `p_conj = clamp(strength × 0.005 × N_donor × N_recip / max(N_total², 1), 0.0, 0.3)`, dove `strength` = count domini TM del plasmide (mass-action con moderazione biologica)
- Creazione transconjugant: `Lineage.new_child(recipient, Genome.add_plasmid(recipient.genome, plasmid), %{phase_name => 1}, tick + 1)` — conservazione abbondanza (-1 dal ricevente originale)
- Costo plasmide: `plasmid_burden = plasmid_gene_count × 0.3 ATP/tick` sottratto da `net_adjusted` in `compute_growth_deltas_v5` prima del round; modella il burden trascrizionale + replicazione di Blocco 5 come scalar additive
- Induzione profago: `stress_factor = max(0, 1 - atp_yield / max(energy_cost × 5.0, 0.1))`, `p_induction = clamp(0.03 × stress_factor, 0, 0.1)` per cassetta; burst litico = perdita del 50% dell'abbondanza — stresso = 0 ATP → induction max, equivalente SOS qualitativo
- Skip lignaggi `genome: nil` per HGT (sia come donatori che riceventi) — nessun genome completo da trasferire
- Cap HGT per tick: `max(div(length(lineages), 4), 1)` nuovi figli per call a `HGT.step/4` — previene esplosione combinatoria del numero di lignaggi

**Moduli creati/modificati**:

| Modulo | File | Cambiamento |
|---|---|---|
| `Arkea.Sim.HGT` | `lib/arkea/sim/hgt.ex` | nuovo — `conjugative?/1`, `conjugation_strength/1`, `step/4`, `induction_step/4` |
| `Arkea.Sim.Tick` | `lib/arkea/sim/tick.ex` | `step_hgt/1` implementato (era stub); `compute_growth_deltas_v5/4` con genome + plasmid burden |

**Test suite** (nuovi):
- `test/arkea/sim/hgt_test.exs` — 5 test: diffusione plasmide coniugativo (2000 trial), non-diffusione plasmide non-coniugativo, burden riduce delta di crescita, property `conjugative? ↔ strength > 0`, induzione profago riduce abbondanza

**Note architetturali**:
- Il `type_tag` corretto per `:transmembrane_anchor` è `[0, 0, 2]` (indice 2 in `Domain.Type.all()`), non `[0, 0, 6]` come indicato nel brief iniziale — corretto dall'agente in fase di implementazione
- `step_hgt/1` mantiene la disciplina pure-functional: legge e aggiorna `state.rng_seed` via `get_rng/1`, niente I/O
- `credo:disable-for-this-file Credo.Check.Refactor.Nesting` nel test HGT: necessario per il pattern `gen all do ... end` di StreamData (nesting canonico della libreria)

**Suite finale**: `mix test` → **122 properties, 198 tests, 0 failures**

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

> Per lo stato di esecuzione dettagliato delle fasi, vedi §1bis. La tabella seguente è la pianificazione canonica.

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
