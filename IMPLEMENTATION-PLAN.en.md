> 🇮🇹 [Italiano](IMPLEMENTATION-PLAN.md) · 🇬🇧 English (this page)

# Arkea — Implementation plan (high level)

**References**: [DESIGN.en.md](DESIGN.en.md), [DESIGN_STRESS-TEST.en.md](DESIGN_STRESS-TEST.en.md)
**Date**: 2026-04-26
**Status**: Phase 0 ✅ · Phase 1 ✅ · Phase 2 ✅ · Phase 3 ✅ · Phase 4 ✅ · Phase 5 ✅ · Phase 6 ✅ · Phase 7 ✅ · Phase 8 ✅ · Phase 9 ✅ · Phase 10 ✅ · Phase 11 ✅ · UI Evolution ✅ (see §1bis). **Project completed.**

---

## 1. Context

The design (15 blocks consolidated in DESIGN.en.md, validated by the stress test in DESIGN_STRESS-TEST.en.md) is coherent and ready for implementation. The stack is fixed (Block 14):

- **Sim core + orchestration**: Elixir + OTP
- **Web framework**: Phoenix (LiveView for ~80% UI + PixiJS in LV Hook for the 2D WebGL view)
- **DB**: PostgreSQL via Ecto
- **Prototype hosting**: DigitalOcean VPS 1 CPU / 1 GB RAM
- **Prototype scope**: 5–10 biotopes, cap 100 lineages/biotope, 1–4 players

This document defines **how** to build the system: the main architectural choice (with analysis of alternatives considered), the roadmap of incremental phases, and the development discipline to follow.

---

## 1bis. Implementation status

> Updated: 2026-05-02. All 12 phases (0–11) and the UI Evolution refactoring are on `master`. The plan is aligned to the complete shell including the minimal scientifically-correct interface.

Completed phases on `master` as of 2026-05-01:
- Phase 0: Bootstrap Phoenix scaffold (commit `86a3ef2`)
- Phase 1: Core data model + Ecto schemas + property tests (commit `142b4aa`)
- Phase 2: Dilution + environment step
- Phase 3: Gene expression + phenotype
- Phase 4: Stochastic fission + pruning
- Phase 5: Michaelis-Menten metabolism
- Phase 6: HGT + mobile elements — conjugation, prophage induction, plasmid cost (commit `7491a3f`)
- Phase 7: Quorum sensing & signaling (commit `a9adab8`)
- Phase 8: Migration + biotope network topology (commit `82e1d5f`)
- Phase 9: UI: LiveView + PixiJS Hook (commit `0c047c0`)
- Phase 10: Complete persistence (commit `fec12f6`)
- Phase 11: Abridged "Chronicles" use case (commit `bd72aed`)

### Phase 8 — Migration + network topology ✅ completed (commit `82e1d5f`)

**Design decisions** (`elixir-otp-architect`, 2026-05-01):

- **Global post-tick barrier**: migration does not live inside `Arkea.Sim.Tick`; `Arkea.Sim.Migration.Coordinator` subscribes to `"world:tick"`, waits until every participating biotope reaches the same `tick_count`, then computes the pure plan via `Arkea.Sim.Migration.plan/2` and applies transfers through `Biotope.Server.apply_migration/3`
- **Topology on `BiotopeState`**: `x`, `y`, `zone`, `owner_player_id`, and `neighbor_ids` were added so the coordinator can derive the graph directly from runtime state without external shared state
- **Multi-level transfers**: flows along edges cover lineages (integer cell-equivalent counts), metabolites (float), signals (float), and free phages (integer); lineages migrate phase-to-phase, while environmental pools follow the same edge graph with dedicated scaling
- **Connectivity formula**: `edge_weight = 1 / (1 + euclidean_distance)`; `biotope_compatibility` is the mean of best phase compatibilities; `phase_compatibility` weights temperature, pH, and osmolarity differences with a bonus when phase names match (`surface -> surface`, etc.)
- **Emergent mobility by phase/phenotype**: each phase has a base `phase_mobility`; phenotype modulates it with penalty `n_transmembrane × 0.12` and bonus `structural_stability × 0.10`, final clamp `0.05..1.0`
- **Runtime configuration**: default `base_flow = 0.12`; separate scaling for pools `metabolite = 0.45`, `signal = 0.70`, `phage = 0.30`; coordinator barrier with `migration_settle_delay_ms = 10` and `migration_max_retries = 25`, all overrideable via `Application.get_env/3`
- **Audit/broadcast for Phase 8**: applying a transfer on `Biotope.Server` emits `%{type: :migration, payload: ...}` and reuses the existing `{:biotope_tick, new_state, events}` broadcast observed by the UI

**Modules created/modified**:

| Module | File | Change |
|---|---|---|
| `Arkea.Sim.Migration` | `lib/arkea/sim/migration.ex` | new — pure planner, edge/phase compatibility, transfer application |
| `Arkea.Sim.Migration.Coordinator` | `lib/arkea/sim/migration/coordinator.ex` | new — global post-tick barrier + apply orchestration |
| `Arkea.Sim.Biotope.Server` | `lib/arkea/sim/biotope/server.ex` | `apply_migration/3`, `:migration` event, reused broadcast helper |
| `Arkea.Sim.BiotopeState` | `lib/arkea/sim/biotope_state.ex` | runtime topology coordinates (`x`, `y`, `zone`, `owner_player_id`, `neighbor_ids`) |
| `Arkea.Application` | `lib/arkea/application.ex` | added `MigrationCoordinator` child to the supervision tree |

**Test suite** (new):
- `test/arkea/sim/migration_test.exs` — 1 property + 2 tests: total abundance conservation on reciprocal plans, preference for environmentally compatible phases, coherent transfer of metabolites/signals/phages along the same edge
- `test/arkea/sim/migration/coordinator_test.exs` — integration test on a 5-biotope chain: one-hop-per-tick diffusion and conservation of total mass

**Architectural notes**:
- `Migration.Coordinator.run_migration/1` exists only for tests that use `manual_tick/1`; the real runtime path remains PubSub-driven on `"world:tick"`
- Delivered Phase 8 covers topology + migration. Player-facing **claim/colonization** rules remain out of scope until lineages carry explicit provenance for home biotope / owner

**Final suite**: `mix format --check-formatted` + `mix test` → **124 properties, 207 tests, 0 failures**

### Phase 9 — UI: LiveView + PixiJS Hook ✅ completed (base commit `0c047c0`, then refined in later integrations)

**Design decisions** (`design-coherence-reviewer` + `elixir-otp-architect`, 2026-05-01):

- **Client-side scene, server-authoritative state**: `ArkeaWeb.SimLive` still receives only `BiotopeState` + events from PubSub; the client computes no dynamics and instead renders a snapshot serialized by the LiveView
- **Multi-view simulation shell**: the UI is split across player access on `"/"`, `WorldLive` on `"/world"`, `SeedLabLive` on `"/seed-lab"`, and `SimLive` on `"/biotopes/:id"`; `GameChrome` provides shared navigation between world overview, seed builder, and detailed viewport
- **Dedicated PixiJS hook resilient to LiveView patches**: `BiotopeScene`, mounted through `phx-hook="BiotopeScene"` in `assets/js/hooks/biotope_scene.js` and registered in `assets/js/app.js`, initializes a `PIXI.Application`, listens to `push_event("biotope_snapshot", ...)`, maps canvas clicks back to `pushEvent("select_phase", %{phase: ...})`, and keeps the canvas alive through `phx-update="ignore"` plus the `ensureCanvasMounted()` remount guard
- **Readable, stable procedural rendering**: 2D regions are per-phase abundance bands; dots represent lineage fractions colored by phenotypic cluster (`biofilm`, `motile`, `stress-tolerant`, `generalist`, `cryptic`) and are deterministically anchored by `phase + lineage + slot`, so consecutive ticks change density rather than fully reshuffling positions
- **Viewport clarity pass**: ambiguous glow overlays were removed; safe vertical margins were added so labels/header/footer are not occluded; an explicit legend (band, dot, focus) plus `pointer` cursor make phase selection legible to the player
- **Authenticated-player onboarding**: the browser enters through `PlayerAccessController` on `"/"`, creates or resumes a persisted `Player` by email, and opens a browser session; `SeedLabLive` then uses `current_player` for starter-ecotype choice, phenotype-first tuning, genome/phenotype preview, and first-home provisioning, while `WorldLive` shows network overview, ownership, and the active ecotype inventory
- **Readable navigation and world map**: the shell now uses direct `href` links between `World`, `SeedLab`, and `Biotope`; decorative layers no longer intercept pointer events, and `Arkea.Game.World` resolves node collisions before render so biotope cards do not overlap
- **Seed-editor groundwork**: `SeedLabLive` now also exposes a gameplay-facing `Arkeon phenotype portrait` and a read-only `Chromosome atlas` that already separates chromosome, plasmids, and prophages as the basis for the future advanced editor
- **Responsive non-boilerplate shell**: dashboards and maps use dedicated CSS in `assets/css/app.css` with atmospheric background, reveal animation, and mobile-first layout, while keeping world-scale and biotope-scale views distinct

**Modules/files created or modified**:

| Module / asset | File | Change |
|---|---|---|
| `ArkeaWeb.WorldLive` | `lib/arkea_web/live/world_live.ex` | new — macroscale world overview, network map, active ecotype inventory, navigation CTAs |
| `ArkeaWeb.SeedLabLive` | `lib/arkea_web/live/seed_lab_live.ex` | new — seed builder, phenotype/genome preview, morphology portrait, chromosome atlas, and first home-biotope provisioning |
| `ArkeaWeb.SimLive` | `lib/arkea_web/live/sim_live.ex` | full refactor: detailed viewport, snapshot serialization, phase selection, operator panel, ownership/budget feedback |
| `ArkeaWeb.GameChrome` | `lib/arkea_web/game_chrome.ex` | new — shared top navigation for world, seed lab, and biotope view |
| `Arkea.Accounts`, `ArkeaWeb.PlayerAuth` | `lib/arkea/accounts.ex`, `lib/arkea_web/player_auth.ex` | new — minimal player-account context plus browser session gate for controllers/LiveView |
| `ArkeaWeb.PlayerAccessController`, `ArkeaWeb.PlayerAccessHTML` | `lib/arkea_web/controllers/player_access_controller.ex`, `lib/arkea_web/controllers/player_access_html/*` | new — `"/"` entrypoint for create/resume player before entering the simulation |
| `Arkea.Game.World` | `lib/arkea/game/world.ex` | new — lightweight runtime read model for the world overview, network map, and node-collision resolution |
| `Arkea.Game.SeedLab`, `Arkea.Game.PrototypePlayer` | `lib/arkea/game/seed_lab.ex`, `lib/arkea/game/prototype_player.ex` | new/extended — phenotype-first builder with `current_player` flow; `PrototypePlayer` remains only as a compatibility helper for tests and low-level call sites |
| `BiotopeScene` hook | `assets/js/hooks/biotope_scene.js` | new — PixiJS scene with phase bands, stable-anchor dots, remount safety, click → `pushEvent` |
| LiveSocket hooks | `assets/js/app.js` | registers `BiotopeScene` |
| web + LiveView router | `lib/arkea_web/router.ex` | `"/"` player-access route plus authenticated `live_session` for `WorldLive`, `SeedLabLive`, and `SimLive` |
| UI shell CSS | `assets/css/app.css` | new responsive skin with `sim-*` classes, readable world map, seed portrait, and chromosome atlas |
| asset manifest | `assets/package.json`, `assets/package-lock.json` | adds dependency `pixi.js` `^8.18.1` |

**Test suite** (new/updated):
- `test/arkea_web/controllers/page_controller_test.exs` — verifies the access page on `/`, create/resume player, authenticated redirect to `/world`, anonymous gate, and logout
- `test/arkea_web/live/world_live_test.exs` — renders the world shell with map and navigation CTAs
- `test/arkea_web/live/seed_lab_live_test.exs` — verifies ecotype preview/seed builder flow, portrait + atlas rendering, and home-biotope provisioning redirect
- `test/arkea_web/live/sim_live_test.exs` — verifies LiveView phase selection (`surface -> sediment`), `phx-update="ignore"` canvas container, `World/Seed lab` links, and player-biotope intervention panel
- `test/arkea/game/world_test.exs` — verifies that the world-layout resolver avoids overlap between nodes with colliding initial coordinates

**Architectural notes**:
- The canvas remains a **pure visualization** of authoritative per-phase data, consistent with DESIGN.en.md Block 12: clicking a single dot has no simulation effect
- The Hook ↔ LiveView bridge uses both channels called for in the design stack: `push_event` server → hook for snapshots, and `pushEvent` hook → LiveView for phase selection
- The `PlayerAccess -> WorldLive -> SeedLabLive -> SimLive` split clarifies the difference between player access, world view, seed construction, and authoritative single-biotope detail
- Authoritative interventions are layered later through `apply_intervention/2` and are documented in Phase 10; the Phase 9 viewport still stays an aggregated phase view, not a client-side simulation
- The delivered shell remains **simulation-first**: no leaderboard, presence, or contest loop is part of the runtime contract; the goal is observation/intervention on controlled biotopes within a shared world
- Development JS bundle: `priv/static/assets/js/app.js` grows to about `1.9mb` because of PixiJS. Acceptable for the prototype; extra slimming/tree-shaking can be handled as follow-up work

**Final suite**: `mix format` + `mix assets.build` + `mix test` → **124 properties, 237 tests, 0 failures**

### Phase 10 — Complete persistence ✅ completed (base commit `fec12f6`, then extended with player assets and authoritative interventions)

**Design decisions** (`ecto-postgres-modeler` + `elixir-otp-architect`, 2026-05-01):

- **Full-state WAL per transition**: `Biotope.Server` persists an append-only row in `biotope_wal_entries` after each local tick and after each `apply_migration/3`; the row stores the compressed serialized `BiotopeState`, so recovery doesn't depend on replaying partial deltas
- **Periodic snapshots via Oban**: every transition with `tick_count rem 10 == 0` enqueues `SnapshotWorker`, which copies the source WAL row into `biotope_snapshots`; upsert on `(biotope_id, tick_count)` allows a migration later in the same tick to overwrite the snapshot with the newest state
- **Two-tier recovery**: `Arkea.Persistence.Recovery` chooses between latest WAL and latest snapshot, preferring WAL on equal ticks; at boot it repopulates `Biotope.Supervisor` with all persisted biotopes and seeds the default scenario only when no recoverable state exists
- **Restart-safe child boot**: `Biotope.Server.start_link/1` now passes through `Recovery.resolve_start_state/1`, so a crashed process under `Biotope.Supervisor` restarts from the newest persisted state instead of the original seed
- **Persisted player assets + authoritative interventions**: `SeedLab` persists `ArkeonBlueprint` and `PlayerBiotope` for the authenticated player's first home biotope; `PlayerInterventions` validates ownership and per-biotope intervention budget, writes `intervention_logs`, and calls `Biotope.Server.apply_intervention/2`, which delegates pure transforms such as `nutrient_pulse`, `plasmid_inoculation`, and `mixing_event` to `Arkea.Sim.Intervention`
- **Authenticated player access on top of the `Player` schema**: `Arkea.Accounts` registers and reloads `Player`; `ArkeaWeb.PlayerAuth` handles browser session plus `live_session`; `PlayerAccessController` exposes `"/"` as the create/resume page and removes the forced bootstrap into a fixed operator
- **Seed immutability after first colonization**: once an active player `home` exists, `SeedLab` reloads the persisted blueprint, disables phenotype options, and shows the same seed as a read-only configuration bound to the initial biotope
- **Typed audit in the same transaction**: `Arkea.Persistence.AuditWriter` normalizes runtime events (`lineage_born`, `lineage_extinct`, `hgt_event`, `migration`, `intervention`) and also propagates `actor_player_id` into `audit_log` within the same `Ecto.Multi` as the WAL write
- **Explicit test gating**: `config/test.exs` keeps `:persistence_enabled` disabled by default so pure tick tests don't incur DB I/O; Phase 10 tests re-enable it locally and start `Arkea.Oban` in `testing: :manual`

