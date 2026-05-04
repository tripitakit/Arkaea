> 🇮🇹 Italiano (questa pagina) · [🇬🇧 English](UI-OPTIMIZATION-PLAN.en.md)

# Ottimizzazione UI Arkea — Piano fasato per UX, usabilità e indagine scientifica

## Context

Arkea è oggi una simulazione tecnicamente solida ma con un'interfaccia che **rivela meno della metà di ciò che la simulazione calcola**. Due audit interni hanno mappato il gap:

1. **Audit UI**: mancano time-series (popolazioni, metaboliti, segnali QS), phylogeny dei lineage, viste comparative (seed/biotopi/replicati), export di dati o snapshot, navigazione consistente (link Audit/Seed-Lab assenti in alcune nav), keyboard shortcuts, glossario in-app, contenuto del pannello Docs.

2. **Audit data pipeline**: sono solo in-memory `phase.metabolite_pool`, `phase.signal_pool`, `lineage.biomass`, `lineage.dna_damage`, `atp_yield_by_lineage`, `uptake_by_lineage`. Sono **silenziosi** (niente eventi né persistenza): induzione profago, infezioni fagiche, R-M digestion, lisi da biomass-deficit, conjugazione che non genera nuovo lineage. Lo schema `audit_log` definisce tipi `:mass_lysis`, `:mutation_notable`, `:community_provisioned`, `:mobile_element_release`, `:colonization` — ma il sim non li scrive mai.

Il pubblico target sono biologi/microbiologi professionisti: oggi il prodotto fornisce un seed-builder + scena live, ma non un **banco di indagine** dove formulare ipotesi, osservare traiettorie, confrontare repliche, tracciare provenienze, esportare risultati.

Decisioni dell'utente (plan mode):
- **Persistenza in scope**: pieno verticale sim → DB → UI. Il piano emette gli eventi mancanti, snapshotta i time-series chiave, e poi costruisce le visualizzazioni sopra.
- **i18n / a11y fuori scope**: focus su densità informativa, navigazione, grafici, comparazione, export.

Esito atteso a piano completo: un microbiologo apre Arkea e può
- vedere traiettorie di abbondanza, fitness, metaboliti per centinaia di tick;
- navigare la genealogia dei lineage con i delta di mutazione sugli archi;
- ricostruire chi-ha-trasferito-cosa-a-chi via HGT (provenance Sankey);
- confrontare due seed o due biotopi gemelli affiancati;
- esportare snapshot biotope + audit log per analisi off-line;
- partire da preset di scenario ("estuario contestato") senza progettare seed da zero.

---

## Principi guida (vincolanti per ogni fase)

- **Sim core puro**: nessun I/O nei moduli `Arkea.Sim.*`. Persistence resta delegata al `Server` tramite event structs ritornati dal tick. I nuovi eventi seguono questo contratto.
- **Persistence in batch**: le scritture di time-series (es. abundance per lineage per tick) sono campionate (default ogni 5 tick) e batchate per evitare DB explosion. Adaptive sampling: alti rate → frequenza minore; pochi lineage → frequenza maggiore.
- **Reuse vista pure-funzionale**: le nuove visualizzazioni sono moduli puri in `Arkea.Views.*`, riusando il pattern già introdotto da `GenomeCanvas`, `BiotopeScene`, `ArkeonSchematic`.
- **SVG-only**: nessuna JS chart lib aggiuntiva. Si introduce un helper `Arkea.Views.Chart` con scale/axis/path utilities, riusabile da tutte le viste.
- **Test obbligatori**: per ogni nuova visualizzazione almeno 1 snapshot test; per ogni nuovo evento sim almeno 1 property test (conservation/monotonicity); per ogni nuova query almeno 1 test su dataset seed.
- **Coerenza navigazione**: tutte le live view condividono lo stesso `Shell.shell_nav` items list, derivato da una sola sorgente.
- **No regressioni**: `mix test` resta verde dopo ogni fase; il rendering del biotope viewport non regredisce >20%; hard cap su path nodes/series.

