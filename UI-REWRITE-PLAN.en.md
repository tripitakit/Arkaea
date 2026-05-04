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

**Circular chromosome (SVG)**:

- Main circle; genes as colored arcs distributed along the circumference.
- Each gene is a sub-arc; domains are mini concentric rectangles toward the center (domain crown).
- Click on a gene → highlight + populates Inspector.
- Drag a domain: reorder within the same gene; drop on another gene → move; drop outside → removal (with confirmation).
- Intergenic biases between genes shown as "ticks" on the outer ring.
- Plasmids below as smaller circles (same scheme, scale 0.6×).

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

| Phase | Scope | Output |
|---|---|---|
| **U0** | Shell + tokens + `panel`/`metric` components | Shared shell, clean CSS base |
| **U1** | Dashboard as new landing | `/dashboard`, post-login redirect |
| **U2** | World view migrated to Shell + full-bleed SVG | Contextual right sidebar |
| **U3** | Biotope SVG scene (replaces Pixi) | `pixi.js` removed from `package.json` |
| **U4** | Biotope view: drawer + bottom tabs | `SimLive` layout replacement |
| **U5** | SeedLab circular chromosome + domain DnD | `DomainDnD` hook (≤120 lines) |
| **U6** | Audit + Community views | Paginated stream |
| **U7** | CSS cleanup + dead code removal | `app.css` split into modules |

Each phase: tests green (including `mix test`), no manual visual regression, isolated commit.

---

## Critical files touched (summary)

- `lib/arkea_web/router.ex` — new route `/dashboard`, post-login redirect.
- `lib/arkea_web/components/layouts/root.html.heex` — loading of new CSS files.
- `lib/arkea_web/components/layouts.ex` — `app` layout with `<.shell>`.
- `lib/arkea_web/live/dashboard_live.ex` — **new**.
- `lib/arkea_web/live/world_live.ex` — full refactor to Shell + VM.
- `lib/arkea_web/live/seed_lab_live.ex` — full refactor: circular chromosome, DnD, inspector.
- `lib/arkea_web/live/sim_live.ex` — full refactor: SVG scene, drawer, bottom tabs.
- `lib/arkea_web/live/community_live.ex` — **new** (read-only).
- `lib/arkea_web/live/audit_live.ex` — **new**.
- `lib/arkea_web/components/` — new components (see dedicated section).
- `lib/arkea/views/` — new pure VMs (`WorldVM`, `BiotopeVM`, `SeedVM`).
- `assets/js/app.js` — removal of Pixi `BiotopeScene`, addition of `SvgPanZoom`, `DomainDnD`.
- `assets/js/hooks/` — removal of `biotope_scene.js`, addition of `svg_pan_zoom.js`, `domain_dnd.js`.
- `assets/css/` — modular split of `app.css`.
- `assets/package.json` — removal of `pixi.js`.

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

## Expected final outputs at plan completion

- Dashboard as post-login landing with 6 card-link panels.
- 4 dedicated full-page views (`/world`, `/seed-lab`, `/biotopes/:id`, `/community`, `/audit`) without global scrollbars.
- Genome visualized as a circular chromosome with domains reorderable via DnD (with a11y fallback).
- PixiJS removed; 100% LiveView/SVG rendering.
- JS bundle < 200 KB.
- Modularized CSS (`tokens.css` + component files) under the single `arkea-` prefix.
- View-model layer tested independently from LiveViews.
- Full coherence with DESIGN.md (Blocks 12 and 14 — visualization and UI).