**Modules/files created or modified**:

| Module / file | Path | Change |
|---|---|---|
| `Arkea.Persistence` | `lib/arkea/persistence.ex` | runtime `enabled?/0` gate for persistence |
| `Arkea.Oban` | `lib/arkea/oban.ex` | application Oban facade |
| `Arkea.Persistence.Serializer` | `lib/arkea/persistence/serializer.ex` | safe `BiotopeState <-> binary` serialization |
| `Arkea.Persistence.BiotopeWalEntry` | `lib/arkea/persistence/biotope_wal_entry.ex` | append-only WAL schema |
| `Arkea.Persistence.BiotopeSnapshot` | `lib/arkea/persistence/biotope_snapshot.ex` | periodic snapshot schema |
| `Arkea.Persistence.AuditWriter` | `lib/arkea/persistence/audit_writer.ex` | runtime event → `audit_log` mapping |
| `Arkea.Persistence.Store` | `lib/arkea/persistence/store.ex` | transactional `Ecto.Multi`: WAL + audit + snapshot enqueue |
| `Arkea.Persistence.SnapshotWorker` | `lib/arkea/persistence/snapshot_worker.ex` | Oban worker that materializes snapshots from WAL |
| `Arkea.Persistence.Recovery` | `lib/arkea/persistence/recovery.ex` | boot restore + `resolve_start_state/1` helper |
| `Arkea.Persistence.ArkeonBlueprint` | `lib/arkea/persistence/arkeon_blueprint.ex` | new — persisted seed blueprint for the player |
| `Arkea.Persistence.PlayerBiotope` | `lib/arkea/persistence/player_biotope.ex` | new — explicit player ↔ controlled-biotope relation (`home`, `colonized`) |
| `Arkea.Persistence.InterventionLog` | `lib/arkea/persistence/intervention_log.ex` | new — append-only log for intervention budget and history |
| `Arkea.Game.PlayerAssets` | `lib/arkea/game/player_assets.ex` | new — registers player, blueprint, and home biotope in one `Ecto.Multi` |
| `Arkea.Game.PlayerInterventions` | `lib/arkea/game/player_interventions.ex` | new — ownership checks, per-biotope budget enforcement, player-command audit |
| `Arkea.Accounts` | `lib/arkea/accounts.ex` | new — registration/resume of persisted players |
| `ArkeaWeb.PlayerAuth` | `lib/arkea_web/player_auth.ex` | new — browser session + LiveView access gate |
| `ArkeaWeb.PlayerAccessController`, `ArkeaWeb.PlayerAccessHTML` | `lib/arkea_web/controllers/player_access_controller.ex`, `lib/arkea_web/controllers/player_access_html/*` | new — player access forms and redirect into the shared world |
| `Arkea.Sim.Intervention` | `lib/arkea/sim/intervention.ex` | new — pure intervention transforms outside the tick |
| DB migration | `priv/repo/migrations/20260501113000_add_runtime_persistence.exs` | new `biotope_wal_entries`, `biotope_snapshots`, `oban_jobs` tables |
| player/runtime migration | `priv/repo/migrations/20260501143000_add_player_assets_and_intervention_logs.exs` | new `arkeon_blueprints`, `player_biotopes`, `intervention_logs` tables |
| runtime/UI config | `lib/arkea/application.ex`, `lib/arkea/sim/biotope/server.ex`, `lib/arkea/game/seed_lab.ex`, `lib/arkea/game/prototype_player.ex`, `lib/arkea_web/live/sim_live.ex`, `config/config.exs`, `config/test.exs` | supervisor wiring, post-tick persistence, `apply_intervention/2`, ownership/budget in the operator panel |

