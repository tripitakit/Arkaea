> 🇮🇹 [Italiano](UI-OPTIMIZATION-PLAN.md) · 🇬🇧 English (this page)

# Arkea UI Optimization — Phased plan for UX, usability, and scientific investigation

## Context

Arkea is today a technically solid simulation, but with an interface that **reveals less than half of what the simulation computes**. Two internal audits have mapped the gap:

1. **UI audit**: missing time-series (populations, metabolites, QS signals), lineage phylogeny, comparative views (seeds/biotopes/replicates), data or snapshot export, consistent navigation (Audit/Seed-Lab links absent from some nav bars), keyboard shortcuts, in-app glossary, and Docs panel content.

2. **Data pipeline audit**: `phase.metabolite_pool`, `phase.signal_pool`, `lineage.biomass`, `lineage.dna_damage`, `atp_yield_by_lineage`, `uptake_by_lineage` are in-memory only. They are **silent** (no events, no persistence): prophage induction, phage infections, R-M digestion, lysis from biomass-deficit, conjugation that does not produce a new lineage. The `audit_log` schema defines types `:mass_lysis`, `:mutation_notable`, `:community_provisioned`, `:mobile_element_release`, `:colonization` — but the sim never writes them.

The target audience is professional biologists and microbiologists: today the product provides a seed-builder plus a live scene, but not a **bench for investigation** where one can formulate hypotheses, observe trajectories, compare replicates, trace provenance, and export results.

User decisions (plan mode):
- **Persistence in scope**: full vertical sim → DB → UI. The plan emits the missing events, snapshots key time-series, and then builds visualizations on top.
- **i18n / a11y out of scope**: focus on information density, navigation, charts, comparison, export.

Expected outcome at plan completion: a microbiologist opens Arkea and can
- view abundance, fitness, and metabolite trajectories over hundreds of ticks;
- navigate lineage genealogy with mutation deltas on the edges;
- reconstruct who-transferred-what-to-whom via HGT (provenance Sankey);
- compare two seeds or two twin biotopes side by side;
- export a biotope snapshot + audit log for offline analysis;
- start from a scenario preset ("contested estuary") without designing a seed from scratch.

---

## Guiding principles (binding for every phase)

- **Pure sim core**: no I/O in `Arkea.Sim.*` modules. Persistence remains delegated to the `Server` via event structs returned by the tick. New events follow this contract.
- **Batch persistence**: time-series writes (e.g. abundance per lineage per tick) are sampled (default every 5 ticks) and batched to avoid DB explosion. Adaptive sampling: high rates → lower frequency; few lineages → higher frequency.
- **Reuse pure-functional views**: new visualizations are pure modules in `Arkea.Views.*`, reusing the pattern already established by `GenomeCanvas`, `BiotopeScene`, `ArkeonSchematic`.
- **SVG-only**: no additional JS chart library. An `Arkea.Views.Chart` helper is introduced with scale/axis/path utilities, reusable by all views.
- **Mandatory tests**: at least 1 snapshot test per new visualization; at least 1 property test (conservation/monotonicity) per new sim event; at least 1 test on a seed dataset per new query.
- **Navigation consistency**: all live views share the same `Shell.shell_nav` items list, derived from a single source.
- **No regressions**: `mix test` stays green after every phase; biotope viewport rendering does not regress >20%; hard cap on path nodes/series.

---

## Phase A — Navigation foundation, help, shortcuts (P0)

**Objective**: make the UI consistent before building on top of it. Low difficulty, high compounding effect.

### Key changes
- `lib/arkea_web/components/shell.ex` — single `nav_items/1` that accepts `active`; all live views call it. Resolves the documented inconsistencies.
- New `lib/arkea_web/components/help.ex` — `<.glossary_term term="kcat" />` with tooltip + link to lateral panel `/help#kcat` (sections from USER-MANUAL.md). Extensible to 30+ biological terms.
- New `lib/arkea_web/live/help_live.ex` — static render of USER-MANUAL.md (and then DESIGN.md) with anchors; replaces the Docs placeholder in the Dashboard.
- Keyboard shortcuts: minimal JS hook in `components/shortcuts.ex`:
  - `/` global search focus; `g d/w/s/c/a` go-to view; `?` cheatsheet.
  - In SimLive: `j/k` lineage prev/next; `1..4` switch tab; `e` events; `i` interventions.
