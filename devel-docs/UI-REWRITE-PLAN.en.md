> [🇮🇹 Italiano](UI-REWRITE-PLAN.md) · 🇬🇧 English (this page)

# Arkea UI/UX Rewrite — Design Plan

## Context

The current interface (at the end of phase 20) is functional but has grown organically:

- 3 LiveViews with heavy inline `~H`: `WorldLive` (314 lines), `SeedLabLive` (1473 lines), `SimLive` (1316 lines).
- 1 PixiJS hook (`BiotopeScene`, 497 lines) for the biotope scene, the only relevant JS dependency (`pixi.js`).
- Monolithic `app.css` at 2063 lines, mixed `sim-*`/`world-*`/`seed-*` naming.
- Layout: `GameChrome.top_nav` as shared header, no formalized dashboard/sidebar layout.
- Global scrollbars present on multiple pages, uneven information density.

The goal is a rewrite consistent with the target audience (biologists/microbiologists/molecular biologists): high information density, panel-based navigation that opens full-page views, 100% LiveView rendering (PixiJS removal), and genome visualization as a **circular chromosome** with visually reorderable domains.

**Confirmed user decisions**:

1. Handcrafted CSS (no Tailwind).
2. Dashboard as post-login landing.
3. Drag-and-drop as primary mechanism for domain reordering, with ↑/↓/× button fallback for accessibility.
4. Plan persisted as a versioned bilingual document in the project root.

---

## Guiding principles (binding for every phase)

1. **Server-authoritative + LiveView-native**. All rendering is HEEx/SVG/CSS. JS hooks only for: pan/zoom on SVG, domain drag-and-drop, resize observer, scroll-into-view for virtual lists. **No canvas/WebGL library.**
2. **No global scrollbar**. The page fills the viewport (`height: 100dvh`, `overflow: hidden` on the shell). Scrolling exists only inside panels/lists with explicit `overflow: auto` and a thin styled scrollbar.
3. **Information density, no decorative chrome**. Eyebrow + title + subtitle, no gradient hero. Target audience: scientific.
4. **Dashboard → full-page view**. Each dashboard panel is a summary + entry point; clicking opens the dedicated view at its dedicated route (`/world`, `/seed-lab`, `/biotopes/:id`, `/community`, `/audit`).
5. **Composability via slots**. A single `<.shell>` (header + optional sidebar + main) and a set of declarative components: `<.panel>`, `<.panel_header>`, `<.panel_body scroll>`, `<.metric_strip>`, `<.data_table>`, `<.empty_state>`. Eliminate the current markup duplication across the 3 LiveViews.
6. **Data decoupling**. Each LiveView consumes a `view-model` struct (e.g. `BiotopeViewModel`) built by a pure function `to_view/1`. Render without calling `Phenotype`/`Lineage` directly. Improves HEEx testability.
7. **A11y/keyboard-first**. All panels are keyboard-navigable. No feature depends exclusively on the mouse (drag-and-drop always has a button fallback).

---

## PixiJS removal — 2D rendering strategy

The biotope panel currently shows: phase-stripe backgrounds, lineage particles (radius ∝ abundance fraction), metabolite bubbles, event ticker. Nothing above ~200 simultaneous entities, no real physics animation. **WebGL is not needed.**

Replacement: `BiotopeScene` as a HEEx component that emits **a single SVG** with:

- `<rect>` elements for phase stripes (gradients defined in `<defs>`),
- `<circle>` for each lineage (cap ~60/phase, deterministically positioned from `lineage.id` hash),
- `<g>` for metabolite pools (mini-bar to the right of each stripe),
- transitions with `style="transition: r 200ms, cy 200ms"` for particles whose abundance changes.

**Advantages**:

- 100% server-side state, snapshots via LV diffing (we already have `assign_scene_snapshot`).
- Click on `<circle>` → `phx-click` with `lineage_id` → opens inspector side-drawer without JSON serialization.
- Removal of `pixi.js` (-500 KB bundle); `package.json` reducible to `phoenix`/`phoenix_html`/`phoenix_live_view`.

Residual JS hook `SvgPanZoom` (≤80 lines): listens for wheel/drag, applies `transform: matrix(...)` to the biotope's root `<g>`. No WebGL, no Pixi.

**Performance mitigation**: cap at 60 particles/phase (already enforced in Pixi); denser phases aggregate into "stacks" + counter, click expands. For N > 200 total lineages the scene still has more than sufficient rendering budget with native SVG (modern browsers handle thousands of SVG nodes with `will-change: transform`).

---