**Test suite** (new/updated):
- `test/arkea/persistence/runtime_persistence_test.exs` — 4 integration tests: WAL + audit on `manual_tick/1`, snapshot enqueue/materialization at tick 10, `Biotope.Server` restart from latest WAL, recovery child restoring persisted biotopes at boot
- `test/arkea/game/player_interventions_test.exs` — authoritative player intervention: server-state mutation, `intervention_logs` write, subsequent budget lock
- `test/arkea_web/controllers/page_controller_test.exs` — persisted player create/resume, protected routes, and logout
- `test/arkea_web/live/seed_lab_live_test.exs` — seed/home provisioning with `ArkeonBlueprint` and `PlayerBiotope` verification, plus read-only reopening of the seed after the first home
- `test/arkea_web/live/sim_live_test.exs` — `nutrient_pulse` execution on a player-controlled biotope and budget-lock feedback in LiveView

**Architectural notes**:
- Phase 10 WAL is a **full-state journal**, not the canonical event stream: deliberate choice for simple, robust prototype recovery
- The snapshot is built **from already-written WAL**, not by querying the live process, so the worker stays idempotent and doesn't depend on a running `Biotope.Server`
- When a snapshot-worthy tick is followed by migration in the same tick, recovery still prefers WAL; the snapshot acts as a periodic checkpoint and is realigned through upsert
- Player interventions remain **outside the pure tick**, but still pass through the state-owning `Biotope.Server`: the `tick(state) -> {new_state, events}` boundary stays intact even with realtime player actions
- Each authenticated player may own only one active `home`; the UI uses `player_biotopes` plus `intervention_logs` to expose ownership and cooldown consistently with authoritative simulation state. `PrototypePlayer` survives only as a compatibility helper for tests and legacy call sites
- The future advanced genome editor should operate on the persisted blueprint layer (`arkeon_blueprints`), not directly on live biotope state

**Final suite**: `mix format` + `MIX_ENV=test mix ecto.migrate` + `mix ecto.migrate` + `mix assets.build` + `mix test` → **124 properties, 237 tests, 0 failures**

---

### Phase 11 — Abridged "Chronicles" use case ✅ completed (commit `bd72aed`)

Reproduced the DESIGN_STRESS-TEST.md stress test at prototype scale: from seed, over a few real-time hours of ticks, antibiotic resistance, biofilm, prophage induction, and competitive colonization between biotopes all emerge. All 15 design blocks traversed in the operational runtime.

**Final suite**: `mix compile` + `mix test` → **124 properties, 237 tests, 0 failures**

---

### UI Evolution — post-Phase-11 refactoring ✅ (current commit)

**Goal**: minimal, scientifically correct, compact, and functional interface for expert biologists/microbiologists — no decorative noise, SI units throughout, maximum information density, zero vertical scroll at 1440px.

**P1 — Design token cleanup + aurora removal** (`app.css`):
- Semantic biology variables: `--bio-growth` (oklch green), `--bio-stress` (red), `--bio-signal` (amber), `--bio-metabolite` (blue); spacing system `--space-1..6`; typographic scale `--text-xs..lg`
- Removed `.sim-shell__aurora` and `sim-aurora-float` keyframe (GPU-heavy, no informational value)
- `.sim-card`: uniform background (no radial-gradient), box-shadow reduced 40%
- `font-variant-numeric: tabular-nums` on all numeric values

**P2 — Biotope viewport restructure** (`sim_live.ex` + `app.css`):
- Layout `biotope-shell` → `biotope-header` (48px) + `biotope-grid` (`55fr 45fr`, `height: calc(100vh - 92px)`)
- Right column `overflow-y: auto` — eliminates the off-viewport second grid at 1440px
- Topology panel moved into an HTML `<dialog>` modal (trigger: gear button in header)
- Event log + operator panel grouped in a daisyUI `tabs-box` (Events / Interventions)

**P3 — Phase inline-KPI tabs + compact lineage table** (`sim_live.ex`):
- Inline phase tabs showing T (°C), pH, N per phase; active left-border via CSS
- Lineage table reduced to 7 columns: ID · Cluster · Dom. phase · N · µ (h⁻¹) · ε · Born
- Client-less sorting via `phx-click="sort_lineages"` for 4 fields
- Shannon diversity H′ = Σ −p·ln(p) added to the phase inspector KPIs
- Environmental labels with SI units: `T (°C)`, `Osm (mOsm/L)`, `D (%/tick)`, `µ (h⁻¹)`

**P4 — Chemistry heatmap** (`sim_live.ex` + `app.css`):
- 13 canonical metabolites × N phases; intensity via `color-mix(in oklab, var(--bio-metabolite) calc(var(--fill) * 55%), transparent)`
- Replaces token clouds that showed only the top-4

**P5 — PixiJS improvements** (`biotope_scene.js`):
- Event queue for transient animations: `lineage_born` (green expanding circle), `lineage_extinct` (red collapsing), `hgt_transfer` (amber arc)
- Cluster shapes: biofilm → rectangle, motile → elongated ellipse, others → circle
- Overlay reduced to `tick ${n}` only; phase label with `T ${T}°C · pH ${ph} · D ${D}%/tick`; `MAX_PHASE_PARTICLES` 72 → 60