- Cross-linking: every audit row → biotope viewport; community row → founder blueprint; lineage drawer → "audit for this lineage".
- Global search skeleton: `/search?q=...` (minimal live view, populated in later phases).

### Files touched
- New: `components/help.ex`, `components/shortcuts.ex`, `live/help_live.ex`, `live/search_live.ex`.
- Refactor: `components/shell.ex`; all 6 live views modified to consume the unified nav.

### Verification
- All 6 nav-bars show the same 5 links, correct `active` state. Snapshot test per view.
- `?` opens cheatsheet on any view.
- Click on an Audit row navigates to the corresponding biotope.
- `/help` renders the manual in-app, anchors functional.

---

## Phase B — Persistence + event pipeline backfill (P0, blocking)

**Objective**: make the simulation **observable**. Every significant biological mechanism must (a) emit an event or (b) leave a queryable time-series trace. Without this phase, C/D/E are paper.

### Events currently not emitted
- **Silent HGT** in `lib/arkea/sim/hgt.ex`:
  - `:hgt_conjugation_attempt` (even without new lineage; donor/recipient/payload)
  - `:hgt_transformation_event` (uptake from dna_pool)
  - `:hgt_transduction_event` (in phage_infection)
  - `:rm_digestion` (failed R-M check)
  - `:plasmid_displaced` (inc_group incompatibility)
- **Prophage** in `sim/hgt/phage.ex` (BIO Phase 12): `:prophage_induced`, `:phage_infection`, `:phage_decay`.
- **Lysis** in `sim/biomass.ex` or tick step lysis: `:cell_lysis` (per-lineage death count) and `:mass_lysis` when >X% of a phase population dies in one tick.
- **Mutations**: enrich `:lineage_born` with `mutation_summary` (gene_id, kind, fitness_delta) derived from `delta_genome`. Add `:mutation_notable` when the fitness delta exceeds ±20% or touches a key domain.
- **Cross-feeding**: new `:cross_feeding_observed` when lineage A is a net producer of metabolite X and co-resident lineage B is a net consumer (detection over a window of N ticks).
- **Error catastrophe**: `:error_catastrophe_death` (BIO Phase 17).
- **Colonization**: `:colonization` when a lineage migrates into a new biotope and establishes itself (>K cells for >M ticks).

### Snapshotted time-series
- New module `lib/arkea/persistence/time_series.ex` + table `time_series_samples(biotope_id, tick, kind, scope_id, payload jsonb)`. Adaptive sampling with defaults:
  - `:abundance_per_lineage_per_phase` every 5 ticks.
  - `:metabolite_pool_per_phase` every 5 ticks (sampling `phase.metabolite_pool`).
  - `:signal_pool_per_phase` every 5 ticks.
  - `:phenotype_per_lineage` on-change only (delta-encoded).
  - `:dna_damage_per_lineage`, `:biomass_per_lineage` every 10 ticks.
- Sampling rate configurable per biotope; total cap `@samples_per_biotope_cap` (default 10⁵) with pruning of the oldest.

### Audit writer
- Extend `lib/arkea/persistence/audit_writer.ex` for the new event types. Batch insert in transaction, non-blocking for the tick.

### Biotope snapshot
- Extend `Arkea.Persistence.BiotopeSnapshot` with `export/1` (state struct + lineages + phases + metabolites + neighbor edges) as JSON. Reused by user export (Phase F), scientific replay, diff.

### Property tests
- `time_series_test.exs`: sum of sampled abundances ≈ total abundance at the sampling tick.
- `audit_writer_test.exs`: all new events end up in `audit_log` with valid payload.
- `events_silence_test.exs` (StreamData): no sim branch that modifies population remains silent.

### Critical files
- New: `lib/arkea/persistence/time_series.ex`, `priv/repo/migrations/<ts>_create_time_series_samples.exs`, `lib/arkea/sim/event.ex` (canonical event struct).
- Modified: `sim/tick.ex`, `sim/hgt.ex`, `sim/biomass.ex`, `persistence/audit_writer.ex`, `persistence/audit_log.ex` (extend `@event_types`).