## Layout system

```
┌─────────────────────────────────────────────────────────────┐
│ TopBar:  [logo] Dashboard · World · SeedLab · Audit  [user] │ ← 48px
├──────────┬──────────────────────────────────────────────────┤
│          │                                                  │
│ Sidebar  │                  Main view                       │ ← flex: 1
│  (opt)   │                  (no global scroll)              │
│  240px   │                                                  │
│          │                                                  │
└──────────┴──────────────────────────────────────────────────┘
```

- `Layouts.app` replaces `GameChrome.top_nav` (keep during migration, then remove).
- Optional sidebar: present in `SeedLabLive` (replicon list), `SimLive` (phase list); absent in `WorldLive`/`Dashboard`.
- Viewport: `height: 100dvh; display: grid; grid-template-rows: 48px 1fr; overflow: hidden`.

---

## View by view

### Dashboard (`/dashboard` — new, post-login landing)

2×3 grid of "card-link" panels (click → dedicated view):

| Panel | Content | Opens |
|---|---|---|
| **World** | SVG mini-graph of active biotopes + count | `/world` |
| **Seed Lab** | preview of the player's current seed + lock status | `/seed-lab` |
| **My Biotopes** | compact list of own biotopes + tick | `/biotopes/:id` |
| **Community** | top 3 communities from other players (read-only) | `/community` |
| **Audit / Events** | stream of the last 10 global events | `/audit` |
| **Calibration** | static links (`CALIBRATION.md`, `DESIGN.md`, `BIOLOGICAL-MODEL-REVIEW.md`) rendered as HTML | `/docs/:slug` |

### World view (`/world`)

```
┌──────────────────────┬───────────────────┐
│                      │  Selected biotope │
│   World graph        │  ─────────        │
│   (SVG, full-bleed)  │  archetype        │
│   pan/zoom           │  tick / lineages  │
│                      │  metabolite mix   │
│                      │  [Open biotope →] │
└──────────────────────┴───────────────────┘
```

- Replace the current `world-map` with a full-bleed SVG (no scrollbar).
- Contextual side-panel on the right (320 px): selected biotope info, primary CTA.
- Filters (mine/wild/all) as inline tabs, no modal.

### Seed Lab (`/seed-lab`) — the most redesigned view

3-column layout:

```
┌────────────┬──────────────────────────────┬─────────────┐
│ Sidebar    │  Genome canvas               │ Inspector   │
│ ────────── │  (chromosome + plasmids)     │ (selected)  │
│            │                              │             │
│ Replicons  │   ┌──────────────────┐       │ Domain list │
│  ▸ chrom   │   │   ╱ Gene 1 ╲     │       │ Phenotype   │
│  ▸ plasm 1 │   │  │  G3   G2  │   │       │ effects     │
│  ▸ plasm 2 │   │   ╲ Gene 4 ╱     │       │             │
│            │   └──────────────────┘       │             │
│ + add      │   chromosome (circular)      │             │
│            │                              │             │
│ ────────── │   [plasmid 1]  [plasmid 2]   │             │
│ Phenotype  │                              │             │
│ targets    │                              │             │
│            │                              │             │
└────────────┴──────────────────────────────┴─────────────┘
```

**Circular chromosome (SVG)** *(U5 design + post-merge revision)*:

- Closed ring; **genes are contiguous segments of the ring itself**, separated by a small fixed gap (~0.012 rad ≈ 0.7°) regardless of gene count.
- **Domains** are **side-by-side angular sub-arcs** inside the gene's segment, each spanning the full radial thickness (`r_inner..r_outer`). No concentric crown: the gene's detail lives on the ring itself, read as a sequence of coloured sub-segments by domain type.
- Click on a gene → highlight (solid outline) + populates Inspector.
- Drag a domain (post-MVP, JS hook): reorder within the same gene; drop on another gene → move; drop outside → removal (with confirmation).
- Intergenic biases between genes: `data-*` attributes for analytic compositions; in a future iteration they may be exposed as radial "ticks" in the middle of the gap.
- Plasmids below as smaller circles (same scheme, scale 0.6×).

> **History**: the first iteration (commit U5 `bf6576f`) used a concentric domain crown. The representation was revised post-merge for consistency with the mental model "the chromosome is the sequence of its genes": domains are now *parts* of the gene-segment, not a separate decorative layer.

**Drag-and-drop hook** (`DomainDnD`, ≤120 JS lines): `pointerdown` on domain → registers; `pointermove` → live position; `pointerup` on drop target → `pushEvent("reorder_domain", {...})`. All final state is server-side.