---

## Fase A — Fondamenta navigazione, help, shortcuts (P0)

**Obiettivo**: rendere la UI coerente prima di costruirvi sopra. Bassa difficoltà, alto compounding effect.

### Cambi chiave
- `lib/arkea_web/components/shell.ex` — `nav_items/1` unica che accetta `active`; tutte le live view la chiamano. Risolve le inconsistenze documentate.
- Nuovo `lib/arkea_web/components/help.ex` — `<.glossary_term term="kcat" />` con tooltip + link a panel laterale `/help#kcat` (sezioni di USER-MANUAL.md). Estendibile ai 30+ termini biologici.
- Nuovo `lib/arkea_web/live/help_live.ex` — render statico di USER-MANUAL.md (e poi DESIGN.md) con anchor; sostituisce il placeholder Docs della Dashboard.
- Keyboard shortcuts: hook JS minimale in `components/shortcuts.ex`:
  - `/` focus search globale; `g d/w/s/c/a` go-to view; `?` cheatsheet.
  - In SimLive: `j/k` lineage prev/next; `1..4` switch tab; `e` events; `i` interventions.
- Cross-linking: ogni audit row → biotope viewport; community row → blueprint del founder; lineage drawer → "audit per questo lineage".
- Search globale skeleton: `/search?q=...` (live view minima, popolata nelle fasi successive).

### File toccati
- Nuovi: `components/help.ex`, `components/shortcuts.ex`, `live/help_live.ex`, `live/search_live.ex`.
- Refactor: `components/shell.ex`; modificate tutte e 6 le live view per consumare la nav unificata.

### Verifica
- Tutte le 6 nav-bar mostrano gli stessi 5 link, `active` corretto. Snapshot test per ogni view.
- `?` apre cheatsheet su qualunque view.
- Click su row Audit naviga al biotope corrispondente.
- `/help` renderizza il manuale in-app, ancore funzionanti.

---

## Fase B — Persistence + event pipeline backfill (P0, bloccante)

**Obiettivo**: rendere la simulazione **observable**. Ogni meccanismo biologico significativo deve (a) emettere un evento o (b) lasciare una traccia time-series interrogabile. Senza questa fase, le successive C/D/E sono carta.

### Eventi emessi che oggi mancano
- **HGT silenti** in `lib/arkea/sim/hgt.ex`:
  - `:hgt_conjugation_attempt` (anche senza nuovo lineage; donor/recipient/payload)
  - `:hgt_transformation_event` (uptake da dna_pool)
  - `:hgt_transduction_event` (in phage_infection)
  - `:rm_digestion` (R-M check fallito)
  - `:plasmid_displaced` (incompatibilità inc_group)
- **Profago** in `sim/hgt/phage.ex` (Fase 12 BIO): `:prophage_induced`, `:phage_infection`, `:phage_decay`.
- **Lisi** in `sim/biomass.ex` o tick step lysis: `:cell_lysis` (per-lineage death count) e `:mass_lysis` quando >X% della popolazione di una fase muore in un tick.
- **Mutazioni**: arricchire `:lineage_born` con `mutation_summary` (gene_id, kind, fitness_delta) ricavato da `delta_genome`. Aggiungere `:mutation_notable` quando il fitness delta supera ±20% o tocca un dominio chiave.
- **Cross-feeding**: nuovo `:cross_feeding_observed` quando lineage A è netto produttore di metabolita X e lineage B coresidente è netto consumatore (rilevazione su finestra di N tick).
- **Error catastrophe**: `:error_catastrophe_death` (Fase 17 BIO).
- **Colonization**: `:colonization` quando un lineage migra in un nuovo biotope e si stabilizza (>K cellule per >M tick).