**P6 — World overview + Seed Lab** (`world_live.ex`, `seed_lab_live.ex`):
- World: proportional archetype breakdown bar in sidebar; simplified table columns; compact world-map nodes
- Seed Lab: gene inspector collapsed by default (`toggle_inspector`), 3-column domain palette, KPIs with σ affinity and QS signals

**P7 — Nav + flash polish** (`game_chrome.ex`, `core_components.ex`):
- Logout → daisyUI `dropdown` with chevron on player name; `aria-current="page"` on active links
- Info flash → `role="status"` (was `role="alert"`); nav padding: `0.9rem 1rem` → `0.5rem 0.9rem`

**Files modified**:

| File | Priority |
|---|---|
| `arkea/assets/css/app.css` | P1–P4, P6, P7 |
| `arkea/lib/arkea_web/live/sim_live.ex` | P2–P4 |
| `arkea/assets/js/hooks/biotope_scene.js` | P5 |
| `arkea/lib/arkea_web/live/world_live.ex` | P6 |
| `arkea/lib/arkea_web/live/seed_lab_live.ex` | P6 |
| `arkea/lib/arkea_web/game_chrome.ex` | P7 |
| `arkea/lib/arkea_web/components/core_components.ex` | P7 |

**Final build**: `mix compile` → clean, 0 warnings, 0 errors.

---

## 2. Main architectural choice

### 2.1 Decision

**Active Record pattern (BEAM-canonical)** for state management and tick, with two **structural caveats** that mitigate the pattern's weaknesses and keep open a path for future evolution.

**Model**:
- One `Biotope.Server` GenServer per biotope. State (lineages, phases, metabolites, signals, free phages) lives **in the process's memory**, in Elixir structs.
- The tick is a **pure function** `tick(state) -> {new_state, events}`, applied sequentially by the GenServer. Internally parallelizable per phase via `Task.async_stream` when profiling justifies it.
- **Inter-biotope migration** is orchestrated by the `Migration.Coordinator` after each global tick: `Phoenix.PubSub` barrier on `world:tick`, fetch of current states, pure transfer planning, and per-biotope apply.
- **Persistence** is complete runtime persistence: full-state WAL for tick/migration transitions + periodic snapshots via Oban worker (every 10 ticks = 50 real minutes) + boot-time recovery.

### 2.2 The two structural caveats

**Caveat 1 — Structured audit log from day 1**.
Even though we do not adopt full event sourcing, the tick writes relevant events to a well-typed `audit_log` table: notable mutations, HGT events, mass lyses, appearance of chimeras, player interventions, colonization events. Satisfies Block 13 (anti-griefing, origin tracking) and provides partial time-travel debugging without paying the full-CQRS price. It is a **subset** of event sourcing where we keep only events of interest.

**Caveat 2 — Pure-functional discipline of the tick**.
The tick is strictly `state -> {new_state, events}`. No side-effects internal to the tick function (DB writes, broadcasts, notifications happen *after* the computation, from the GenServer that orchestrates them). This discipline:
- Makes the tick maximally testable (property-based testing becomes natural)
- Keeps **open the migration path to full event sourcing** if ever needed in the future: it would suffice to persist `events` instead of applying them immediately
- Allows parallelizing the tick by phases without concurrency problems

### 2.3 Rationale

The "Active Record + audit subset + pure functions" combination captures **80% of the benefits of event sourcing at 30% of its cost**:

| Event Sourcing benefit | Satisfied by AR + caveats? |
|---|---|
| Native audit log (Block 13) | ✅ via structured audit_log table (caveat 1) |
| Tick testability | ✅ via pure function (caveat 2) |
| Time-travel debugging | ⚠️ partial: snapshot every 10 ticks + audit log for notable events |
| Perfect replay for analysis | ❌ would require full ES |

The only benefit **not** satisfied is perfect replay. We accept it as a trade-off until a concrete need emerges.

---

## 3. Alternatives considered

### 3.1 Discarded alternative: Full Event Sourcing (CQRS-like)

State derived entirely from a stream of events appended in Postgres. Tick = command handler that produces events; current state = reconstructed projection.

**Pros**: native audit, perfect time-travel, arbitrary replay, pattern suitable for mature systems with critical audit.

**Cons**: implementation complexity (event store, projections, idempotency, consistency), storage footprint growing linearly, reduced per-tick performance (write event + apply projection for every change), not idiomatic in pure Elixir (requires libraries like Commanded).

### 3.2 Weighted evaluation (for reconstructibility of the decision)

Weighting on criteria relevant to the **project profile** (prototype on 1 GB VPS + multi-year lifetime + expert audience + critical audit for Block 13):

| Criterion | Weight | Active Record | Event Sourcing |
|---|---|---|---|
| Initial development simplicity | 3 | 9/10 | 4/10 |
| Per-tick performance | 2 | 8/10 | 5/10 |
| Memory footprint (1 GB VPS) | 2 | 9/10 | 6/10 |
| DB storage footprint | 2 | 8/10 | 4/10 |
| Native audit log (Block 13) | 3 | 5/10 (raised to ~9/10 with caveat 1) | 10/10 |
| Time-travel debugging / replay | 2 | 3/10 | 10/10 |
| Testability | 3 | 8/10 (raised to 9/10 with caveat 2) | 8/10 |
| Resilience / fault tolerance | 2 | 8/10 | 8/10 |
| Debugging / observability | 3 | 7/10 | 8/10 |
| NIF Rust migration path | 2 | 9/10 | 7/10 |
| Multi-node scalability | 2 | 7/10 | 8/10 |
| Adherence to Elixir/OTP patterns | 2 | 10/10 | 6/10 |
| Maturity of Elixir ecosystem | 2 | 10/10 | 7/10 |