**A11y fallback**: each domain has ↑/↓/× buttons always visible (not only on drag). Tab-navigable, keyboard-activatable. Consistent with guiding principle #7.

**Phenotype panel**: derived in real time from `Phenotype.from_genome`. Shows the 11 traits (kcat, repair, growth rate, surface tags, etc.) as colored horizontal bars. Tooltip on each explains "derived from X domains of type Y".

### Biotope view (`/biotopes/:id`)

3-zone layout:

```
┌────────────────────────────────────────────────┐
│ Header: archetype · tick · running · controls  │
├──────────────┬────────────────┬────────────────┤
│              │                │                │
│  Phase list  │  Scene (SVG)   │ Lineage drawer │
│  (sidebar)   │  pan/zoom      │  (slide-in)    │
│              │                │                │
│  ▸ surface   │                │ on click       │
│  ▸ deep      │                │ on circle      │
│              │                │                │
├──────────────┴────────────────┴────────────────┤
│ Bottom tabs: Events · Lineages · Metabolites   │ ← 200 px
│ (tabbed panel, scroll inside body)             │
└────────────────────────────────────────────────┘
```

- `BiotopeScene` as SVG (replaces Pixi).
- Click on lineage circle → right drawer (375 px) with phenotype detail, link to "Open in SeedLab" (read-only inspector).
- Fixed bottom tab bar, tab body scrolls vertically only within itself.
- Player interventions as floating action button + modal dialog (no long inline form as today).

### Community (`/community`)

Public list of community-mode runs (phase 19). Identical structure to `/world`, but read-only and sortable by diversity metrics.

### Audit (`/audit`)

Global event stream: server-side paginated table, filters by event type (HGT, mutation, lysis, etc.). Sub-panel scroll, main page fixed.

---

## Components to create/refactor

In `lib/arkea_web/components/`:

- `shell.ex` — `<.shell>`, `<.shell_header>`, `<.shell_sidebar>`, `<.shell_main>` (slot-based).
- `panel.ex` — `<.panel>`, `<.panel_header>`, `<.panel_body scroll/no_scroll>`.
- `metric.ex` — `<.metric_chip>`, `<.metric_strip>`, `<.metric_bar>` (replaces the duplicated `stat_chip` elements across the 3 views).
- `data_table.ex` — table with sort, sticky header, optional virtual scroll.
- `genome_canvas.ex` — SVG render of chromosome/plasmids + inspector hooks.
- `biotope_scene.ex` — SVG replacement for Pixi.
- `world_graph.ex` — SVG with pan/zoom.
- `drawer.ex` — right slide-in panel, close with Esc.
- `empty_state.ex` — consistent placeholder for empty lists.

`core_components.ex` stays only for default Phoenix components (input, button, errors).

---

## CSS — refactor

- Progressive migration from the monolithic `app.css` (2063 lines) to a set of files in `assets/css/`:
  - `tokens.css` (colors, spacing, type scale, z-index).
  - `shell.css` (root layout).
  - `panel.css`, `metric.css`, `table.css`, `drawer.css`, `genome.css`, `scene.css`.
  - `app.css` as `@import` only.
- CSS custom properties for theming; **handcrafted CSS, no Tailwind** (confirmed decision).
- Naming: `arkea-` prefix instead of the mixed `sim-`/`world-`/`seed-`.

---

## View-model layer

New pure modules in `lib/arkea/views/`:

- `Arkea.Views.WorldVM` — `to_view(world_overview)` → struct with pre-formatted fields.
- `Arkea.Views.BiotopeVM` — `to_view(BiotopeState.t())` → `scene_snapshot`, `lineage_rows`, `metabolite_rows`.
- `Arkea.Views.SeedVM` — `to_view(seed_form)` → `genome_layout` (circles, arcs, domains with pre-calculated coordinates).

HEEx renders consume only VMs. Unit tests on VMs (no coupling with LV).

---

## Migration phases

| Phase | Commit | Scope | Output |
|---|---|---|---|
| **U0** | `1643016` | Shell + tokens + `panel`/`metric` components | Shared shell, clean CSS base |
| **U1** | `a6d9cc2` | Dashboard as new landing | `/dashboard`, post-login redirect |
| **U2** | `471ab2a` | World view migrated to Shell + full-bleed SVG | Contextual right sidebar |
| **U3** | `0ba7f25` | Biotope SVG scene (replaces Pixi) | `pixi.js` removed from `package.json` |
| **U4** | `6c55626` | Biotope view: drawer + bottom tabs | `SimLive` layout replacement |
| **U5** | `bf6576f` | SeedLab circular chromosome + domain DnD (a11y-first ↑/↓/×) | DnD JS hook deferred |
| **U6** | `5549e9a` | Audit + Community views | LiveView on `audit_log` |
| **U7** | `a4c58c8` | CSS cleanup + dead code removal | `app.css` 2076 → 119 lines |
| **U7+** | `67fe68a` | Full `legacy.css` → `arkea/inner.css` migration | Entire namespace `arkea-*`, −510 dead lines |