### Time-series snapshottate
- Nuovo modulo `lib/arkea/persistence/time_series.ex` + tabella `time_series_samples(biotope_id, tick, kind, scope_id, payload jsonb)`. Adaptive sampling con default:
  - `:abundance_per_lineage_per_phase` ogni 5 tick.
  - `:metabolite_pool_per_phase` ogni 5 tick (campionamento `phase.metabolite_pool`).
  - `:signal_pool_per_phase` ogni 5 tick.
  - `:phenotype_per_lineage` solo on-change (delta-encoded).
  - `:dna_damage_per_lineage`, `:biomass_per_lineage` ogni 10 tick.
- Sampling rate configurabile per biotope; cap totale `@samples_per_biotope_cap` (default 10⁵) con prune del più vecchio.

### Audit writer
- Estendere `lib/arkea/persistence/audit_writer.ex` per i nuovi tipi event. Batch insert in transazione, non bloccante per il tick.

### Snapshot biotope
- Estendere `Arkea.Persistence.BiotopeSnapshot` con `export/1` (state struct + lineages + phases + metaboliti + neighbor edges) come JSON. Riusato da export utente (Fase F), replay scientifico, diff.

### Property tests
- `time_series_test.exs`: somma delle abundance campionate ≈ abundance totale al tick di sampling.
- `audit_writer_test.exs`: tutti i nuovi eventi finiscono in `audit_log` con payload valido.
- `events_silence_test.exs` (StreamData): nessun branch sim che modifica popolazione resta silente.

### File critici
- Nuovi: `lib/arkea/persistence/time_series.ex`, `priv/repo/migrations/<ts>_create_time_series_samples.exs`, `lib/arkea/sim/event.ex` (canonical event struct).
- Modificati: `sim/tick.ex`, `sim/hgt.ex`, `sim/biomass.ex`, `persistence/audit_writer.ex`, `persistence/audit_log.ex` (estendere `@event_types`).

### Verifica
- Eseguendo 100 tick di un biotope diversificato: `audit_log` cresce con tutti i nuovi tipi presenti almeno una volta; `time_series_samples` cresce in modo controllato (~20–40 righe per 100 tick con sampling default).
- Replay: caricando snapshot e ri-eseguendo da seed deterministico, l'audit_log post-replay è bit-identico.

---

## Fase C — Time-series visualization core (P0)

**Obiettivo**: la visualizzazione che **manca di più**. Libreria chart minimale + tre integrazioni mirate.

### Helper di vista
- Nuovo `lib/arkea/views/chart.ex` (puro): `linear_scale/3`, `log_scale/3`, `path_for_series/2`, `axis_ticks/2`, `band/3`, `marker/2`. Solo SVG.
- Nuovo `lib/arkea_web/components/chart.ex`: `<Chart.line_series />`, `<Chart.heatmap />`, `<Chart.event_markers />`, `<Chart.brushable_axis />`.

### Integrazioni in SimLive
1. **Population trajectory** — nuovo tab "Trends" (5°). Stacked area `abundance_per_lineage_per_phase`, marker verticali per `:intervention`/`:mass_lysis`/`:mutation_notable`, brushing su asse X che re-pivota le altre viste della pagina.
2. **Metabolite pool heatmap** — nel tab Chemistry: griglia `metabolite × phase × tick` con scala log; tooltip valore esatto. Cross-feeding emerge a colpo d'occhio (rosso → verde dello stesso metabolita tra fasi adiacenti).
3. **QS signal trajectory** — nel tab Chemistry: linee per ogni signal_key, threshold marker per i lineage che lo "ascoltano" (da `phenotype.qs_receives`).

### Lineage drawer arricchito
- Sparkline 200-tick dell'abundance del lineage selezionato; mini-fitness derivata; timeline degli HGT events ricevuti/donati.

### Performance
- Downsampling se >2000 punti: bin per `floor(point / N) * N`. Test che il rendering finale non superi 2k path nodes per series.

### File toccati
- Nuovi: `views/chart.ex`, `components/chart.ex`.
- Modificati: `live/sim_live.ex` (tab + drawer), `views/biotope_scene.ex` (event markers).

