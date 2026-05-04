> 🇮🇹 [Italiano](README.md) · 🇬🇧 English (this page)

# Arkea

Persistent shared simulation of proto-bacterial organism evolution. Players create or resume an account, design an *Arkeon* seed (cellular structure + genome), and start colonization in a controlled biotope inside an ecosystem that evolves 24/7 server-side. Target audience: biologists, microbiologists, geneticists, molecular biologists.

**Status**: phases `0–11` completed + UI Evolution ✅. Operational web shell with player access, `World`, `Seed Lab`, authoritative biotope viewport, runtime persistence/recovery, and the “Chronicles” scenario reproduced on the prototype. Minimal scientifically-correct interface: `biotope-grid` layout (55fr/45fr, viewport-height), 13-metabolite chemistry heatmap, Shannon diversity H′, and PixiJS event animations (born/extinct/HGT).

**Stack**: Elixir + Phoenix (LiveView + Channels) · PostgreSQL via Ecto · PixiJS for the 2D WebGL view · prototype on DigitalOcean VPS.

## Current shell

- `/` — player access: account creation or email-based resume
- `/world` — shared overview of the biotope network and active ecotypes
- `/seed-lab` — seed construction, phenotype/genome editor, and first colonization
- `/biotopes/:id` — realtime biotope viewport with telemetry, phase inspection, and authoritative interventions

The web app remains a **shared simulation**, not a competitive game: no scoreboard, presence, or contest loop are part of the current runtime.

## Quick local start

```bash
cd arkea
mix setup
mix ecto.migrate
mix phx.server
```

Then open [`localhost:4000`](http://localhost:4000) and create or resume a player from route `/`.

## Documents

- [DESIGN.en.md](DESIGN.en.md) — complete design document, 15 blocks (architecture, biological model, environment, population, engine, metabolic inventory, generative domain system, selective pressures, quorum sensing, network topology, time, micro/macroscale, anti-griefing, stack, integral use case)
- [DESIGN_STRESS-TEST.en.md](DESIGN_STRESS-TEST.en.md) — walk-through "Chronicles of a contested estuary" that validates design coherence by traversing all 15 blocks
- [IMPLEMENTATION-PLAN.en.md](IMPLEMENTATION-PLAN.en.md) — architectural choice (Active Record + structured audit log + pure-functional tick), analysis of the discarded Event Sourcing alternative, implemented roadmap, and consolidation notes on UI, persistence, and player onboarding
- [BIOLOGICAL-MODEL-REVIEW.en.md](BIOLOGICAL-MODEL-REVIEW.en.md) — scientific review of the implemented biological model and intervention plan to close the gaps (complete HGT, phage cycle, R-M, transformation, transduction, xenobiotics/RAS, biomass, SOS, error catastrophe, operons, bacteriocins)
- [CALIBRATION.en.md](CALIBRATION.en.md) — calibration appendix: declared time and concentration scales, key code constants mapped to biological ranges, Phase 20 changelog, and overrides for scientific benchmarks
- [UI-REWRITE-PLAN.en.md](UI-REWRITE-PLAN.en.md) — UI/UX rewrite plan: guiding principles, PixiJS removal, layout system, view-by-view breakdown, components, CSS refactor, view-model layer, migration phases U0–U7

## Project subagents

In `.claude/agents/`: five specialized agents (Elixir/OTP, Ecto/Postgres, biological realism, property testing, design coherence) that assist development in their specific domain.

## License

[GNU General Public License v3.0](LICENSE) (GPL-3.0).
