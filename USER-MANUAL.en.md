> 🇮🇹 [Italiano](USER-MANUAL.md) · 🇬🇧 English (this page)

# User Manual · Arkea

Welcome to **Arkea**. This manual guides you through creating your first player, designing an *Arkeon* seed, colonizing a biotope, and observing the evolution that follows.

Arkea is a **persistent shared simulation** written for those with a solid background in microbiology / molecular biology. Do not expect narrative shortcuts: every mechanism reflects a real biological counterpart (references in [`devel-docs/CALIBRATION.md`](devel-docs/CALIBRATION.md)).

> **Runtime status**: the simulation runs 24/7 on the server. When you disconnect, your biotope keeps evolving. When you return, you will find the population at the current tick.

---

## 1. First access

### 1.1 Creating an account

1. Open the home page (`/`) and choose **"Create player"**.
2. Enter a `display_name` (visible in `Audit` and `Community`) and an `email` (resume key).
3. After clicking "Create player" you are redirected to the **Seed Lab**.

There is no password: resume is email-based. Use a different address if you want to separate identities.

### 1.2 Resuming

From `/` choose **"Resume player"** and enter your registered email. You are redirected to the **Dashboard**.

---

## 2. Dashboard

The Dashboard is the post-login landing page. It is structured as **6 card-link panels**:

| Panel | Opens | What it contains |
|---|---|---|
| **World** | `/world` | SVG graph of active biotopes (yours + wild + other players') |
| **Seed Lab** | `/seed-lab` | Seed editor; locked after first colonization |
| **My Biotopes** | `/biotopes/:id` | Compact list of biotopes you own, with tick and lineage count |
| **Community** | `/community` | Multi-seed runs by other players (read-only) |
| **Audit** | `/audit` | Global stream of persisted typed events |
| **Docs** | (placeholder) | DESIGN/CALIBRATION references (Markdown rendering coming soon) |

Click a panel to open the full-page view. No view has a global scrollbar: when content overflows, sub-panels scroll internally.

---

## 3. Seed Lab — designing the initial Arkeon

The Seed Lab is the starting point: choose the **archetype of the biotope to colonize**, **base phenotype profiles**, and — optionally — **compose custom genes** domain by domain.

### 3.1 Main form (left column)

- **Seed name**: identifies the blueprint in the provisioning system.
- **Biotope archetype**: 3 starter options (Eutrophic Pond, Oligotrophic Lake, Mesophilic Soil). Each archetype has different phases, starting pool metabolites, and zones — see descriptions in the radio cards.
- **Metabolic cassette** (`metabolism_profile`): select the profile that sets the kcat/Km of the base catalytic domains. Options: balanced / thrifty / bloom.
- **Membrane profile**: porous / fortified / salinity-tuned. Modulates osmotic tolerance and n_transmembrane.
- **Regulation mode**: responsive / steady / mutator. Impacts `repair_efficiency` and dna_binding_affinity.
- **Mobile module**: none / conjugative_plasmid / latent_prophage. Adds a plasmid or a prophage to the starting genome.

The **preview** updates in real time: see the derived phenotype (µ, ε, n_TM, σ-affinity, QS signals) in the right sidebar.

### 3.2 Circular chromosome (center)

The chromosome is rendered as an **SVG ring** with genes as colored arcs. Each gene has a concentric **domain crown** (narrower mini-arcs toward the center).

- **Click on a gene** → highlights it and populates the inspector.
- **Plasmids** shown below as smaller circles (same scheme, 0.6× scale).
- **Editable genes** (custom genes you have added) have a dashed outline to distinguish them from base genes derived from profiles.

### 3.3 Custom gene draft editor

Below the canvas, the **draft gene editor**:

- **Functional domain palette** (11 types). Click a domain → it is appended to the draft.
- **Reordering**: each domain in the draft has three buttons — `↑` (move up), `↓` (move down), `×` (remove). All keyboard-accessible.
- **Intergenic blocks**: 3 families (`expression`, `transfer`, `duplication`) with togglable modules (e.g. sigma_promoter, oriT_site, repeat_array). They influence sigma factor, HGT bias, copy number.
- **Commit** the gene → it is added to the chromosome and appears as an editable arc.
- **Remove custom gene** from the compact list below.

> Maximum **9 domains per custom gene**. Maximum gene editor scope: chromosome only (no custom plasmid in phase 1).

### 3.4 Provisioning

When the seed is complete (name + archetype chosen + form valid), the **"Colonize selected biotope"** button becomes active.

Click → the system:
1. Creates a persistent `ArkeonBlueprint` with your phenotype+genome.
2. Starts a new `Biotope.Server` registered for you.
3. Inoculates the seed lineage into the biotope (`N=420` distributed across phases).
4. Redirects to the **biotope viewport**.

> **Important**: the seed **locks** upon first colonization. The blueprint remains viewable but can no longer be edited. To design a new seed, register another player.

---

## 4. Biotope viewport — observing evolution

The biotope viewport is the densest view: realtime telemetry + inspection + interventions.

### 4.1 Layout

```
┌── header: archetipo · interventi · topology · user ───┐
├── sidebar: fasi + KPIs ───┬── scena SVG ──────────────┤
│  Tick 142                 │                           │
│  Lineages 6               │                           │
│  N total 1.4k             │                           │
│  Stream live              │                           │
│  ────────                 │                           │
│  Phases:                  │                           │
│   ▸ surface  · 22°C  642  │                           │
│   ▸ deep    · 12°C  812  │                           │
│  ────────                 │                           │
│  Phase inspector:         │                           │
│   N, richness, H′, phages │                           │
│   T, pH, osmolarity, D    │                           │
├───────────────────────────┴───────────────────────────┤
│ Bottom tabs: Events · Lineages · Chemistry · Interv.  │
└───────────────────────────────────────────────────────┘
```

### 4.2 Sidebar (left)

**Biotope KPIs**: tick, lineages, N total, stream status (live/shell).

**Phases list**: each phase is a button with a colored swatch + name + (T, pH) + current population. Click → selects the phase. The selected phase determines:
- the highlight of the corresponding arc in the SVG scene
- the **Phase inspector** below (phase KPIs: N, richness, H′ (Shannon), phage load; environment: T, pH, Osm, D = dilution rate)
- the target of certain interventions (e.g. `nutrient_pulse`)

### 4.3 SVG scene (center)

The scene renders the biotope as **horizontal bands** (one per phase) with **particles** inside each representing lineages.

- Particles are deterministically positioned via hash → when abundance changes, dots move but do not jump.
- **Shape by phenotypic cluster**:
  - circle = generalist
  - rounded square = biofilm
  - ellipse = motile
- **Color** = palette by cluster + hash of the lineage `id` (stable).
- **Click on a phase band** → selects the phase in the sidebar.
- Tick overlay in the top right.

### 4.4 Bottom tabs (bottom, ~220 px)

Four tabs. Only the body of the active tab is rendered; scrolling is internal.

- **Events** — stream of the last ~20 biotope events (born, extinct, hgt_transfer, intervention).
- **Lineages** — sortable table (by `N` / `µ` / `ε` / `born`). **Click on a row → opens the right drawer** with lineage detail.
- **Chemistry** — `phases × metabolites` heatmap with color proportional to concentration; below, token cloud with signal load + phage load per phase.
- **Interventions** — see §4.6.

### 4.5 Lineage drawer (right, slide-in)

Opens by clicking a row in the Lineages tab. Shows:

- Full ID + color swatch.
- Phenotypic cluster (biofilm / motile / stress-tolerant / generalist / cryptic).
- Total N, birth tick.
- µ (h⁻¹), ε (repair efficiency), main surface tags.
- Per-phase abundance.

"Close" button or click the row again to close.

### 4.6 Interventions

Only biotopes you **own** accept interventions; others are read-only.

Open the panel via the **"Interventions"** button in the header (left drawer) or from the "Interventions" tab below. Current options:

- **Nutrient pulse** → adds metabolites to the selected phase (targets the kcat of the profiles).
- **Plasmid inoculation** → introduces a known plasmid into the pool of the selected phase (may recombine).
- **Mixing event** → applies mixing across biotope phases (temporarily homogenizes concentrations and populations).

Each intervention consumes a **budget slot** (anti-griefing rate limiting). The slot status is visible in the panel: `Slot open` or `Locked X` (counter to reset).

### 4.7 Topology modal

Click the ⚙ button in the header → modal with network metadata: biotope id, zone, display coordinates, owner, list of neighbor IDs.

---

## 5. World — macroscale overview

`/world` renders the **SVG graph** of active biotopes.

- **Nodes** = biotopes; radius ∝ log(total N + lineage count). Color = archetype.
- **Edges** = inter-biotope migration connections.
- **Click on a node** → selects it; the right side panel shows: archetype, owner, tick, lineages, N, phases, "Open biotope" link.
- **Filter tabs**: `All` / `Mine` / `Wild` to narrow the view.

The side panel has 3 sub-panels:
1. **Operator** — your name + CTA to Seed Lab.
2. **Selected** — detail of the selected biotope (empty if none).
3. **Distribution** — colored bar with breakdown by archetype.

---

## 6. Audit — global events

`/audit` shows the **persisted log** of typed events (Block 13 of `DESIGN.md`).

- **Filter tabs**: All / HGT / Mutations / Lysis / Interventions / Community / Colonisation / Mobile.
- **Pagination**: 50 events per page; pager `1–50 of 412`.
- Each row: timestamp, event type (colored badge), tick, biotope_id, lineage_id, payload preview.

The audit log is **append-only** and survives biotope removal. It is the source of truth for reconstructing any evolutionary history.

---

## 7. Community — multi-seed runs

`/community` lists **biotopes inoculated in community mode** (BIOLOGICAL-MODEL-REVIEW Phase 19). These are biotopes started with multiple founder seeds simultaneously — useful for studying inter-strain interactions from tick 0.

Each entry has: archetype, founder count, inoculation phase, timestamp, current tick, lineage count, "Open →" link to the viewport.

> Community provisioning currently happens only via the simulation API (`Arkea.Game.CommunityLab.provision_community/3`). A creation UI is on the roadmap.

---

## 8. Quick glossary

| UI term | Meaning |
|---|---|
| **Arkeon** | The proto-bacterial organism (genome + derived phenotype). |
| **Lineage** | Descent with identical genome (a mutant is a new lineage). |
| **Biotope** | Persistent world with N phases, K lineages, environmental conditions. |
| **Phase** | Sub-volume of the biotope with homogeneous conditions (surface, sediment, …). |
| **µ** | Specific growth rate (h⁻¹). |
| **ε** | Repair efficiency (0..1). |
| **H′** | Shannon diversity index computed per phase. |
| **N** | Population (counts), per phase or total. |
| **D** | Dilution rate (%/tick). |
| **Cluster** | Derived phenotypic category: biofilm / motile / stress-tolerant / generalist / cryptic. |
| **Phage load** | Sum of virion abundances in the `phage_pool` of a phase. |
| **HGT** | Horizontal Gene Transfer — conjugation + transformation + transduction + phage infection. |
| **Budget slot** | Anti-griefing rate limit for interventions. |
| **Audit log** | Append-only table of persisted typed events. |

Broader biological glossary in [`devel-docs/DESIGN.md`](devel-docs/DESIGN.md).

---

## 9. FAQ

**Can I reset the biotope?**
No: the simulation is authoritative and persistent. To start over, register a new player or wait for your lineage to go extinct naturally.

**What happens if I close the browser during a tick?**
The server continues. When you return, you reconnect via PubSub to the biotope and receive the current state.

**Why don't I see events in the Events tab?**
The biotope is probably young or stable. Events are `:lineage_born`, `:lineage_extinct`, `:hgt_transfer`, `:intervention`. Without selective pressure (neutral mutation, no spontaneous HGT) the queue stays empty.

**My seed is locked — how do I test new configurations?**
Create a new player (different email). The seed lock is per blueprint, not per instance.

**Can I intervene on a biotope I don't own?**
No. Only biotopes you have colonized accept interventions. Others are inspectable but read-only.

**Will my draft gene edits be lost?**
Yes, the draft is not persisted. It lives in the LiveView state. If you reload the page, you start from scratch — commit the gene when you are ready.

**Where do I find the model constants?**
All key constants + biological ranges from the literature are in [`devel-docs/CALIBRATION.md`](devel-docs/CALIBRATION.md).

---

## 10. Feedback and contributions

Bugs, suggestions, scientific walkthroughs to validate → see [README.en.md](README.en.md) for project channels. The biological model is evolving: the roadmap is in [`devel-docs/BIOLOGICAL-MODEL-REVIEW.md`](devel-docs/BIOLOGICAL-MODEL-REVIEW.md).