### Verifica
- Apri biotope → tab Trends → traiettorie cumulative, tooltip al hover, brushing che filtra le altre tab.
- Snapshot test struttura SVG.

---

## Fase D — Phylogeny / lineage tree (P0)

**Obiettivo**: il singolo deliverable più chiesto da biologi e oggi assente: chi-viene-da-chi.

### Algoritmo + view
- Nuovo `lib/arkea/views/phylogeny.ex` (puro): da `[Lineage.t()]` con `parent_id` chain → tidy-tree (Reingold-Tilford).
- Nuovo `lib/arkea_web/components/phylogeny.ex`: SVG tree con
  - nodi colorati per abbondanza corrente (estinto = grigio + outline tratteggiato)
  - archi etichettati col **delta mutazionale** (gene_id, kind) ricavato dall'evento `:lineage_born` arricchito (Fase B)
  - hover su nodo → mini-card phenotype + sparkline abundance
  - click su nodo → seleziona il lineage (riusa drawer SimLive)

### Integrazione
- Nuovo tab "Phylogeny" in SimLive.
- Standalone su `/biotopes/:id/phylogeny` per share-friendly link.

### Filtri
- "Show extinct branches", "Only HGT donors", "Color by phenotype trait".

### Property tests
- `phylogeny_test.exs`: l'albero copre tutti i lineage (no orfani); ogni non-founder ha esattamente 1 parent valido; N nodi → N-1 archi.

### File toccati
- Nuovi: `views/phylogeny.ex`, `components/phylogeny.ex`.
- Modificati: `live/sim_live.ex` (nuovo tab + route).

### Verifica
- Su biotope con 10+ generazioni: rendering leggibile, archi mutazionali chiari, lineage estinti visibili in grigio.

---

## Fase E — HGT ledger + Sankey provenance (P1)

**Obiettivo**: rendere visibile il flusso orizzontale dei geni — il cuore narrativo dell'evoluzione microbica.

### Cambi
- Nuova vista `/biotopes/:id/hgt-ledger`:
  - Tabella filtrabile: `tick · kind (conjugation/transformation/transduction/phage) · donor → recipient · payload (genes) · effect (Δfitness sull'erede)`.
  - Sankey diagram aggregato (nodi = lineage, size = abbondanza; archi = HGT events, width = numero payload, color = kind).
  - Time-slider per restringere la finestra.
- Nuovo `views/hgt_sankey.ex` (puro): layout Sankey deterministico.

### Cross-link
- Click su nodo Sankey → drawer lineage; click su arco → modal "HGT event detail" con payload geni e link "open recipient phylogeny here".

### Integrazione audit log
- Filtro "HGT only" in Audit condivide la stessa query del Sankey, esposta come API interna riutilizzabile.

### File toccati
- Nuovi: `views/hgt_sankey.ex`, `components/sankey.ex`, `live/hgt_ledger_live.ex`.

### Verifica
- Su scenario stress-test (estuario con plasmidi mobili): ledger ≥10 eventi HGT con donor/recipient corretti; Sankey proporzionato.

---

## Fase F — Compare / iterate / export (P1)

**Obiettivo**: prodotto come banco di esperimenti riproducibili.

### Confronto seed
- Route `/seed-lab/compare?a=<blueprint_id>&b=<blueprint_id>`:
  - SVG side-by-side dei due cromosomi (riusa `GenomeCanvas`).
  - Diff testuale gene-by-gene unificato (added / removed / domains-changed).
  - Diff phenotype scalar fields: tabella di differenze percentuali.

### Confronto biotopi
- Route `/biotopes/compare?a=<id>&b=<id>`:
  - Stacked area popolazioni sovrapposta (asse tick allineato).
  - Phenotype distribution histogram (mean/median/IQR per trait, side-by-side).
  - Audit event diff (unici a A vs unici a B vs comuni).