### Verification
- Running 100 ticks of a diversified biotope: `audit_log` grows with all new types present at least once; `time_series_samples` grows in a controlled manner (~20–40 rows per 100 ticks with default sampling).
- Replay: loading a snapshot and re-running from a deterministic seed, the post-replay `audit_log` is bit-identical.

---

## Phase C — Time-series visualization core (P0)

**Objective**: the **most missing** visualization. Minimal chart library + three targeted integrations.

### View helpers
- New `lib/arkea/views/chart.ex` (pure): `linear_scale/3`, `log_scale/3`, `path_for_series/2`, `axis_ticks/2`, `band/3`, `marker/2`. SVG only.
- New `lib/arkea_web/components/chart.ex`: `<Chart.line_series />`, `<Chart.heatmap />`, `<Chart.event_markers />`, `<Chart.brushable_axis />`.

### SimLive integrations
1. **Population trajectory** — new "Trends" tab (5th). Stacked area `abundance_per_lineage_per_phase`, vertical markers for `:intervention`/`:mass_lysis`/`:mutation_notable`, brushing on the X axis that re-pivots the other views on the page.
2. **Metabolite pool heatmap** — in Chemistry tab: `metabolite × phase × tick` grid with log scale; tooltip showing exact value. Cross-feeding emerges at a glance (red → green of the same metabolite between adjacent phases).
3. **QS signal trajectory** — in Chemistry tab: lines per signal_key, threshold markers for lineages that "listen" to it (from `phenotype.qs_receives`).

### Enriched lineage drawer
- 200-tick sparkline of the selected lineage's abundance; derived mini-fitness; timeline of received/donated HGT events.

### Performance
- Downsampling if >2000 points: bin by `floor(point / N) * N`. Test that the final rendering does not exceed 2k path nodes per series.

### Files touched
- New: `views/chart.ex`, `components/chart.ex`.
- Modified: `live/sim_live.ex` (tab + drawer), `views/biotope_scene.ex` (event markers).

### Verification
- Open biotope → Trends tab → cumulative trajectories, tooltip on hover, brushing that filters other tabs.
- Snapshot test of SVG structure.

---

## Phase D — Phylogeny / lineage tree (P0)

**Objective**: the single deliverable most requested by biologists and currently absent: who-comes-from-whom.

### Algorithm + view
- New `lib/arkea/views/phylogeny.ex` (pure): from `[Lineage.t()]` with `parent_id` chain → tidy-tree (Reingold-Tilford).
- New `lib/arkea_web/components/phylogeny.ex`: SVG tree with
  - nodes colored by current abundance (extinct = grey + dashed outline)
  - edges labeled with the **mutational delta** (gene_id, kind) derived from the enriched `:lineage_born` event (Phase B)
  - hover on node → mini-card phenotype + abundance sparkline
  - click on node → selects the lineage (reuses SimLive drawer)

### Integration
- New "Phylogeny" tab in SimLive.
- Standalone at `/biotopes/:id/phylogeny` for share-friendly links.

### Filters
- "Show extinct branches", "Only HGT donors", "Color by phenotype trait".

### Property tests
- `phylogeny_test.exs`: the tree covers all lineages (no orphans); every non-founder has exactly 1 valid parent; N nodes → N-1 edges.

### Files touched
- New: `views/phylogeny.ex`, `components/phylogeny.ex`.
- Modified: `live/sim_live.ex` (new tab + route).

### Verification
- On a biotope with 10+ generations: legible rendering, clear mutational edges, extinct lineages visible in grey.

---

## Phase E — HGT ledger + Sankey provenance (P1)

**Objective**: make the horizontal gene flow visible — the narrative core of microbial evolution.

### Changes
- New view `/biotopes/:id/hgt-ledger`:
  - Filterable table: `tick · kind (conjugation/transformation/transduction/phage) · donor → recipient · payload (genes) · effect (Δfitness on recipient)`.
  - Aggregated Sankey diagram (nodes = lineages, size = abundance; edges = HGT events, width = payload count, color = kind).
  - Time-slider to narrow the window.
- New `views/hgt_sankey.ex` (pure): deterministic Sankey layout.

### Cross-linking
- Click on Sankey node → lineage drawer; click on edge → modal "HGT event detail" with gene payload and link "open recipient phylogeny here".

### Audit log integration
- "HGT only" filter in Audit shares the same query as the Sankey, exposed as a reusable internal API.