Each phase: tests green (including `mix test`), no manual visual regression, isolated commit.

### Final state

- **9 commits** (U0..U7+) merged on `master`.
- **429 tests / 0 failures** (was 374/5 at the start of the rewrite — the 5 pre-existing failures were resolved as a side effect).
- **JS bundle with PixiJS removed**: `priv/static/assets/app.js` < 50 KB (was ~600 KB with Pixi).
- **Modular CSS** in `assets/css/arkea/`: `tokens.css`, `shell.css`, `panel.css`, `metric.css`, `dashboard.css`, `world.css`, `scene.css`, `biotope.css`, `seed_lab.css`, `audit.css`, `inner.css`. `app.css` reduced to 119 lines (Tailwind config + imports).
- **No legacy selectors** (`sim-*`/`seed-*`/`world-*`/`biotope-*`/`game-nav-*`/`access-*`) in HEEx files; everything under the `arkea-*` prefix.

---

## Critical files touched (final summary)

### LiveView

- `lib/arkea_web/live/dashboard_live.ex` — **new**: 6 card-link panels.
- `lib/arkea_web/live/audit_live.ex` — **new**: paginated stream of `audit_log` with filter tabs.
- `lib/arkea_web/live/community_live.ex` — **new**: community-mode run list (read-only).
- `lib/arkea_web/live/world_live.ex` — full refactor to Shell + full-bleed SVG + side panels.
- `lib/arkea_web/live/seed_lab_live.ex` — refactor: shell + circular chromosome + domain drafting with ↑/↓/×.
- `lib/arkea_web/live/sim_live.ex` — full refactor: shell + phase sidebar + SVG scene + drawer + bottom tabs.

### Reusable components

- `lib/arkea_web/components/shell.ex` — **new**: `<.shell>`, `<.shell_brand>`, `<.shell_nav>`, `<.shell_user>`.
- `lib/arkea_web/components/panel.ex` — **new**: `<.panel>` with header/body/footer slots + `<.empty_state>`.
- `lib/arkea_web/components/metric.ex` — **new**: `<.metric_strip>`, `<.metric_chip>`, `<.metric_bar>` (replaces `stat_chip`).
- `lib/arkea_web/components/biotope_scene.ex` — **new**: SVG biotope scene (replaces Pixi hook).
- `lib/arkea_web/components/genome_canvas.ex` — **new**: circular chromosome SVG. Genes are contiguous ring segments; domains are side-by-side angular sub-arcs inside each gene segment (full radial thickness, not concentric). See "Seed Lab" section for design rationale.
- `lib/arkea_web/components/layouts.ex` — slimmed: only `flash_group/1` (scaffold `app/1` + `theme_toggle` removed).

### Pure view-models (testable without LV)

- `lib/arkea/views/biotope_scene.ex` — **new**: SVG biotope layout (`build/1` from snapshot).
- `lib/arkea/views/genome_canvas.ex` — **new**: SVG genome layout (`build/1` from preview, `from_preview/1`).

### Routing

- `lib/arkea_web/router.ex` — added routes `/dashboard`, `/audit`, `/community`.
- `lib/arkea_web/player_auth.ex` + `lib/arkea_web/controllers/player_access_controller.ex` — post-login redirect to `/dashboard` (was `/world`).

### Assets

- `assets/css/app.css` — reduced from 2076 to 119 lines (Tailwind/DaisyUI/heroicons only + module imports).
- `assets/css/arkea/` — **new directory** with 11 modules: `tokens.css`, `shell.css`, `panel.css`, `metric.css`, `dashboard.css`, `world.css`, `scene.css`, `biotope.css`, `seed_lab.css`, `audit.css`, `inner.css`.
- `assets/js/app.js` — `BiotopeScene` hook (Pixi) removed.
- `assets/js/hooks/biotope_scene.js` — **deleted** (497 lines).
- `assets/package.json` — `pixi.js` removed. Dependencies are now `{}`.

### Removed scaffold code