### Export
- `GET /api/biotopes/:id/snapshot.json` (riusa `BiotopeSnapshot.export/1`): state completo + audit + time-series.
- `GET /api/biotopes/:id/audit.csv` (filtrabile per tick range, event type).
- `GET /api/blueprints/:id.json`: blueprint completo + genome decoded.
- `GET /api/lineages/:id/genome.fasta`: pseudo-FASTA del genoma.
- Pulsante "Export" in: SimLive (snapshot), Audit (CSV), SeedLab (blueprint), Phylogeny (Newick).

### Permalinks
- Ogni vista con stato (filtri Audit, brush window, lineage selection) riflette lo stato in URL come query string. "Copy link" copia URL completo.

### Dry-run
- Nuovo `Arkea.Sim.DryRun.simulate/3` — esegue N tick di un seed in un archetipo target SENZA persistenza, ritorna trajectory previsionale. Esposto in Seed Lab come "Preview 100 tick" prima del submit. Riusa l'engine sim a stato pulito.

### File toccati
- Nuovi: `sim/dry_run.ex`, `controllers/api/biotope_controller.ex`, `live/seed_compare_live.ex`, `live/biotope_compare_live.ex`.
- Modificati: live views per export buttons + permalink state.

### Verifica
- Diff tra 2 blueprint mostra le mutazioni introdotte; export → re-import (Fase G) ricostruisce lo stato.

---

## Fase G — Onboarding, scenario presets, in-app docs (P2)

**Obiettivo**: lower the floor without raising the ceiling.

### First-run wizard
- `live/onboarding_live.ex` triggered alla prima sessione (player con 0 home): wizard 4-step su Seed Lab, Sim viewport, Phylogeny, Audit. Skippabile.

### Scenario presets
- `Arkea.Game.Scenarios` con preset pre-caricati:
  - "Estuario contestato" (DESIGN_STRESS-TEST.md narrativo)
  - "Mutator vs steady" (due home gemelli per A/B)
  - "Antibiotic challenge" (richiede Fase 15 BIO)
  - "Cross-feeding bloom"
- Pulsante "Load scenario..." in Seed Lab che pre-popola form e (opzionalmente) crea direttamente i 2-3 biotopi attesi.

### Docs panel content
- Dashboard "Docs" placeholder ora linka a:
  - `/help/user-manual` (USER-MANUAL renderizzato inline, indicizzato)
  - `/help/design` (DESIGN renderizzato per chi vuole il modello biologico)
  - `/help/calibration` (calibration ranges, riferimenti letteratura)
  - `/help/api` (endpoints di Fase F documentati)
- Glossary search globale: `/help/glossary?q=kcat` cross-doc.

### Notifications (in-tab toast)
- Toast quando un evento di interesse (`:mass_lysis`, `:error_catastrophe_death`) avviene in un biotope owned. Toggle on/off per categoria. Cap rate (max 1 toast / 30s).

### File toccati
- Nuovi: `live/onboarding_live.ex`, `game/scenarios.ex`, `live/help/*`.
- Modificati: `live/dashboard_live.ex` (Docs panel), `live/seed_lab_live.ex` (load scenario).

### Verifica
- Nuovo player vede onboarding al primo login.
- "Load scenario: Estuario contestato" provisiona 3 biotopi corretti e naviga al primo.
- `/help/glossary?q=kcat` mostra la voce.

---

## Sequenza di esecuzione

```
A (foundation) ────────────────┐
                               ↓
B (persistence backfill) ──────┼─→ C (time-series viz) ─→ D (phylogeny) ─→ E (HGT ledger)
                               │                                                      ↓
                               └─→ F (compare/export/dry-run) ──→ G (onboarding/docs)
```

- **A** prerequisito per tutte (nav unificata, help base, shortcut framework).
- **B** blocca C/D/E (dati senza persistenza = grafici vuoti).
- **C** abilita le sparkline nel drawer di D.
- **E** dipende da B (eventi HGT arricchiti).
- **F** dipende da E (export include HGT ledger) e da B (snapshot completo).
- **G** alla fine: usa tutto come building blocks.

Tempo stimato: ~6 settimane dev sequenziali, ~4 con C/D paralleli e F/G paralleli.