### Files touched
- New: `views/hgt_sankey.ex`, `components/sankey.ex`, `live/hgt_ledger_live.ex`.

### Verification
- On a stress-test scenario (estuary with mobile plasmids): ledger ≥10 HGT events with correct donor/recipient; Sankey proportional.

---

## Phase F — Compare / iterate / export (P1)

**Objective**: product as a bench for reproducible experiments.

### Seed comparison
- Route `/seed-lab/compare?a=<blueprint_id>&b=<blueprint_id>`:
  - SVG side-by-side of both chromosomes (reuses `GenomeCanvas`).
  - Unified gene-by-gene textual diff (added / removed / domains-changed).
  - Phenotype scalar field diff: table of percentage differences.

### Biotope comparison
- Route `/biotopes/compare?a=<id>&b=<id>`:
  - Overlaid stacked area populations (tick-aligned axis).
  - Phenotype distribution histogram (mean/median/IQR per trait, side-by-side).
  - Audit event diff (unique to A vs unique to B vs common).

### Export
- `GET /api/biotopes/:id/snapshot.json` (reuses `BiotopeSnapshot.export/1`): full state + audit + time-series.
- `GET /api/biotopes/:id/audit.csv` (filterable by tick range, event type).
- `GET /api/blueprints/:id.json`: full blueprint + decoded genome.
- `GET /api/lineages/:id/genome.fasta`: pseudo-FASTA of the genome.
- "Export" button in: SimLive (snapshot), Audit (CSV), SeedLab (blueprint), Phylogeny (Newick).

### Permalinks
- Every stateful view (Audit filters, brush window, lineage selection) reflects state in the URL as query string. "Copy link" copies the full URL.

### Dry-run
- New `Arkea.Sim.DryRun.simulate/3` — runs N ticks of a seed in a target archetype WITHOUT persistence, returns a preview trajectory. Exposed in Seed Lab as "Preview 100 ticks" before submit. Reuses the sim engine with clean state.

### Files touched
- New: `sim/dry_run.ex`, `controllers/api/biotope_controller.ex`, `live/seed_compare_live.ex`, `live/biotope_compare_live.ex`.
- Modified: live views for export buttons + permalink state.

### Verification
- Diff between 2 blueprints shows the introduced mutations; export → re-import (Phase G) reconstructs the state.

---

## Phase G — Onboarding, scenario presets, in-app docs (P2)

**Objective**: lower the floor without raising the ceiling.

### First-run wizard
- `live/onboarding_live.ex` triggered on first session (player with 0 homes): 4-step wizard covering Seed Lab, Sim viewport, Phylogeny, Audit. Skippable.

### Scenario presets
- `Arkea.Game.Scenarios` with pre-loaded presets:
  - "Contested estuary" (narrative from DESIGN_STRESS-TEST.md)
  - "Mutator vs steady" (two twin homes for A/B)
  - "Antibiotic challenge" (requires BIO Phase 15)
  - "Cross-feeding bloom"
- "Load scenario..." button in Seed Lab that pre-fills the form and (optionally) directly creates the expected 2-3 biotopes.

### Docs panel content
- Dashboard "Docs" placeholder now links to:
  - `/help/user-manual` (USER-MANUAL rendered inline, indexed)
  - `/help/design` (DESIGN rendered for those who want the biological model)
  - `/help/calibration` (calibration ranges, literature references)
  - `/help/api` (Phase F endpoints documented)
- Global glossary search: `/help/glossary?q=kcat` cross-doc.

### Notifications (in-tab toast)
- Toast when an event of interest (`:mass_lysis`, `:error_catastrophe_death`) occurs in an owned biotope. Toggle on/off per category. Rate cap (max 1 toast / 30s).

### Files touched
- New: `live/onboarding_live.ex`, `game/scenarios.ex`, `live/help/*`.
- Modified: `live/dashboard_live.ex` (Docs panel), `live/seed_lab_live.ex` (load scenario).

### Verification
- New player sees onboarding on first login.
- "Load scenario: Contested estuary" provisions 3 correct biotopes and navigates to the first.
- `/help/glossary?q=kcat` shows the entry.

---

## Execution sequence