- `lib/arkea_web/game_chrome.ex` — deleted (replaced by `<.shell>` + `<.shell_nav>`).
- `lib/arkea_web/controllers/page_controller.ex` + `page_html.ex` + `page_html/home.html.heex` — deleted (Phoenix scaffold, not wired).
- `Layouts.app/1` + `Layouts.theme_toggle/1` — deleted (unused scaffold).
- Inline theme-toggle script in `root.html.heex` — deleted.

---

## End-to-end verification

For each phase:

1. **`mix test` green** after every phase.
2. **LiveView tests**: `Phoenix.LiveViewTest` on `mount`, `handle_event` for drag/drop, drawer open/close.
3. **VM tests**: pure unit tests on `Arkea.Views.*`.
4. **Manual smoke**: every view at 1280×720 and 1920×1080, no global scrollbar, all interactions keyboard-accessible.
5. **Bundle size**: `priv/static/assets/app.js` < 200 KB after Pixi removal (currently ~600 KB).
6. **A11y**: full keyboard navigation, ↑/↓/× fallback for domain reordering always available.

---

## Risks and mitigations

- **SVG performance with N > 200 lineages**: Pixi is faster at 1000+ entities. Mitigation: cap at 60 particles/phase + aggregation stacks for density; CSS `will-change: transform` on animated `<g>` elements.
- **Drag-and-drop on SVG**: complex but feasible with pointer events. Fallback already planned (↑/↓/× buttons).
- **State lock during genome editing**: already present (`seed_locked?`), confirm semantics in the new flow.
- **Routing**: add `/dashboard` as default; modify login redirect without breaking existing bookmarks (keep `/world` accessible).
- **Refactor of long files (`SeedLabLive` 1473, `SimLive` 1316)**: risk of regressions during VM extraction. Mitigation: VMs tested first, render migrated in small steps, HEEx snapshot tests where possible.

---

## Plan persistence in the repository

The plan is reified as a **versioned bilingual document in the project root**, conforming to the existing convention (`DESIGN.md` / `DESIGN.en.md`, `BIOLOGICAL-MODEL-REVIEW.md` / `BIOLOGICAL-MODEL-REVIEW.en.md`, `CALIBRATION.md` / `CALIBRATION.en.md`):

- **`UI-REWRITE-PLAN.md`** — Italian, canonical (source of truth). Header with language switcher.
- **`UI-REWRITE-PLAN.en.md`** — synchronized English translation. Mirror header.

The English translation is created and kept in sync by the `bilingual-docs-maintainer` agent.

Update of `README.md` and `README.en.md` in the "Documents" section to link the new doc.

---

## Final outputs (delivered)

- ✅ Dashboard as post-login landing with 6 card-link panels (3 live, 3 read-only).
- ✅ 5 dedicated full-page views (`/world`, `/seed-lab`, `/biotopes/:id`, `/community`, `/audit`) without global scrollbars.
- ✅ Genome visualized as a circular chromosome SVG. Genes are segments of the ring itself; domains are coloured sub-arcs side-by-side inside the gene (post-merge revision of the first iteration that used a concentric crown). Domain reordering via ↑/↓/× (a11y-first; DnD JS hook deferred as an additive enhancement).
- ✅ PixiJS removed; 100% LiveView/SVG rendering.
- ✅ JS bundle < 50 KB (target was < 200 KB).
- ✅ CSS modularized into 11 modules under the `arkea-*` prefix. No legacy classes `sim-*`/`seed-*`/`world-*`/`biotope-*` remaining in the codebase.

## Undelivered scope (additive follow-up)

- **JS DnD hook** for visual reordering of domains directly on the SVG chromosome. The ↑/↓/× a11y fallback is the current primary mechanism (fully keyboard-accessible). The hook remains optional.
- **`/docs/:slug`** for Markdown rendering of canonical docs (DESIGN, CALIBRATION, etc.). Would require `Earmark`. The Docs panel on the dashboard is still a placeholder.
- **DaisyUI removal**: the Tailwind plugin is still loaded (`assets/css/app.css`). It can be removed after migrating `core_components.ex` flashes (`alert-error`, `alert-info`, `text-error`) and the default Phoenix `.input` button (`btn-primary`) to arkea CSS.
- **Full split of `arkea/inner.css` modules**: the inner panel layer (1468 lines) has been renamed to `arkea-*` but remains in a single file. Splitting per surface (login/biotope-inner/seed-lab-inner) is residual, non-blocking work.
- View-model layer tested independently from LiveViews.
- Full coherence with DESIGN.md (Blocks 12 and 14 — visualization and UI).