---

## File toccati (sintesi)

### Nuovi moduli puri
- `lib/arkea/views/chart.ex`, `views/phylogeny.ex`, `views/hgt_sankey.ex`
- `lib/arkea/persistence/time_series.ex` (estensione `BiotopeSnapshot` per export/import)
- `lib/arkea/sim/event.ex`, `sim/dry_run.ex`
- `lib/arkea/game/scenarios.ex`

### Nuovi componenti web
- `components/help.ex`, `components/shortcuts.ex`, `components/chart.ex`, `components/sankey.ex`, `components/phylogeny.ex`

### Nuove live view / controller
- `live/help_live.ex`, `live/search_live.ex`, `live/seed_compare_live.ex`, `live/biotope_compare_live.ex`, `live/hgt_ledger_live.ex`, `live/onboarding_live.ex`, `controllers/api/biotope_controller.ex`

### Modificati
- Tutte e 6 le live view esistenti (nav unificata, cross-link, permalink state)
- `sim/tick.ex`, `sim/hgt.ex`, `sim/biomass.ex`, `sim/metabolism.ex` (eventi mancanti)
- `persistence/audit_log.ex`, `persistence/audit_writer.ex` (nuovi event types)

### Migrations
- `<ts>_create_time_series_samples.exs`
- `<ts>_extend_audit_log_event_types.exs`

---

## Verifica end-to-end

Per ogni fase:
1. **Test verdi**: `mix test` resta verde, snapshot test per ogni nuova view, property tests per persistenza/eventi.
2. **Performance**: rendering biotope viewport con 50 lineage attivi non regredisce (>20% slowdown = stop).
3. **Demo manuale**: per ogni feature una "demo path" da riprodurre in browser, scritta in PR description.
4. **Reproducibility**: snapshot export → re-import → diff = 0 byte.

End-to-end finale: lo scenario "Estuario contestato" (Fase G preset) deve produrre un biotope dove il microbiologo può
- vedere la curva di abbondanza con marker `:mass_lysis` (Fase B+C);
- aprire il phylogeny e tracciare quale lineage ha donato il plasmide di resistenza (D+E);
- esportare audit log + snapshot per analisi off-line (F);
- comparare due replicate dello scenario (F).

---

## Rischi e mitigazioni

- **DB explosion da time-series**: cap + adaptive sampling + prune. Validato con benchmark a 1000 tick × 50 lineage.
- **Rendering performance dei chart**: downsampling + virtualizzazione; cap su path nodes per series.
- **Combinatorial test surface**: factories StreamData (es. `HGTSituation.build/1`) per scenari riproducibili.
- **Drift docs/UI**: ogni fase aggiorna USER-MANUAL.md + USER-MANUAL.en.md (via `bilingual-docs-maintainer` agent).
- **Accoppiamento con BIOLOGICAL-MODEL-REVIEW**: alcuni eventi (`:error_catastrophe_death`, `:mass_lysis` da biomass) dipendono da Fase 14/17 di quel piano. Per ognuno è specificato un fallback graceful (no-op se la sorgente sim non è ancora attivata): la UI mostra "Source not available yet" invece di crashare.

---

## Output finali attesi a piano completo

- Navigazione coerente, glossario in-app, keyboard shortcuts, search globale.
- Time-series persistite per ogni biotope (popolazioni, metaboliti, segnali, biomass, dna_damage).
- Eventi audit completi: HGT (4 canali) + R-M + lisi + mutazioni notable + colonization + cross-feeding + error catastrophe.
- Time-series visualization: population trajectory, metabolite heatmap, signal trajectory.
- Phylogeny renderizzato con delta mutazionali sugli archi.
- HGT ledger + Sankey di provenienza.
- Diff tra seed e tra biotopi affiancati.
- Export JSON/CSV/FASTA/Newick.
- Permalink stato per ogni view.
- Dry-run preview seed.
- Onboarding wizard, scenario presets, docs panel popolato, notifications.