**Base weighted score**: AR = 7.7/10, ES = 6.7/10
**With caveats 1+2 applied to AR**: AR ≈ 8.3/10

### 3.3 Future evolution path

If in the future a strong need emerged (scientific replay, formal disputes over griefing, retrospective analysis of a long campaign), a **partial migration toward event sourcing for critical sub-systems** (e.g. only mobile elements and player interventions) is feasible without rewriting the core. The pure-functional discipline from the start is the strength that enables this path.

---

## 4. Process-level architecture (Elixir)

```
Application Supervisor
├── WorldClock (GenServer, ticks every 5 min wall-clock)
├── Biotope.Supervisor (DynamicSupervisor)
│   └── Biotope.Server × N (one per active biotope)
│       state: phases, lineages (with delta_genome), metabolites, signals, phages
│       handle_tick: tick(state) → {new_state, events}; persist + broadcast post-compute
├── Migration.Coordinator (orchestrates inter-biotope step after each tick)
├── Player.Supervisor (DynamicSupervisor)
│   └── Player.Session × M
├── Phoenix.PubSub (broadcast events to client + Biotope ↔ Migration coordination)
├── Persistence.Snapshot (Oban worker, every 10 ticks: copy source WAL into snapshot)
├── Persistence.AuditLog (insert on relevant events table, transactional)
└── Persistence.Recovery (at boot: rebuild state from latest snapshot/WAL)
```

### 4.1 Tick shape

```elixir
# Pure function — the heart of the discipline
def tick(%BiotopeState{} = state) do
  new_state =
    state
    |> step_metabolism()
    |> step_expression()
    |> step_cell_events()    # division, lysis, mutation → new lineages
    |> step_hgt()
    |> step_environment()    # decay, dilution
    |> step_pruning()

  events = derive_events(state, new_state)
  {new_state, events}
end

# Biotope.Server — local side-effects orchestration
def handle_info(:tick, state) do
  {new_state, events} = Tick.tick(state)
  PubSub.broadcast(Topic.biotope(state.id), {:tick, new_state, events})
  Persistence.Store.persist_transition(new_state, events, :tick)
  {:noreply, new_state}
end

# Migration.Coordinator — global post-tick barrier
def handle_info({:tick, n}, state) do
  participating_states()
  |> wait_until(&(&1.tick_count == n))
  |> Migration.plan()
  |> apply_plan(n)
  {:noreply, state}
end
```

---

## 5. Implementation roadmap

12 incremental phases. Each phase leaves a working and demonstrable system, even if incomplete. The order maximizes **early evolutionary feedback**: as early as Phase 4 the first emergent phenomena are visible.

| Phase | Deliverable | Success criterion | DESIGN blocks covered |
|---|---|---|---|
| **0. Bootstrap** | Phoenix scaffold + Postgres + Ecto + base CI + LiveDashboard | `mix phx.server` starts; LV "Hello Arkea" served; CI pipeline green | 14 (stack) |
| **1. Core data model** | Structs: Codon, Domain, Gene, Genome, Lineage, Phase, Biotope + base Ecto schema | Property tests that validate struct invariants | 4, 7 |
| **2. Minimal tick engine** | `WorldClock` + `Biotope.Server` with "empty" tick (only aggregate growth/decay) | One biotope, population grows and equilibrium with dilution | 11 |
| **3. Generative domain system** | Codon parser → domains → emergent phenotype | Test: given a known genome, deterministic computation of phenotypes | 7 |
| **4. Mutation + selection + lineages** | Mutator (point, indel, dup, inv, translocations), lineage fission, delta encoding, pruning, fitness | **First evolutionary test**: from a seed, in 100 ticks visible polymorphic variety emerges | 4, 5 (partial), 7 |
| **5. Metabolism + regulation** | The 13 metabolites, Michaelis-Menten reactions, σ-factor + riboswitch, ATP balance | Test: different strains win in biotopes with different metabolic profiles | 6, 7 (regulation), 8 (partial) |
| **6. HGT + mobile elements** | Plasmids, prophages, gene-encoded conjugation, phage lysis, plasmid cost | Test: introduction of a plasmid → measurable spread via HGT | 5, 8 |
| **7. Quorum sensing & signaling** | 4D synthase + receptors, QS program, density-dependence | Test: program OFF at low N, ON at high N | 9 |
| **8. Migration + network topology** | Biotope network, weighted arcs, biotope_compatibility, phases (Block 12) | Test: 5 connected biotopes, lineages spread coherently; emergent phase preferences | 3, 5, 10, 12 |
| **9. UI: LiveView + PixiJS Hook** | `Access / World / Seed lab / Biotope` shell, procedural 2D view, dashboards, ecotype inventory, seed builder, `Arkeon phenotype portrait`, `Chromosome atlas`, event log | A registered player can enter the simulation, design the seed, provision the home biotope, navigate the world overview, and open the detailed viewport | 12, 14 |
| **10. Complete persistence** | Snapshot every 10 ticks + audit log + recovery + `arkeon_blueprints` / `player_biotopes` / `intervention_logs` | Deliberate crash → restart → state preserved; seed, home, and player interventions persisted with authoritative budget, and the starter seed reopens read-only after first colonization | 11, 13, 14 |
| **11. Abridged "Chronicles" use case** | Reproduction of the stress test on prototype scale | From seed → resistance, biofilm, prophage, colonization visible in a few real hours | all |

