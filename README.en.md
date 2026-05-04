> 🇮🇹 [Italiano](README.md) · 🇬🇧 English (this page)

# Arkea

Persistent shared simulation of proto-bacterial organism evolution. Target audience: biologists, microbiologists, geneticists, molecular biologists.

Players create an account, design an *Arkeon* seed (cellular structure + generative genome), and colonize a controlled biotope inside an ecosystem that evolves 24/7 server-side. The simulation is authoritative: each biotope is a BEAM process with a pure-functional tick; typed events (HGT, notable mutations, lysis, interventions) are persisted to PostgreSQL as an append-only audit log.

Arkea **is not a competitive game**: no scoreboard, no contest loop. The observable phenomenon is the same you observe under a microscope in a natural environment — speciation, coevolution, host-phage arms race, plasmid displacement, error catastrophe.

## Scientific features

- **Generative genome**: every gene is a codon sequence, parsed into `domains` (11 functional types: substrate-binding, catalytic, transmembrane, channel, energy-coupling, DNA-binding, regulator-output, ligand-sensor, structural-fold, surface-tag, repair-fidelity).
- **Michaelis-Menten metabolism** over 13 metabolites (glucose, lactate, acetate, NH₃, NO₃⁻, SO₄²⁻, H₂S, Fe²⁺/Fe³⁺, H₂, CO₂, CH₄, oxygen).
- **Complete HGT**: plasmid conjugation, natural transformation, transduction (generalized + specialized), closed phage cycle (SOS induction → lytic burst → virion pool → infection with receptor matching).
- **R-M defenses** (Restriction-Modification) with Arber-Dussoix host modification.
- **4D Gaussian quorum sensing**, intra-biotope phases (surface/water-column/sediment/biofilm/…), inter-biotope migration.
- **Continuous biomass** (membrane/wall/dna progress) → lysis at division → error catastrophe as natural upper bound on µ.
- **SOS response** triggered by DNA damage score.
- **Bacteriocins** as surface-tag arms race.
- **Documented calibration** in [`devel-docs/CALIBRATION.md`](devel-docs/CALIBRATION.md): every constant mapped to the biological range from primary literature.

## Stack

- **Elixir + Phoenix LiveView** (100% server-authoritative rendering; no JS framework, no SPA build).
- **PostgreSQL via Ecto** for biotope persistence, blueprints, audit log, player accounts.
- **Native SVG** for graphics (circular chromosome, biotope scene, world graph). JS bundle ~50 KB.
- **Single-node BEAM**: each biotope is an `Arkea.Sim.Biotope.Server` process registered under `Arkea.Sim.Registry`.

## Routes

| Route | View | What it does |
|---|---|---|
| `/` | Login | Creates or resumes a player account |
| `/dashboard` | Dashboard | Card-link panels for World, Seed Lab, owned biotopes, Community, Audit |
| `/world` | World | SVG graph of active biotopes + selected side panel |
| `/seed-lab` | Seed Lab | Visual phenotype + genome editor; circular chromosome with domain crown |
| `/biotopes/:id` | Biotope viewport | Realtime SVG scene + phase sidebar + lineage drawer + bottom tabs (Events / Lineages / Chemistry / Interventions) |
| `/audit` | Audit | Paginated stream of `audit_log` with filter tabs |
| `/community` | Community | Read-only list of multi-seed runs |

## Local setup

```bash
cd arkea
mix setup
mix ecto.migrate
mix phx.server
```

Then open [`localhost:4000`](http://localhost:4000) and create a player from route `/`.

Requirements: Erlang 28.x · Elixir 1.19.x · PostgreSQL ≥14.

## Repo structure

```
Arkea/
├── arkea/                    # Phoenix application
│   ├── lib/
│   │   ├── arkea/            # sim core, persistence, game logic
│   │   ├── arkea_web/        # LiveView, components, controllers
│   │   └── arkea/views/      # pure view-model layer
│   ├── assets/css/arkea/     # 11 CSS modules (tokens, shell, panel, …)
│   └── test/                 # 429 tests, 131 properties
├── devel-docs/               # development documentation (design, plans)
├── USER-MANUAL.md            # user manual for biologists
├── README.md                 # Italian version of this page
└── LICENSE
```

## Documents

### For users

- [USER-MANUAL.en.md](USER-MANUAL.en.md) — user manual for biologists: registration, seed design, colonization, biotope observation, interventions, glossary.

### For developers (`devel-docs/`)

- [DESIGN.en.md](devel-docs/DESIGN.en.md) — complete design document, 15 blocks (architecture, biological model, environment, population, engine, metabolic inventory, generative domain system, selective pressures, quorum sensing, network topology, time, micro/macroscale, anti-griefing, stack, integral use case).
- [DESIGN_STRESS-TEST.en.md](devel-docs/DESIGN_STRESS-TEST.en.md) — walk-through "Chronicles of a Contested Estuary" that validates design coherence across all 15 blocks.
- [IMPLEMENTATION-PLAN.en.md](devel-docs/IMPLEMENTATION-PLAN.en.md) — architectural choice (Active Record + structured audit log + pure-functional tick) and implemented roadmap.
- [BIOLOGICAL-MODEL-REVIEW.en.md](devel-docs/BIOLOGICAL-MODEL-REVIEW.en.md) — scientific review of the biological model and intervention plan to close the gaps (complete HGT, phage cycle, R-M, transformation, transduction, xenobiotics/RAS, biomass, SOS, error catastrophe, operons, bacteriocins).
- [CALIBRATION.en.md](devel-docs/CALIBRATION.en.md) — calibration appendix: declared time and concentration scales, key code constants mapped to biological ranges, overrides for scientific benchmarks.
- [UI-REWRITE-PLAN.en.md](devel-docs/UI-REWRITE-PLAN.en.md) — UI/UX rewrite plan (8 phases U0..U7+, all delivered): PixiJS removal, layout system, view-by-view breakdown, components, CSS refactor, view-model layer.

## Project subagents

In `.claude/agents/`: five specialized agents (Elixir/OTP, Ecto/Postgres, biological realism, property testing, design coherence) + a `bilingual-docs-maintainer` that keeps IT↔EN document pairs aligned.

## License

[GNU General Public License v3.0](LICENSE) (GPL-3.0).
