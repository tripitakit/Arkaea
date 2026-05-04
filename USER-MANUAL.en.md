> [🇮🇹 Italiano](USER-MANUAL.md) · 🇬🇧 English (this page)

# User Manual · Arkea

Welcome to **Arkea**, a persistent evolutionary sandbox for proto-bacterial organisms. This manual takes you from zero (player registration) to observing host-phage arms races, plasmid displacement, error catastrophe, and metabolic cycle closure in your biotopes.

The manual assumes a solid background in **microbiology / molecular biology**. Do not expect narrative shortcuts: every mechanism reflects a real biological counterpart, calibrated and documented in [`devel-docs/CALIBRATION.md`](devel-docs/CALIBRATION.md). If you want the exact numbers, keep it open alongside.

> **What Arkea is NOT**: a competitive game. No scoreboard, no victory loop. The observable phenomenon *is* the reward.

---

## Table of Contents

1. [Mental model (read this first)](#1-mental-model-read-this-first)
2. [First access](#2-first-access)
3. [Dashboard tour](#3-dashboard-tour)
4. [Seed Lab — designing the initial Arkeon](#4-seed-lab--designing-the-initial-arkeon)
5. [Biotope viewport — observing evolution](#5-biotope-viewport--observing-evolution)
6. [Selective pressures: what to expect](#6-selective-pressures-what-to-expect)
7. [Reading evolutionary signals](#7-reading-evolutionary-signals)
8. [World — macroscale overview](#8-world--macroscale-overview)
9. [Audit — the event log](#9-audit--the-event-log)
10. [Community — multi-seed runs](#10-community--multi-seed-runs)
11. [Playbook: recurring scenarios](#11-playbook-recurring-scenarios)
12. [Extended glossary](#12-extended-glossary)
13. [FAQ](#13-faq)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Mental model (read this first)

### 1.1 Server-authoritative

Arkea runs **24/7 on the server** (BEAM/OTP). Each biotope is an isolated Erlang process that executes a *pure-functional tick* at a regular cadence. The browser **does not** simulate anything: it only receives the current biotope state via PubSub and renders it as native SVG.

Practical consequences:

- **When you close the browser, your biotope keeps evolving.** When you return, the display shows the state at the current tick.
- **You cannot pause.** Time on the server runs equally for all players.
- **If two players are looking at the same wild biotope simultaneously, they see exactly the same thing.**

### 1.2 Time scales

| Construct | Arkea value | Biological equivalent |
|---|---|---|
| 1 tick | 5 minutes wall-clock | ~1 reference cell generation |
| Free phage half-life | 3–5 ticks | hours–days in real surface waters |
| SOS activation under stress | 4–10 ticks | minutes in vivo |
| Mutator strain emergence | 50–200 ticks | 100–1000 Lenski-style generations |
| Cross-feeding cycle closure | 100–500 ticks | days in chemostat |

So **one hour of runtime ≈ 12 generations**, and one simulation day ≈ 288 generations: comparable to a weekly Lenski experiment. Rare in-vivo events (transduction, SOS hypermutation) are **amplified for visibility within game time scales**; overrides for scientific benchmarks exist (see `devel-docs/CALIBRATION.md`).

### 1.3 Ownership and visibility

- **Biotopes you colonize** are `player_controlled`: only you can apply interventions.
- `wild` biotopes (default scenario, automatic events) are inspectable by anyone but not modifiable.
- Other players' biotopes are `foreign_controlled`: visible in `World`, not modifiable.
- Your **seed** (genome + initial phenotype) is private until provisioning, then becomes part of the public record via `Audit`.

### 1.4 Minimal anti-griefing

`intervention` events (nutrient pulse, plasmid inoculation, mixing event) consume a **budget slot** subject to a **60-second rate limit** (in prototype; in production it was 30 minutes). This prevents a player from "disrupting" a wild biotope with burst interventions. The slot status is always visible in the interventions panel: `Slot open` or `Locked X` (with countdown to reset).

### 1.5 What the player designs vs what emerges

| You decide (Seed Lab) | Emerges from the simulation |
|---|---|
| Biotope archetype | Speciation (new lineages from mutation) |
| Seed metabolic cassette | HGT events (conjugation, transformation, transduction) |
| Membrane profile | Phage dynamics (lytic burst, lysogeny, decay) |
| Regulation mode | SOS response, error catastrophe |
| Mobile module (plasmid or prophage) | Bacteriocin warfare |
| Custom genes (≤ 9 domains each) | Cross-feeding, niche partitioning |
| Intergenic blocks | Biofilm formation, mixing events |

You design **the starting point**. The system evolves everything else.

---

## 2. First access

### 2.1 Creating an account

1. Open the home page `/` and choose **"Crea player"**.
2. Enter a `display_name` (visible in `Audit` and `Community`) and an `email` (resume key).
3. After clicking "Create player" you are redirected to the **Seed Lab**.

> **No password.** Resume is email-based — anyone who knows your email can resume your session. For the prototype this is acceptable; it will change in production.

### 2.2 Resuming

From `/` choose **"Riprendi player"** and enter your registered email. You are redirected to the **Dashboard** (not the Seed Lab — the seed is already locked if you have already provisioned).

### 2.3 What to expect in the first minute

Immediately after registration:

1. The **Dashboard** shows 6 panels; "Seed Lab" is the one you need.
2. No biotope is running yet — the "World" panel is empty, "My Biotopes" shows "No owned biotopes".
3. Community and audit are empty for you (global events from other players may already be visible).
4. Click "Seed Lab" → design the seed.
5. After provisioning, the biotope viewport takes you into your first biotope. Already at **tick 0** you see the founding population (`N=420` distributed across the biotope phases).

In the **first 10–30 ticks** you will see almost nothing dynamic: the founding population is genomically uniform, mutations are rare. This is normal. From around tick ~50 onward, the first `:lineage_born` events begin to appear.

---

## 3. Dashboard tour

The Dashboard is the post-login landing page. It is structured as **6 card-link panels**:

| Panel | Opens | When you need it |
|---|---|---|
| **World** | `/world` | Overview: who is where, how many active biotopes, archetype distribution. |
| **Seed Lab** | `/seed-lab` | Only before the first provisioning, or to inspect the locked seed. |
| **My Biotopes** | `/biotopes/:id` | Compact list of biotopes you own — quick jump to the viewport. |
| **Community** | `/community` | Read-only: biotopes started in community mode (multi-seed). |
| **Audit** | `/audit` | Global stream of persisted typed events — forensic queries. |
| **Docs** | (placeholder) | DESIGN/CALIBRATION references (Markdown rendering coming soon). |

### 3.1 Typical session flows

- **Onboarding session (first time)**: Dashboard → Seed Lab → provision → Biotope viewport. Once the seed is locked, the "Seed Lab" panel on the Dashboard becomes inspect-only.
- **Observation session**: Dashboard → My Biotopes → Biotope viewport (or World → click on node → Open biotope).
- **Forensic analysis session**: Dashboard → Audit → filter by `mutation_notable` / `hgt_event` / `community_provisioned` to understand what happened in the last few hours.

No Dashboard view has a global scrollbar: when content overflows, sub-panels scroll internally.

---

## 4. Seed Lab — designing the initial Arkeon

The Seed Lab is the point of maximum leverage. Your choices here determine:

- the **base cellularity** of your founder lineage (membrane, regulation, repair);
- the **initial metabolic cassette** (kcat, Km, metabolite targets);
- the **mobile elements** the seed carries (plasmids, prophages, custom genes);
- the **destination biotope** (archetype + zone).

Once the first biotope is colonized, the seed **locks** and is no longer editable. To design an alternative seed, you must register a new player.

### 4.1 Main form (left column)

#### Seed name

Human-readable identifier of the blueprint in the provisioning system. Visible in Audit for `colonization` events. Maximum 40 characters.

#### Biotope archetype to colonize

Three starter options, each with different phases / metabolites / zones:

- **Eutrophic Pond** — high nutrient density, rapid turnover. Phases: surface (high O₂), water column, sediment (anoxic). Good environment for generalists with flexible metabolism.
- **Oligotrophic Lake** — clean water, low C inflow. Phases similar to pond but with lower metabolic concentrations. Rewards `thrifty` profiles with low Km.
- **Mesophilic Soil** — patchy environment (aerobic pore, wet clump, soil water). More heterogeneous phases → marked niche partitioning. Rewards fortified membranes and responsive regulation.

Each archetype loads a **starting metabolite pool** (see `devel-docs/DESIGN.md` Block 6 for the complete list).

#### Metabolic cassette (`metabolism_profile`)

Sets the base parameters of the seed's catalytic domains:

- **`balanced`** — average kcat, average Km across diversified targets. Good default for exploration.
- **`thrifty`** — low kcat, low Km (high affinity). Survives in oligotrophic environments; grows slowly everywhere.
- **`bloom`** — high kcat, high Km (low affinity). Explodes in eutrophic; crashes in oligotrophic.

#### Membrane profile (`membrane_profile`)

- **`porous`** — high diffusion, low osmotic stability. Fast uptake; fragile under osmolarity shock.
- **`fortified`** — more transmembrane anchors, robust to osmotic stress and xenobiotics. Slow uptake.
- **`salinity_tuned`** — middle ground specific to saline estuary / sediment.

#### Regulation mode (`regulation_profile`)

Modulates `repair_efficiency`, `dna_binding_affinity`, and the SOS trigger sensitivity:

- **`steady`** — high repair, medium dna_binding_affinity, conservative SOS. Low µ but stable.
- **`responsive`** — medium repair, adaptive regulation, SOS-ready.
- **`mutator`** — low repair → high mutation rate → mutator strain. Fast speciation but risk of error catastrophe.

> Tip: `mutator` is explosive. In an oligotrophic lake with a mutator profile you will see 10+ lineages within 200 ticks, but many will collapse due to error catastrophe. It is the fastest way to study the Eigen limit.

#### Mobile module (`mobile_module`)

Adds a mobile element to the starting genome:

- **`none`** — chromosome only.
- **`conjugative_plasmid`** — a plasmid with `oriT` site, copy number ~3, ~2 cassette genes. Allows vertical HGT from tick 1.
- **`latent_prophage`** — an integrated lysogenic prophage with medium repressor strength. Under stress (SOS), it will enter the lytic cycle and release virions.

The mobile module is the key to triggering fast HGT in scenarios of a few hundred ticks.

### 4.2 Circular chromosome (center of the Seed Lab)

The chromosome is rendered as an **SVG ring** with genes as colored arcs distributed around the circumference. Each gene has a **concentric domain crown**: narrower mini-arcs toward the center corresponding to the individual functional domains of the gene.

How to read it:

- **Outer ring** = gene arc, uniformly colored per gene (palette derived from the hash of the gene `id`).
- **Inner crown** = domains, each with its own type color (see domain table below).
- **Plasmids** shown below as smaller circles (0.6× scale). Their center is labeled "Plasmid 1", "Plasmid 2", etc.
- **Dashed outline** = editable gene (custom, added by you). Base genes (derived from cassette/membrane/regulation profiles) have a solid outline.

Click on a gene → the gene is highlighted (thicker stroke) and populates the **Inspector** below, where you see: domains, intergenic blocks, codon count, derived parameters.

### 4.3 The 11 functional domains

Block 7 of `DESIGN.md`. Each gene is a sequence of codons; the parser extracts one or more *domains* based on a 3-codon `type_tag` that indexes into `0..10`. Each domain has 20 `parameter_codons` that, summed with log-normal weights, produce the derived parameters.

| Type | Tag | What it does | Typical parameters |
|---|---|---|---|
| `:substrate_binding` | SB | Defines binding affinity and target metabolite class | `target_metabolite_id` (0..12), `affinity_km` |
| `:catalytic_site` | CAT | Adds catalytic turnover and reaction class | `kcat`, `reaction_class` (e.g. hydrolysis, oxidation) |
| `:transmembrane_anchor` | TM | Membrane insertion, modulates `n_passes` | `n_passes` (1..10), `stability` |
| `:channel_pore` | CH | Transport selectivity + gating threshold | `selectivity_class`, `gating_threshold` |
| `:energy_coupling` | EC | ATP cost / PMF coupling | `atp_cost`, `pmf_couple` |
| `:dna_binding` | DNA | Promoter affinity, sigma coupling | `binding_affinity`, `sigma_class` |
| `:regulator_output` | REG | Regulatory output (activator/repressor) | `output_logic`, `target_operon` |
| `:ligand_sensor` | LIG | Sensing threshold for metabolite or signal | `signal_class`, `threshold_concentration` |
| `:structural_fold` | SF | Stability + multimerization support | `multimerization_n`, `stability` |
| `:surface_tag` | ST | Surface signature (pilus, phage receptor, biofilm) | `surface_class` (adhesin, matrix, biofilm, phage_receptor, …) |
| `:repair_fidelity` | RPR | DNA repair, modulates `error_rate` per replication | `repair_class`, `efficiency` |

**Composition rule**: a custom gene can carry **1 to 9 domains**. Typical meaningful compositions:

- `[catalytic, substrate_binding]` — a monofunctional enzyme.
- `[transmembrane, transmembrane, channel_pore, energy_coupling]` — an active transporter (e.g. ABC transporter).
- `[ligand_sensor, dna_binding, regulator_output]` — a two-component transcription factor.
- `[transmembrane, surface_tag]` — a surface adhesin.
- `[catalytic, substrate_binding, structural_fold]` — a multimeric enzyme.

The system does **not** validate the biological coherence of the composition: you can create an "alien" gene with domains that make no sense together. Natural selection will do the rest (non-functional lineages go extinct quickly).

### 4.4 Intergenic blocks

Three families of blocks attachable to the draft gene; each has togglable modules. They provide the gene with regulatory context and mobility:

- **`expression`**:
  - `sigma_promoter` — the gene is constitutively expressed (sigma-70-like).
  - `cyclic_amp_response` — expression modulated by catabolite.
  - `quorum_response` — QS-dependent expression.
- **`transfer`**:
  - `oriT_site` — the gene is transferable by conjugation (makes the gene "mobile").
  - `pilus_attachment_site` — facilitates inter-cellular HGT.
- **`duplication`**:
  - `repeat_array` — repeated sequence that increases the probability of gene duplication (gene amplification).

Each block is opt-in in the draft; committing the gene → the blocks become part of the gene's `regulatory_block`.

### 4.5 Draft gene editor

Below the canvas, the **draft gene editor**:

1. **Functional domain palette** (11 types, click to add). Latent domains (some `:channel_pore`, `:regulator_output`) are marked `stored / future` — biologically encoded but not aggregated in the currently active runtime.
2. **Draft list** with each domain in order. Buttons for each:
   - `↑` move up (accessible, keyboard too).
   - `↓` move down.
   - `×` remove.
3. **Intergenic block toggles** (3 families × 3 modules each).
4. **Draft errors**: if the composition is invalid (>9 domains, unknown palette id), an error message appears above the palette.
5. **Commit** — the gene is added to the chromosome and appears as an editable arc on the canvas.
6. **Clear draft** — reset.

> Tip: the draft is not persisted between reloads. If you reload the page, you start from scratch. Commit when you are satisfied.

### 4.6 Lock and provisioning

When the seed is complete (name ≥ 1 char + archetype selected + form valid), the **"Colonize selected biotope"** button becomes active.

Click → the system:

1. Creates a persistent `ArkeonBlueprint` with your phenotype + genome.
2. Starts a new `Biotope.Server` registered for you (you become `owner`).
3. Inoculates the seed lineage into the biotope. Initial distribution: `N=420` cells **divided across phases** of the biotope according to seed weights (e.g. surface 60%, water_column 30%, sediment 10%).
4. Redirects to the **biotope viewport**.

**Important**: the seed **locks** upon first colonization. The blueprint remains viewable (Seed Lab in read-only mode) but can no longer be edited. To design a new seed → register another player.

---

## 5. Biotope viewport — observing evolution

The biotope viewport is the densest view. It provides realtime telemetry + lineage inspection + intervention application.

### 5.1 General layout

```
┌── header: archetipo · interventi · topology · user ───┐
├── sidebar ────────────────┬── scena SVG ──────────────┤
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

When you click a lineage row, a **drawer** slides in on the right side (375 px) with the detail of the selected lineage.

### 5.2 Header

- **Archetype chip** (e.g. "Eutrophic Pond") with a colored dot per archetype.
- **Interventions** — opens the left drawer with the interventions panel.
- **⚙ Topology** — modal with network metadata (biotope id, zone, coordinates, owner, neighbor_ids).
- **User menu** — your name and logout.

### 5.3 Sidebar (left)

#### Biotope KPIs

Four tiles:

- **Tick** — the current tick. Increments by 1 every 5 minutes server-side.
- **Lineages** — number of currently living lineages (with `total_abundance > 0`).
- **N total** — overall biotope population, summed across all phases.
- **Stream** — `live` if you are subscribed to the biotope's PubSub (should always be `live` in a connected browser); `shell` if the subscription has dropped (refresh the page).

#### Phases list

Each biotope phase is a button with:

- a colored swatch on the left (by phase archetype: surface=amber, deep/sediment=rust, water_column=cyan, biofilm=green, etc.);
- phase name + (T, pH);
- current population in the phase on the right (compact format: `1.2k`).

Click → selects the phase. The selected phase determines:

- the **highlight** of the corresponding arc in the SVG scene (thicker stroke, evidence ring);
- the **Phase inspector** below (phase KPIs + environment);
- the target of certain interventions (e.g. `nutrient_pulse` acts on the selected phase).

#### Phase inspector

KPIs of the selected phase:

- **N** — population in the phase.
- **richness** — number of distinct lineages present in the phase.
- **H′ (Shannon)** — Shannon diversity calculated on lineage counts. `H′ = 0` when only 1 lineage; increases with N and with evenness.
- **phages** — sum of virion abundance in the phase's `phage_pool`.

Environment readings:

- **T** — temperature (°C).
- **pH** — phase pH.
- **Osm** — osmolarity (mOsm/L equivalent).
- **D** — dilution rate (%/tick). D=2% means 2% of the population flows out of the phase each tick.

### 5.4 SVG scene (center)

The scene renders the biotope as **horizontal bands** (one per phase) with **particles** inside each representing lineages. Key points:

- **Band height ∝ total population of the phase** (with a minimum floor). A small band = nearly empty phase.
- **Number of particles ∝ √(phase population)**, capped at 60. Each particle represents a fraction of the lineage.
- **Particle position** is deterministic via hash of `{phase, lineage_id, i}`. When abundance changes, particles shift slightly (CSS transition) but do not jump. Particles of the same lineage share a color.
- **Shape by phenotypic cluster**:
  - **circle** = `generalist` or `stress-tolerant` or `cryptic`.
  - **rounded square** = `biofilm` (lineages with `:adhesin` / `:matrix` / `:biofilm` surface tags).
  - **ellipse** = `motile` (lineages with `n_transmembrane >= 2`).
- **Color** = palette by cluster + hash of the lineage `id`. Stable across ticks (does not change when abundance changes).
- **Click on a phase band** → selects the phase (equivalent to clicking the phase list).
- **Tick overlay** in the top right.

> Note: the scene is a **dense proxy**, not a 1:1 representation. With 100 lineages in a phase, you will see at most 60 particles; the rest is "implicit". The exact numerical detail is in the Lineages tab.

### 5.5 Bottom tabs (~220 px)

Four tabs. Only the body of the active tab is rendered; scrolling is internal.

#### Events

Stream of the last ~20 biotope events, in descending chronological order. Types:

- **`:lineage_born`** — new lineage born (mutation producing a new genome). Icon: ➕ green.
- **`:lineage_extinct`** — lineage extinct (`total_abundance = 0`). Icon: ➖ red.
- **`:hgt_transfer`** — HGT event (conjugation, transformation, transduction, lysogenic infection). Icon: ⇄ amber.
- **`:intervention`** — player intervention applied. Icon: 🧪 teal.

Each entry shows: icon, label, occurrence tick, short_id of the lineage involved.

#### Lineages

Sortable **population board** table. Columns:

- **ID** — short_id (8 chars) + color swatch.
- **Cluster** — biofilm / motile / stress-tolerant / generalist / cryptic.
- **Phase** — dominant phase (the one with the most cells).
- **N** — total abundance, with a horizontal bar proportional to max(N).
- **µ (h⁻¹)** — base growth rate, derived from catalytic/repair domains.
- **ε** — repair efficiency (0..1).
- **Born** — the birth tick.

**Click on a column header** → sort by that column. Default: sort by N descending.

**Click on a row** → opens the **right drawer** with lineage detail.

#### Chemistry

**Phases × metabolites** heatmap (13 canonical metabolites: glucose, acetate, lactate, oxygen, NO₃, SO₄, H₂S, NH₃, H₂, PO₄, CO₂, CH₄, iron). Each cell has color intensity proportional to concentration, normalized to the maximum concentration of that metabolite across phases.

Below the heatmap: token cloud with `signal load` + `phage load` per phase.

**What to look for**:

- **Cycle closure**: in a healthy biotope after 200+ ticks, you will see for example high glucose in surface + high lactate in water_column + high acetate/CO₂ in sediment → functioning **cross-feeding**.
- **Anoxic gradient**: high O₂ in surface, low in deep/sediment.
- **High phage load** in a phase → arms race in progress.

#### Interventions

Operator panel. Only if you are `owner` of the biotope.

- **Status**: `Slot open` (you can intervene) or `Locked X` (countdown). The slot opens after the rate limit interval.
- **Buttons** (each consumes 1 slot):
  - **Pulse nutrients** → adds metabolites to the selected phase. Increases the concentration of the target metabolites of the currently active profiles. Useful to "unblock" a stagnant biotope.
  - **Inoculate plasmid** → introduces a known plasmid into the pool of the selected phase. Can recombine with present genomes via transformation (if recipients are competent).
  - **Trigger mixing event** → applies mixing across biotope phases. Temporarily homogenizes concentrations and populations. Equivalent to a storm in nature.
- **Recent interventions** — mini-table with kind, scope, tick.

A **confirm prompt** appears before applying each intervention. Click Cancel if you opened it by mistake.

### 5.6 Lineage drawer (right slide-in)

Opens by clicking a row in the Lineages tab. Shows:

- **Header**: short_id + phenotypic cluster.
- **Swatch + full ID** — copy/paste the UUID if you want to search for it in the audit.
- **KPIs**: total N, birth tick, µ (h⁻¹), ε (repair efficiency), main surface tags (max 4).
- **Per-phase abundance** — in which phase is the lineage most abundant? If it is split 50-50, it is likely in a niche partitioning scenario.

**Close** button at the bottom, or click the lineage row again, or press Esc.

### 5.7 Topology modal

Click ⚙ in the header → modal with network metadata:

- `biotope` — short_id.
- `zone` — ecological zone (e.g. lacustrine, swamp_edge).
- `coords` — display X,Y (for the world graph).
- `owner` — short_id of the owner player (or "wild" if none).
- `Neighbor ids` — list of biotopes connected via migration edge. Each id lets you navigate manually to the viewport `/biotopes/<id>`.

Neighbors are used by migration: cells can pass from one biotope to another along these edges (probability configured via `dilution_rate` × `migration_factor`).

---

## 6. Selective pressures: what to expect

Selective pressures are the mechanisms that cause some lineages to survive and others to die. Recognizing them helps you interpret what you see.

### 6.1 Metabolic toxicities

| Metabolite | Toxic threshold | Mechanism | Detoxify gene |
|---|---|---|---|
| `oxygen` | ≥50 µM equivalent | ROS damage on obligate anaerobes | `:catalytic_site` with `reaction_class=reduction` on O₂ target (catalase-like) |
| `h2s` | ≥20 µM | Cytochrome c inhibition | gene with specific detoxify path (Phase 21) |
| `lactate` | ≥30 (proxy for low pH) | Acidity — replaced by dynamic pH in Phase 21 | — |

**What you see**: a lineage without a catalase-like gene in a high-O₂ phase has an **effective kcat that decreases** monotonically. If O₂ keeps rising, the lineage slows growth until extinction.

### 6.2 Elemental deficits

P, N, Fe, S are required for biomass production. Below a floor (`@elemental_floor_per_cell = 0.001` per cell), the lineage **does not grow** (no fission). Mutations that reduce the Km of transport for the limiting nutrient are positively selected.

**What you see**: in a P-limited biotope, a lineage with `:substrate_binding(target=PO₄)` with high affinity_km grows faster than the others. In Audit, a `mutation_notable` event will appear when a mutant has found the winning combination.

### 6.3 Error catastrophe

Eigen threshold: for a genome of N genes with per-gene error rate µ, if `µ × N > 1`, mutations accumulated per replication are too many to be repaired, and fitness collapses.

**What you see**: `mutator` lineages (low `repair_efficiency`) speciate rapidly in the first 100–200 ticks, then begin to go extinct. In Events you will see a peak of `:lineage_born` followed by a wave of `:lineage_extinct`. In Audit, look for `error_catastrophe_death` events.

### 6.4 Phage predation

Prophages induce under stress (SOS active). One induction → lytic burst → 10–500 virions in the `phage_pool`. Virions decay with half-life 3–5 ticks. If the pool is high and there are recipients with a matching `:phage_receptor`, the infection rate takes off.

**What you see**:

- High phage load in a phase (visible in the token cloud below Chemistry).
- Repeated `:hgt_transfer` events (the `infection_step` hook emits this type).
- Lineages with loss-of-receptor that suddenly expand (positive selection on the mutation that removes the `:phage_receptor`). Classic arms race.

### 6.5 Bacteriocin warfare

A lineage with `[Substrate-binding(target=surface_tag_class)][Catalytic(membrane_disruption)]` produces bacteriocin. Co-resident lineages with that surface tag suffer `wall_progress` damage → lysis at division.

**What you see**: two lineages with conflicting surface tags in the same phase. One produces bacteriocin, the other decreases monotonically until extinction. Timeframe: 80–160 ticks (chronic warfare, deliberately slow in Arkea).

### 6.6 Plasmid displacement (incompatibility)

Two plasmids with the same `inc_group` do not coexist in the same lineage. One of them is `displaced` (lost at division).

**What you see**: after a plasmid inoculation via intervention, within 50–100 ticks one of the pre-existing plasmids of the same inc_group disappears from the lineage's genome. Audit: `plasmid_displaced` events.

---

## 7. Reading evolutionary signals

### 7.1 Where to look for signals

| Signal | Where to look |
|---|---|
| Speciation | Lineages tab (count increases); Events `:lineage_born`. |
| Clade extinction | Lineages tab (a cluster disappears); repeated Events `:lineage_extinct`. |
| HGT in progress | Audit with filter `hgt_event`; biotope Events tab. |
| Mutator emergence | Lineages tab grows quickly (5+ in 50 ticks); ε in the lineage drawer is low. |
| Cycle closure | Chemistry heatmap shows complementary patterns across phases. |
| Niche partitioning | Lineage drawer: per-phase abundance strongly imbalanced; high H′ in the phase inspector. |

### 7.2 Typical temporal patterns

#### Ticks 0–50: relative silence

The founding population is uniform. No visible speciation. You see global growth / contraction but a single genome. Chemistry shows how the seed is consuming the starting metabolites.

#### Ticks 50–200: first diversification

Accumulated mutations begin to produce `:lineage_born` events. Phase inspector richness rises from 1 to 3–5. The founder lineage (cluster `generalist`) typically still dominates but begins to cede ground.

#### Ticks 200–500: niche partitioning

Lineages specialize by phase. H′ in each phase stabilizes. `motile` and `biofilm` clusters appear. Cross-feeding visible in Chemistry.

#### Ticks 500–1000: arms race

If you inoculated a prophage or one emerged from a mutation, phage cycles begin. `:hgt_transfer` is frequent. The `stress-tolerant` cluster grows.

#### Ticks 1000+: pseudo-stationary state

Metabolic cycles are closed. Populations oscillate in dynamic equilibria. Rare events (inter-biotope HGT via migration, mass lysis from bacteriocin warfare) are still possible.

### 7.3 When to intervene

Interventions are your way to **perturb** a system in pseudo-equilibrium. Good moments:

- **Pulse nutrients** in an oligotrophic phase → observe which lineage responds fastest (whoever has the best Km).
- **Inoculate plasmid** in a genomically uniform population → observe whether vertical HGT + selection fix the plasmid.
- **Mixing event** in a biotope with biofilm formation → observe whether the aggregation resists mixing or dissolves.

**When NOT to intervene**: during an active arms race. Your perturbations mask the endogenous patterns you are trying to read.

---

## 8. World — macroscale overview

`/world` renders the **SVG graph** of active biotopes.

### 8.1 How to read the graph

- **Nodes** = biotopes.
  - **Radius** ∝ log(total N) + log(lineage count). A large node is a rich biotope.
  - **Color** = archetype (eutrophic_pond=amber, oligotrophic_lake=cyan, mesophilic_soil=lime, …).
  - **Outline / dot** = ownership (player_controlled=teal, wild=blue, foreign_controlled=rust).
- **Edges** = migration connections. Cells can pass from one node to another along these edges (probability modulated by `dilution_rate × migration_factor`).
- **Click on a node** → selects it; the right side panel populates.

### 8.2 Filter tabs

`All` / `Mine` / `Wild` to narrow the view. Useful in multi-player setups to avoid losing your biotopes in the noise.

### 8.3 Side panel

- **Operator** — your name + CTA to the Seed Lab (or inspection of the locked seed).
- **Selected** — detail of the selected biotope: archetype, ownership, tick, lineages, N, phases, "Open biotope →" link.
- **Distribution** — colored bar showing the breakdown by archetype + per-archetype list with count.

---

## 9. Audit — the event log

`/audit` exposes the **persisted log** of typed events (Block 13 of `DESIGN.md`). Append-only, survives biotope removal (tombstone IDs).

### 9.1 Event types

| Type | What it means |
|---|---|
| `mutation_notable` | Mutation with significant phenotypic effect (above relevance threshold). |
| `hgt_event` | Horizontal gene transfer. |
| `mass_lysis` | Mass lysis (≥10% of a phase's population dies in 1 tick). |
| `intervention` | Player intervention applied. |
| `colonization` | Provisioning of a new biotope from seed. |
| `mobile_element_release` | Plasmid or prophage released into the phase pool. |
| `community_provisioned` | Multi-seed inoculation (Phase 19). |

### 9.2 Filter tabs

Each filter restricts the query to a single `event_type`. `All` is the default.

### 9.3 Pagination

50 events per page. Pager shows `from–to of total`. Click `←` / `→` to navigate. Refresh `↻` reloads the first page (useful if the biotope is producing events while you watch).

### 9.4 Typical forensic queries

- "What happened in `biotope/<id>` in the last few hours?" → filter `All`, paginate until you find the biotope_id and read chronologically.
- "How many HGT events have I seen in total?" → filter `hgt_event` → look at `total` in the pager.
- "When was the first plasmid inoculated?" → filter `mobile_element_release` → go to the last page (descending order → last page = earliest chronologically).

### 9.5 Limits

- The payload preview shows at most 4 keys of the payload. For full-payload inspection, a direct SQL query is currently required (the Docs view coming soon will expose it).
- There is no full-text search — only filter by type. For searches on a specific lineage, copy the lineage UUID from the drawer and scan manually in the table.

---

## 10. Community — multi-seed runs

`/community` lists **biotopes inoculated in community mode** (`BIOLOGICAL-MODEL-REVIEW Phase 19`). These are biotopes started with **multiple founder seeds simultaneously** — useful for studying inter-strain interactions from tick 0.

Each entry shows:

- biotope archetype;
- number of founder seeds;
- inoculation phase (which phase the founders were introduced into);
- provisioning timestamp (UTC);
- current biotope tick;
- lineage count (increases with speciation);
- **Open →** link to the viewport.

**Use case**: comparing 2–3 seed strategies in the same biotope. Example:

- Seed A = mutator, conjugative_plasmid.
- Seed B = thrifty, latent_prophage.
- Seed C = balanced, none.

In 500 ticks, you will see who wins per phase. The winner is *not scripted* — it emerges from the interactions.

> **Community provisioning**: currently only via simulation API (`Arkea.Game.CommunityLab.provision_community/3`). A creation UI is on the roadmap.

---

## 11. Playbook: recurring scenarios

### 11.1 "I want to see fast speciation"

Setup:

- Archetype: `eutrophic_pond` (nutrient-rich, high turnover).
- `metabolism_profile`: `bloom`.
- `regulation_profile`: `mutator`.
- `mobile_module`: `none`.

What to expect:

- Ticks 30–80: first wave of `:lineage_born`.
- Ticks 100–200: 5+ distinct lineages.
- Ticks 200–400: error catastrophe hits some extreme mutators. `:lineage_extinct` events.
- Ticks 400+: semi-stable state with the "good" mutators (those that found a repair fix).

### 11.2 "I want to see a host-phage arms race"

Setup:

- Archetype: `oligotrophic_lake` (smaller populations, clearer dynamics).
- `metabolism_profile`: `thrifty`.
- `regulation_profile`: `responsive`.
- `mobile_module`: `latent_prophage`.

Add a **custom gene** with `[transmembrane_anchor, surface_tag]` to give the seed a `:phage_receptor`.

What to expect:

- Ticks 50–150: stress accumulates → SOS activates → prophage induction.
- Ticks 150–300: first wave of virions in the phage_pool. High phage load in surface.
- Ticks 300+: loss-of-receptor mutations become advantageous. You will see the `cryptic` cluster expand (lineages without phage_receptor).
- Ticks 500+: arms race in steady state — some have rebuilt the receptor (counteradvantage: lower fitness along other dimensions).

### 11.3 "I want to see metabolic cycle closure"

Setup:

- Archetype: `mesophilic_soil` (multiple phases with O₂ gradient).
- `metabolism_profile`: `balanced`.
- `regulation_profile`: `responsive`.
- `mobile_module`: `none`.

Add 2–3 **custom genes**:

- Gene 1: `[catalytic_site, substrate_binding]` on target `glucose`.
- Gene 2: `[catalytic_site, substrate_binding]` on target `lactate`.
- Gene 3: `[catalytic_site, substrate_binding]` on target `acetate`.

What to expect:

- Ticks 200–500: cross-feeding between the three phases. The Chemistry heatmap shows high glucose in surface, high lactate in water_column, high acetate/CO₂ in sediment.
- Ticks 500+: stable cycles. Total population remains nearly constant.

### 11.4 "I want to test my hypothesis"

Basic setup + intervention sequence:

1. Provision a seed with the configuration you want to test.
2. Wait until tick ~100 for the system to get started.
3. Open Audit, filter by `mutation_notable` for your biotope_id. Snapshot the baseline.
4. Open the Interventions tab, apply `nutrient_pulse` in a chosen phase.
5. Compare lineage list at tick 100 vs tick 200 vs tick 400.
6. Document in an external sheet (no in-app notes yet).

---

## 12. Extended glossary

### Biological

| Term | Meaning in Arkea |
|---|---|
| **Arkeon** | The individual proto-bacterial organism (genome + derived phenotype + abundance per phase). |
| **Lineage** | Descent with identical genome. A mutant is a **new** lineage. Counts toward `richness` and Shannon. |
| **Genome** | `chromosome` (list of genes) + `plasmids` (list of records `{genes, inc_group, copy_number, oriT_present}`) + `prophages` (list `{genes, state, repressor_strength}`). |
| **Gene** | Sequence of codons `0..19`, parsed into `domains`. Has intergenic blocks (expression / transfer / duplication). |
| **Domain** | Functional unit of the gene. 11 types (see §4.3). 3-codon `type_tag` + 20 `parameter_codons`. |
| **Phenotype** | Struct derived from the genome: `base_growth_rate`, `repair_efficiency`, `n_transmembrane`, `surface_tags`, `competence_score`, `dna_binding_affinity`, etc. |
| **Cluster** | Derived phenotypic category: `biofilm`, `motile`, `stress-tolerant`, `generalist`, `cryptic`. |
| **HGT** | Horizontal Gene Transfer — conjugation, transformation, transduction, phage infection. |
| **R-M** | Restriction-Modification — defense against exogenous DNA. Donor methylase bypasses the check (Arber-Dussoix). |
| **SOS response** | Response to DNA damage: raises µ and induces prophages. Trigger: `dna_damage_score` > threshold. |
| **Error catastrophe** | Fitness collapse when `µ × genome_size > 1` (Eigen quasispecies). |
| **Cross-feeding** | Metabolic output of one lineage becomes input for another. Cycle closure when closed to steady state. |

### Metabolites (13 canonical)

| Atom | Name | Notes |
|---|---|---|
| `glucose` | Glucose | Main carbon source in eutrophic. |
| `acetate` | Acetate | Fermentation output. |
| `lactate` | Lactate | Anaerobic fermentation output. |
| `oxygen` | O₂ | Toxic to anaerobes (>50 µM). |
| `nh3` | NH₃ | N source. |
| `no3` | NO₃⁻ | Electron acceptor in denitrification. |
| `so4` | SO₄²⁻ | Acceptor in dissimilatory sulfate reduction. |
| `h2s` | H₂S | Toxic to cytochrome c (>20 µM). Output of sulfate reduction. |
| `h2` | H₂ | Fermentation output, methanogenesis input. |
| `co2` | CO₂ | Respiration output + fixed via Calvin/Wood-Ljungdahl. |
| `ch4` | CH₄ | Methanogenesis output. |
| `po4` | PO₄³⁻ | Limiting in oligotrophic lake. |
| `iron` | Fe²⁺/Fe³⁺ | Cytochrome cofactor. |

### UI

| Term | Meaning |
|---|---|
| **Biotope** | Persistent world with N phases, K lineages, environmental conditions. |
| **Phase** | Sub-volume of the biotope with homogeneous conditions (surface, sediment, …). |
| **µ** | Specific growth rate (h⁻¹). |
| **ε** | Repair efficiency (0..1). |
| **H′** | Shannon diversity index calculated per phase. |
| **N** | Population (counts), per phase or total. |
| **D** | Dilution rate (%/tick). |
| **Phage load** | Sum of virion abundances in the `phage_pool` of a phase. |
| **Budget slot** | Anti-griefing rate limit for interventions. |
| **Audit log** | Append-only table of persisted typed events. |
| **Tick** | Simulator time unit. 1 tick = 5 minutes wall-clock. |

For the complete glossary of the biological model, see [`devel-docs/DESIGN.md`](devel-docs/DESIGN.md) (15 blocks) and [`devel-docs/CALIBRATION.md`](devel-docs/CALIBRATION.md) (numerical ranges).

---

## 13. FAQ

#### Can I pause the simulator?

No. The simulation is server-authoritative and runs 24/7. Pausing would break sharing: if A pauses their biotope, B cannot see it updating. To "pause your attention" simply close the browser.

#### Can I reset the biotope?

No. To start over, register a new player (different email). Locked biotopes remain in the runtime until natural extinction.

#### What happens if I close the browser during an intervention?

The intervention was already applied server-side when you clicked Confirm. The rate limit slot is already consumed. When you return, you only see the result.

#### Why don't I see events in the Events tab?

The biotope is young or stable. Check again from tick ~100 onward. If the queue is still empty at that point, verify that the `running` chip shows `live` (not `shell`) — if it shows `shell` the PubSub subscription has dropped, refresh the page.

#### My seed is locked — how do I test new configurations?

Create a new player (different email). The seed lock is per blueprint, not per instance.

#### Can I intervene on a wild biotope?

No. Only biotopes you have colonized (`player_controlled`) accept interventions. Wild biotopes are inspectable but read-only.

#### Will my draft gene edits be lost?

Yes, the draft is not persisted. If you reload the page, you start from scratch. Commit when you are satisfied.

#### I see `:hgt_transfer` events but I cannot tell which HGT channel was used

The event payload contains the channel (`:conjugation`, `:transformation`, `:transduction`, `:phage_infection`). Currently the preview shows only the first 4 keys of the payload — open Audit with filter `hgt_event` to see the full context (payload previews include the channel).

#### Can I force a high mutation rate on a single lineage?

No, not directly. Mutation rate is derived from the lineage's `repair_efficiency` (low ε → high µ). To have a hypermutator lineage, design the seed with `regulation_profile: mutator`. The SOS response further amplifies µ in stressed lineages.

#### Can lineages from other players migrate into my biotope?

Yes, if the biotopes are connected via migration edge in the world graph. Migration is bilateral and gated by dilution rate. Foreign cells can establish only if their phenotype withstands local selective pressures.

#### Is the JS bundle really that small?

Yes, ~50 KB minified. All graphics are native SVG rendered server-side via Phoenix LiveView. No WebGL, no canvas, no JS framework.

#### Where do I find the model constants?

All key constants + biological literature ranges are in [`devel-docs/CALIBRATION.md`](devel-docs/CALIBRATION.md). Overrides for scientific benchmarks are in the same section.

#### How do I know if my hypothesis is "original"?

There is no lookup system. Compare your seed with those in `/community` if any exist. For the prototype there is no leaderboard or originality mechanism.

---

## 14. Troubleshooting

### Symptom: "Biotope viewport shows No phases / zero population"

**Probable cause**: the `Biotope.Server` for that id is not registered in the runtime. This can happen if:

- You reset the database (`mix ecto.reset`) but the BEAM runtime is still alive.
- Default scenario seeding was disabled (commit `fda5031`).

**Fix**: provision a new seed from the Seed Lab (the action spawns a fresh `Biotope.Server`).

### Symptom: "Events tab is always empty"

**Probable cause**: your PubSub subscription to the biotope has dropped.

**Verify**:

1. Sidebar KPI: the `Stream` chip must show `live` (green). If it shows `shell`, refresh.
2. Browser console (F12): look for WebSocket errors. If you see repeated disconnections, check connectivity to the server.

### Symptom: "Intervention button is always disabled"

**Possible causes**:

- **You are not the owner of the biotope**. Check the `Topology modal` (⚙ in header): if `owner` is "wild" or another player, you cannot intervene.
- **Rate limit active**. The status shows `Locked X` with a countdown. Wait.
- **`selected_phase_name` is nil**. Click on a phase in the sidebar before applying the intervention (for phase-scoped interventions).

### Symptom: "I don't see HGT events despite having a conjugative_plasmid"

**Possible causes**:

- Population density too low. Conjugation requires a contact rate proportional to `density²`. Wait until ticks ~50–100 for the population to grow.
- The plasmid does not have an `oriT_site` in its `regulatory_block`. In Audit, look for `mobile_element_release` for your biotope to verify whether the plasmid was released into the phase pool.
- Potential recipients have R-M defense that digests the plasmid. Look for `rm_digestion` events in audit.

### Symptom: "My mutator strain goes extinct immediately"

**Probable cause**: error catastrophe. With very low `repair_efficiency`, mutations accumulated per replication exceed the Eigen threshold and fitness collapses.

**Fix**:

- Add a `:repair_fidelity` domain with high parameters to the seed to compensate.
- Reduce the mutator profile aggressiveness (switch from `mutator` to `responsive`).

### Symptom: "Chemistry heatmap shows all-yellow columns (saturation)"

**Probable cause**: one phase has a concentration much higher than all the others, and normalization sets that concentration to 1, collapsing the others to near-zero.

**Workaround**: inspect point values via the Phase inspector (KPIs in sidebar) for the phase of interest, or use Audit for specific queries.

### Symptom: "Performance degrades with many biotopes"

**Probable cause**: the prototype runs on a single-node BEAM. Each biotope is an independent process, but SVG rendering in the browser scales with (lineage × particle count). With 100+ lineages in a biotope, the viewport can slow down.

**Mitigation**: the `MAX_PHASE_PARTICLES = 60` cap already limits rendering. For highly populated biotopes, use the Lineages tab (denser information) instead of the visual scene.

### Symptom: "I want to close the session and start from scratch"

`/players/log-out` closes the session. It takes you back to `/`. To start from scratch, register a new account with a different email. The old account remains accessible via "Resume player".

---

## Feedback and contributions

Bugs, suggestions, scientific walkthroughs to validate → see [README.en.md](README.en.md) for project channels. The biological model is evolving: the roadmap is in [`devel-docs/BIOLOGICAL-MODEL-REVIEW.md`](devel-docs/BIOLOGICAL-MODEL-REVIEW.md).

If you find a calibration that does not match your intuition as a microbiologist, open an issue with a primary literature citation. All key parameters are already mapped to the biological range in [`devel-docs/CALIBRATION.md`](devel-docs/CALIBRATION.md), so we can compare and correct.