### 5.1 Dependencies and parallelism

- Phases 0–4 are **strictly sequential** (each phase depends on the previous one)
- Phases 5, 6, 7 can proceed partially in parallel after 4
- Phases 9 and 10 can start after 4, in parallel with 5–8
- Phase 8 depends on 5 (for cross-biotope metabolic kinetics) and 12 (phases) <!-- translator note: source says "12 (fasi)" but only 11 phases are listed; preserved verbatim — likely refers to Block 12 (phases) of DESIGN -->
- Phase 11 closes everything

### 5.2 Estimated relative complexity

| Phase | Relative complexity |
|---|---|
| 0 | Low (boilerplate) |
| 1, 2 | Medium (careful modeling) |
| 3, 4 | **High** (the generative system is the creative core) |
| 5 | **High** (kinetics + regulation + balances) |
| 6, 7 | Medium-high |
| 8 | Medium |
| 9 | Medium (PixiJS + LV Hook) |
| 10 | Medium |
| 11 | Low-medium (orchestration of already existing pieces) |

---

## 6. Development discipline

Non-negotiable from the start of the project. They serve to keep the design coherent with the implementation and to open paths for future evolution without technical debt.

### 6.1 Pure-functional tick

The tick and all its sub-steps (`step_metabolism`, `step_expression`, …) are **pure functions**: input = `state`, output = `new_state` or `{new_state, events}`. No I/O, no messages, no DB access from the tick functions. Side-effects (persistence, broadcast, notifications) happen in the GenServer **after** the tick computation.

### 6.2 Property-based testing for evolutionary invariants

ExUnit + StreamData to verify invariants that must hold for every input:
- Mass conservation (the sum of consumed metabolites = sum of products + waste, modulo dilution)
- Phylogenetic tree monotonicity (a parent_id always points to an older lineage)
- Tick determinism (same state + same RNG seed → same new_state)
- No fitness < 0 for any lineage
- Correct pruning (after prune, no lineage with N < threshold in the biotope, but all still in the historical tree)

### 6.3 Audit log from Phase 4

Don't wait until Phase 10 to write audit. Already from Phase 4 (mutation + lineages), the tick produces typed events that are persisted in `audit_log`. This:
- Forces the discipline of typed events from the start (easier to extend than retrofit)
- Provides immediate debugging on complex evolutions
- Satisfies Block 13 without being a late addition

### 6.4 Built-in telemetry

`:telemetry` instrumented from Phase 2: tick duration, lineage count per biotope, notable events per minute. LiveDashboard configured for internal visualization. When we go to production, we plug in the Prometheus exporter.

### 6.5 No premature optimization

Profile first, optimize after. The VPS is 1 GB / 1 CPU for the prototype: we will probably never see bottlenecks at that scale. NIF Rust, Mnesia, ETS sharing remain documented escape hatches but **not implemented** until a real benchmark justifies them.

### 6.6 Genome serialized as Erlang term

Default: `:erlang.term_to_binary/1` with compression for DB dump (`bytea` field). Optional JSONB for post-hoc analytics. No custom formats until they are needed.

---

## 7. Concrete next steps — Phase 0

Once this plan is confirmed, Phase 0 is a mechanical checklist:

1. `mix phx.new arkea --no-mailer --no-gettext --binary-id` (Phoenix scaffold)
2. Configure local Postgres + production (on the DigitalOcean VPS)
3. Add dependencies: `oban`, `stream_data`, `dialyxir`, `credo`
4. Configure GitHub Actions: `mix test`, `mix dialyzer`, `mix credo`
5. Configure LiveDashboard
6. First deploy on the VPS (mix release + systemd + Caddy)
7. Green CI + LiveView "Hello Arkea" reachable on the domain

Expected output: ~3–5 days of work, environment ready for Phase 1.

---

## 8. Summary

**Architecture**: Active Record (BEAM-canonical) + structured audit log + pure-functional discipline of the tick.
**Rationale**: 80% of the benefits of Event Sourcing at 30% of the cost, with an open evolution path.
**Roadmap**: 12 incremental phases, demonstrable one by one, with first evolutionary feedback in Phase 4.
**Discipline**: pure functions, property tests, audit from day 1, no premature optimization.
**Next step**: Phase 0 — bootstrap of the Phoenix project.