```
A (foundation) ────────────────┐
                               ↓
B (persistence backfill) ──────┼─→ C (time-series viz) ─→ D (phylogeny) ─→ E (HGT ledger)
                               │                                                      ↓
                               └─→ F (compare/export/dry-run) ──→ G (onboarding/docs)
```

- **A** is prerequisite for everything (unified nav, base help, shortcut framework).
- **B** blocks C/D/E (data without persistence = empty charts).
- **C** enables the sparklines in D's drawer.
- **E** depends on B (enriched HGT events).
- **F** depends on E (export includes HGT ledger) and on B (complete snapshot).
- **G** comes last: uses everything as building blocks.

Estimated time: ~6 weeks sequential dev, ~4 with C/D in parallel and F/G in parallel.

---

## Files touched (summary)

### New pure modules
- `lib/arkea/views/chart.ex`, `views/phylogeny.ex`, `views/hgt_sankey.ex`
- `lib/arkea/persistence/time_series.ex` (extension of `BiotopeSnapshot` for export/import)
- `lib/arkea/sim/event.ex`, `sim/dry_run.ex`
- `lib/arkea/game/scenarios.ex`

### New web components
- `components/help.ex`, `components/shortcuts.ex`, `components/chart.ex`, `components/sankey.ex`, `components/phylogeny.ex`

### New live views / controllers
- `live/help_live.ex`, `live/search_live.ex`, `live/seed_compare_live.ex`, `live/biotope_compare_live.ex`, `live/hgt_ledger_live.ex`, `live/onboarding_live.ex`, `controllers/api/biotope_controller.ex`

### Modified
- All 6 existing live views (unified nav, cross-linking, permalink state)
- `sim/tick.ex`, `sim/hgt.ex`, `sim/biomass.ex`, `sim/metabolism.ex` (missing events)
- `persistence/audit_log.ex`, `persistence/audit_writer.ex` (new event types)

### Migrations
- `<ts>_create_time_series_samples.exs`
- `<ts>_extend_audit_log_event_types.exs`

---

## End-to-end verification

Per phase:
1. **Green tests**: `mix test` stays green, snapshot test for every new view, property tests for persistence/events.
2. **Performance**: biotope viewport rendering with 50 active lineages does not regress (>20% slowdown = stop).
3. **Manual demo**: for each feature a "demo path" reproducible in the browser, written in the PR description.
4. **Reproducibility**: snapshot export → re-import → diff = 0 bytes.

Final end-to-end: the "Contested estuary" scenario (Phase G preset) must produce a biotope where the microbiologist can
- view the abundance curve with `:mass_lysis` markers (Phase B+C);
- open the phylogeny and trace which lineage donated the resistance plasmid (D+E);
- export audit log + snapshot for offline analysis (F);
- compare two replicates of the scenario (F).

---

## Risks and mitigations

- **DB explosion from time-series**: cap + adaptive sampling + pruning. Validated with benchmark at 1000 ticks × 50 lineages.
- **Chart rendering performance**: downsampling + virtualization; cap on path nodes per series.
- **Combinatorial test surface**: StreamData factories (e.g. `HGTSituation.build/1`) for reproducible scenarios.
- **Docs/UI drift**: each phase updates USER-MANUAL.md + USER-MANUAL.en.md (via `bilingual-docs-maintainer` agent).
- **Coupling with BIOLOGICAL-MODEL-REVIEW**: some events (`:error_catastrophe_death`, `:mass_lysis` from biomass) depend on Phases 14/17 of that plan. For each, a graceful fallback is specified (no-op if the sim source is not yet activated): the UI shows "Source not available yet" instead of crashing.

---

## Expected end-to-end deliverables

- Consistent navigation, in-app glossary, keyboard shortcuts, global search.
- Time-series persisted for every biotope (populations, metabolites, signals, biomass, dna_damage).
- Complete audit events: HGT (4 channels) + R-M + lysis + notable mutations + colonization + cross-feeding + error catastrophe.
- Time-series visualization: population trajectory, metabolite heatmap, signal trajectory.
- Phylogeny rendered with mutational deltas on edges.
- HGT ledger + provenance Sankey.
- Diff between seeds and between biotopes, side by side.
- JSON/CSV/FASTA/Newick export.
- Permalink state for every view.
- Seed dry-run preview.
- Onboarding wizard, scenario presets, populated docs panel, notifications.
