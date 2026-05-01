> 🇮🇹 [Italiano](IMPLEMENTATION-PLAN.md) · 🇬🇧 English (this page)

# Arkea — Implementation plan (high level)

**References**: [DESIGN.en.md](DESIGN.en.md), [DESIGN_STRESS-TEST.en.md](DESIGN_STRESS-TEST.en.md)
**Date**: 2026-04-26
**Status**: Phase 0 ✅ · Phase 1 ✅ · Phase 2 ✅ · Phase 3 ✅ · Phase 4 ✅ · Phase 5 ✅ · Phase 6 ✅ · Phase 7 ✅ · Phase 8 ✅ · (see §1bis).

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

> Updated: 2026-05-01.

Completed phases on `master` as of 2026-05-01:
- Phase 0: Bootstrap Phoenix scaffold (commit `86a3ef2`)
- Phase 1: Core data model + Ecto schemas + property tests (commit `142b4aa`)
- Phase 2: Dilution + environment step
- Phase 3: Gene expression + phenotype
- Phase 4: Stochastic fission + pruning
- Phase 5: Michaelis-Menten metabolism
- Phase 6: HGT + mobile elements — conjugation, prophage induction, plasmid cost (commit `7491a3f`)
- Phase 7: Quorum sensing & signaling (commit `a9adab8`)
- Phase 8: Migration + biotope network topology (commit `TBD`)

### Phase 8 — Migration + network topology ✅ completed (commit `TBD`)

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

---

## 2. Main architectural choice

### 2.1 Decision

**Active Record pattern (BEAM-canonical)** for state management and tick, with two **structural caveats** that mitigate the pattern's weaknesses and keep open a path for future evolution.

**Model**:
- One `Biotope.Server` GenServer per biotope. State (lineages, phases, metabolites, signals, free phages) lives **in the process's memory**, in Elixir structs.
- The tick is a **pure function** `tick(state) -> {new_state, events}`, applied sequentially by the GenServer. Internally parallelizable per phase via `Task.async_stream` when profiling justifies it.
- **Inter-biotope migration** is orchestrated by the `Migration.Coordinator` after each global tick: `Phoenix.PubSub` barrier on `world:tick`, fetch of current states, pure transfer planning, and per-biotope apply.
- **Persistence** is a periodic snapshot via Oban worker (every 10 ticks = 50 real minutes, from Block 11).

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
├── Persistence.Snapshot (Oban worker, every 10 ticks: serialize state)
├── Persistence.AuditLog (insert on relevant events table, transactional)
└── Persistence.Recovery (at boot: rebuilds state from latest snapshot)
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
  AuditLog.persist(events)
  PubSub.broadcast(Topic.biotope(state.id), {:tick, new_state, events})
  Snapshot.maybe_persist(new_state)
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
| **9. UI: LiveView + PixiJS Hook** | 2D biotope view (procedural rendering), dashboard, event log, intervention controls | Anna of the use case can access via browser and see her own biotope | 12, 14 |
| **10. Complete persistence** | Snapshot every 10 ticks + audit log + recovery | Deliberate crash → restart → state preserved up to recent WAL | 11, 13, 14 |
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
