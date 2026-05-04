> 🇮🇹 Italiano (questa pagina) · [🇬🇧 English](UI-REWRITE-PLAN.en.md)

# Riscrittura UI/UX di Arkea — Piano di design

## Contesto

L'attuale interfaccia (al termine di Fase 20) è funzionale ma cresciuta in modo organico:

- 3 LiveView con `~H` inline pesante: `WorldLive` (314 righe), `SeedLabLive` (1473 righe), `SimLive` (1316 righe).
- 1 hook PixiJS (`BiotopeScene`, 497 righe) per la scena del biotopo, unica dipendenza JS rilevante (`pixi.js`).
- `app.css` monolitico da 2063 righe, naming misto `sim-*`/`world-*`/`seed-*`.
- Layout: `GameChrome.top_nav` come header condiviso, nessun layout dashboard/sidebar formalizzato.
- Scrollbar globali presenti in più pagine, densità informativa disomogenea.

L'obiettivo è una riscrittura coerente con il pubblico target (biologi/microbiologi/biologi molecolari): densità informativa elevata, navigazione a pannelli che aprono viste a pagina intera, rendering 100% LiveView (rimozione di PixiJS) e visualizzazione del genoma come **cromosoma circolare** con domini riorganizzabili visualmente.

**Decisioni utente confermate**:

1. CSS handcrafted (no Tailwind).
2. Dashboard come landing post-login.
3. Drag-and-drop primario per il riordino dei domini, fallback con pulsanti ↑/↓/× per accessibilità.
4. Piano persistito come documento bilingue versionato in root.

---

## Principi guida (vincolanti per ogni fase)

1. **Server-authoritative + LiveView-native**. Tutto rendering è HEEx/SVG/CSS. JS hooks solo per: pan/zoom su SVG, drag-and-drop di domini, resize observer, scroll-into-view per liste virtuali. **Nessuna libreria di canvas/WebGL.**
2. **No scrollbar globale**. La pagina riempie la viewport (`height: 100dvh`, `overflow: hidden` sul shell). Lo scroll esiste solo dentro pannelli/liste con `overflow: auto` esplicito e una scrollbar stilizzata sottile.
3. **Densità informativa, no chrome decorativo**. Eyebrow + titolo + sub-titolo, nessun gradient hero. Pubblico target: scientifico.
4. **Dashboard → vista a pagina intera**. Ogni pannello dashboard è un riassunto + entry point; il click apre la vista dedicata in routing dedicato (`/world`, `/seed-lab`, `/biotopes/:id`, `/community`, `/audit`).
5. **Componibilità via slot**. Un solo `<.shell>` (header + sidebar opzionale + main) e un set di componenti dichiarativi: `<.panel>`, `<.panel_header>`, `<.panel_body scroll>`, `<.metric_strip>`, `<.data_table>`, `<.empty_state>`. Eliminare la duplicazione attuale di markup tra le 3 LiveView.
6. **Disaccoppiamento dati**. Ogni LiveView consuma una `view-model` struct (es. `BiotopeViewModel`) costruita da una funzione pura `to_view/1`. Render senza chiamare `Phenotype`/`Lineage` direttamente. Migliora testabilità HEEx.
7. **A11y/keyboard-first**. Tutti i pannelli sono navigabili con tastiera. Nessuna feature dipende esclusivamente dal mouse (drag-and-drop ha sempre un fallback con pulsanti).

---

## Rimozione PixiJS — strategia rendering 2D

Il pannello biotopo oggi mostra: sfondi a fasce per fase, particelle per lineage (raggio ∝ frazione di abbondanza), bolle di metaboliti, ticker eventi. Niente di sopra ~200 entità simultanee, nessuna animazione fisica reale. **WebGL non serve.**

Sostituzione: `BiotopeScene` come componente HEEx che emette **un singolo SVG** con:

- `<rect>` per le fasce di fase (gradient definite in `<defs>`),
- `<circle>` per ogni lineage (cap ~60/fase, posizionati deterministicamente da `lineage.id` hash),
- `<g>` per pool metaboliti (mini-bar a destra di ogni fascia),
- transizioni con `style="transition: r 200ms, cy 200ms"` per particelle che cambiano abbondanza.

**Vantaggi**:

- Stato 100% lato server, snapshot via diffing LV (già abbiamo `assign_scene_snapshot`).
- Click su `<circle>` → `phx-click` con `lineage_id` → apre side-drawer ispettore senza JSON serialization.
- Eliminazione `pixi.js` (-500 KB bundle); `package.json` riducibile a `phoenix`/`phoenix_html`/`phoenix_live_view`.

Hook JS residuo `SvgPanZoom` (≤80 righe): ascolta wheel/drag, applica `transform: matrix(...)` al `<g>` root del biotopo. Niente WebGL, niente Pixi.

**Mitigazione performance**: cap a 60 particelle/fase (già in Pixi); fasi più dense aggregano in "pile" + counter, click espande. Per N > 200 lineages totali la scena ha comunque budget rendering più che sufficiente con SVG nativo (browser moderni gestiscono migliaia di nodi SVG con `will-change: transform`).

---

## Sistema di layout

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

- `Layouts.app` rimpiazza `GameChrome.top_nav` (mantenere durante migrazione, poi eliminare).
- Sidebar opzionale: presente in `SeedLabLive` (lista repliconi), `SimLive` (lista fasi); assente in `WorldLive`/`Dashboard`.
- Viewport: `height: 100dvh; display: grid; grid-template-rows: 48px 1fr; overflow: hidden`.

---

## Vista per vista

### Dashboard (`/dashboard` — nuova, landing post-login)

Griglia 2×3 di pannelli "card-link" (al click → vista dedicata):

| Pannello | Contenuto | Apre |
|---|---|---|
| **World** | mini-grafo SVG dei biotopi attivi + count | `/world` |
| **Seed Lab** | preview del seed corrente del player + stato lock | `/seed-lab` |
| **My Biotopes** | lista compatta dei propri biotopi + tick | `/biotopes/:id` |
| **Community** | top 3 community di altri player (read-only) | `/community` |
| **Audit / Events** | stream ultimi 10 eventi globali | `/audit` |
| **Calibration** | link statici (`CALIBRATION.md`, `DESIGN.md`, `BIOLOGICAL-MODEL-REVIEW.md`) renderizzati come HTML | `/docs/:slug` |

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

- Sostituire l'attuale `world-map` con SVG full-bleed (no scrollbar).
- Side-panel contestuale a destra (320 px): info del biotopo selezionato, CTA primaria.
- Filtri (mine/wild/all) come tab inline, no modal.

### Seed Lab (`/seed-lab`) — la vista più ridisegnata

Layout 3 colonne:

```
┌────────────┬──────────────────────────────┬─────────────┐
│ Sidebar    │  Genome canvas               │ Inspector   │
│ ────────── │  (chromosome + plasmids)     │ (selected)  │
│            │                              │             │
│ Repliconi  │   ┌──────────────────┐       │ Domain list │
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

**Cromosoma circolare (SVG)**:

- Cerchio principale; geni come archi colorati distribuiti sulla circonferenza.
- Ogni gene è un sotto-arco; i domini sono mini-rettangoli concentrici verso il centro (corona di domini).
- Click su un gene → highlight + popola Inspector.
- Drag di un dominio: riordino entro lo stesso gene; drop su altro gene → spostamento; drop fuori → rimozione (con conferma).
- Bias intergenici tra geni mostrati come "ticks" sull'anello esterno.
- Plasmidi sotto come cerchi più piccoli (stesso schema, scale 0.6×).

**Drag-and-drop hook** (`DomainDnD`, ≤120 righe JS): `pointerdown` su dominio → registra; `pointermove` → posizione live; `pointerup` su drop target → `pushEvent("reorder_domain", {...})`. Tutto stato finale lato server.

**Fallback a11y**: ogni dominio ha pulsanti ↑/↓/× sempre visibili (non solo drag). Tab-navigabili, attivabili da tastiera. Coerente con principio guida #7.

**Pannello fenotipo**: derivato in tempo reale da `Phenotype.from_genome`. Mostra gli 11 trait (kcat, repair, growth rate, surface tags, ecc.) come barre orizzontali colorate. Tooltip su ognuna spiega "deriva da X domini di tipo Y".

### Biotope view (`/biotopes/:id`)

Layout 3 zone:

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

- `BiotopeScene` come SVG (sostituisce Pixi).
- Click su lineage circle → drawer destra (375 px) con dettaglio fenotipo, link a "Open in SeedLab" (read-only inspector).
- Bottom tab bar fisso, body delle tab scrolla verticalmente solo all'interno.
- Player interventions come floating action button + dialog modale (no inline form lungo come oggi).

### Community (`/community`)

Lista pubblica delle community-mode runs (Fase 19). Identica struttura a `/world`, ma read-only e ordinabile per metriche di diversità.

### Audit (`/audit`)

Stream eventi globali: tabella server-side paginated, filtri per tipo evento (HGT, mutation, lysis, ecc.). Sub-panel scroll, pagina principale fissa.

---

## Componenti da creare/refattorizzare

In `lib/arkea_web/components/`:

- `shell.ex` — `<.shell>`, `<.shell_header>`, `<.shell_sidebar>`, `<.shell_main>` (slot-based).
- `panel.ex` — `<.panel>`, `<.panel_header>`, `<.panel_body scroll/no_scroll>`.
- `metric.ex` — `<.metric_chip>`, `<.metric_strip>`, `<.metric_bar>` (sostituisce gli `stat_chip` duplicati nelle 3 view).
- `data_table.ex` — tabella con sort, sticky header, virtual scroll opzionale.
- `genome_canvas.ex` — render SVG cromosoma/plasmidi + inspector hooks.
- `biotope_scene.ex` — SVG sostituto di Pixi.
- `world_graph.ex` — SVG con pan/zoom.
- `drawer.ex` — pannello slide-in destra, chiusura con Esc.
- `empty_state.ex` — placeholder coerente per liste vuote.

`core_components.ex` resta solo per i componenti Phoenix di default (input, button, errors).

---

## CSS — refactor

- Migrazione progressiva da `app.css` monolitico (2063 righe) a un set di file in `assets/css/`:
  - `tokens.css` (colori, spacing, type scale, z-index).
  - `shell.css` (layout root).
  - `panel.css`, `metric.css`, `table.css`, `drawer.css`, `genome.css`, `scene.css`.
  - `app.css` come solo `@import`.
- CSS custom properties per tema; **CSS handcrafted, no Tailwind** (decisione confermata).
- Naming: prefisso `arkea-` invece dei misti `sim-`/`world-`/`seed-`.

---

## View-model layer

Nuovi moduli puri in `lib/arkea/views/`:

- `Arkea.Views.WorldVM` — `to_view(world_overview)` → struct con campi pre-formattati.
- `Arkea.Views.BiotopeVM` — `to_view(BiotopeState.t())` → `scene_snapshot`, `lineage_rows`, `metabolite_rows`.
- `Arkea.Views.SeedVM` — `to_view(seed_form)` → `genome_layout` (cerchi, archi, domini con coordinate pre-calcolate).

Render HEEx consumano solo VM. Test unitari sulle VM (nessun coupling con LV).

---

## Migrazione in fasi

| Fase | Scope | Output |
|---|---|---|
| **U0** | Shell + tokens + componenti `panel`/`metric` | Shell condiviso, base CSS pulita |
| **U1** | Dashboard come nuova landing | `/dashboard`, redirect post-login |
| **U2** | World view migrata a Shell + SVG full-bleed | Sidebar contestuale a destra |
| **U3** | Biotope SVG scene (rimpiazza Pixi) | `pixi.js` rimosso da `package.json` |
| **U4** | Biotope view: drawer + bottom tabs | Sostituzione layout `SimLive` |
| **U5** | SeedLab cromosoma circolare + DnD domini | Hook `DomainDnD` (≤120 righe) |
| **U6** | Audit + Community views | Stream paginated |
| **U7** | Cleanup CSS + rimozione codice morto | `app.css` spezzato in moduli |

Ogni fase: test green (incluso `mix test`), no regressione visiva manuale, commit isolato.

---

## File critici toccati (sintesi)

- `lib/arkea_web/router.ex` — nuova route `/dashboard`, redirect post-login.
- `lib/arkea_web/components/layouts/root.html.heex` — caricamento nuovi CSS.
- `lib/arkea_web/components/layouts.ex` — `app` layout con `<.shell>`.
- `lib/arkea_web/live/dashboard_live.ex` — **nuovo**.
- `lib/arkea_web/live/world_live.ex` — refactor completo a Shell + VM.
- `lib/arkea_web/live/seed_lab_live.ex` — refactor completo: cromosoma circolare, DnD, inspector.
- `lib/arkea_web/live/sim_live.ex` — refactor completo: SVG scene, drawer, bottom tabs.
- `lib/arkea_web/live/community_live.ex` — **nuovo** (read-only).
- `lib/arkea_web/live/audit_live.ex` — **nuovo**.
- `lib/arkea_web/components/` — nuovi componenti (vedi sezione dedicata).
- `lib/arkea/views/` — nuovi VM puri (`WorldVM`, `BiotopeVM`, `SeedVM`).
- `assets/js/app.js` — rimozione `BiotopeScene` Pixi, aggiunta `SvgPanZoom`, `DomainDnD`.
- `assets/js/hooks/` — rimozione `biotope_scene.js`, aggiunta `svg_pan_zoom.js`, `domain_dnd.js`.
- `assets/css/` — split modulare di `app.css`.
- `assets/package.json` — rimozione `pixi.js`.

---

## Verifica end-to-end

Per ogni fase:

1. **`mix test` verde** dopo ogni fase.
2. **Test LiveView**: `Phoenix.LiveViewTest` su `mount`, `handle_event` di drag/drop, drawer open/close.
3. **Test VM**: pure unit test su `Arkea.Views.*`.
4. **Smoke manuale**: ogni view a 1280×720 e 1920×1080, no scrollbar globale, tutte le interazioni keyboard-accessible.
5. **Bundle size**: `priv/static/assets/app.js` < 200 KB dopo rimozione Pixi (oggi ~600 KB).
6. **A11y**: navigazione tastiera completa, fallback ↑/↓/× per il riordino domini sempre disponibili.

---

## Rischi e mitigazioni

- **Performance SVG con N > 200 lineages**: Pixi è più veloce a 1000+ entità. Mitigazione: cap a 60 particelle/fase + aggregation pile per density; CSS `will-change: transform` su `<g>` animati.
- **Drag-and-drop su SVG**: complesso ma fattibile con pointer events. Fallback già pianificato (pulsanti ↑/↓/×).
- **State lock durante editing genoma**: già presente (`seed_locked?`), confermare semantica nel nuovo flow.
- **Routing**: aggiungere `/dashboard` come default; modificare redirect login senza rompere bookmark esistenti (mantenere `/world` accessibile).
- **Refactor di file lunghi (`SeedLabLive` 1473, `SimLive` 1316)**: rischio di regressioni durante l'estrazione VM. Mitigazione: VM testate prima, render migrato a piccoli passi, snapshot test HEEx dove possibile.

---

## Persistenza del piano nel repository

Il piano è reificato come **documento bilingue versionato nella root del progetto**, conforme alla convenzione esistente (`DESIGN.md` / `DESIGN.en.md`, `BIOLOGICAL-MODEL-REVIEW.md` / `BIOLOGICAL-MODEL-REVIEW.en.md`, `CALIBRATION.md` / `CALIBRATION.en.md`):

- **`UI-REWRITE-PLAN.md`** — italiano, canonico (sorgente di verità). Header con language switcher.
- **`UI-REWRITE-PLAN.en.md`** — traduzione inglese sincronizzata. Header speculare.

La traduzione inglese è creata e mantenuta sincronizzata via il `bilingual-docs-maintainer` agent.

Aggiornamento di `README.md` e `README.en.md` nella sezione "Documenti" per linkare il nuovo doc.

---

## Output finali attesi a piano completo

- Dashboard come landing post-login con 6 pannelli card-link.
- 4 viste a pagina intera dedicate (`/world`, `/seed-lab`, `/biotopes/:id`, `/community`, `/audit`) senza scrollbar globali.
- Genoma visualizzato come cromosoma circolare con domini riorganizzabili via DnD (con fallback a11y).
- PixiJS rimosso; rendering 100% LiveView/SVG.
- Bundle JS < 200 KB.
- CSS modularizzato (`tokens.css` + componenti) sotto prefisso unico `arkea-`.
- View-model layer testato indipendentemente dai LiveView.
- Coerenza piena con DESIGN.md (Blocchi 12 e 14 — visualizzazione e UI).
