> 🇮🇹 [Italiano](README.md) · 🇬🇧 English (this page)

# Arkea

Persistent MMO simulation of proto-bacterial organism evolution. The player designs an *Arkeon* (cellular structure + genome) and trains it in a shared ecosystem that evolves 24/7 server-side. Target audience: biologists, microbiologists, geneticists, molecular biologists.

**Status**: consolidated design (15 blocks), validated by tabletop stress test, defined architecture. Ready for Phase 0 of implementation.

**Stack**: Elixir + Phoenix (LiveView + Channels) · PostgreSQL via Ecto · PixiJS for the 2D WebGL view · prototype on DigitalOcean VPS.

## Documents

- [DESIGN.en.md](DESIGN.en.md) — complete design document, 15 blocks (architecture, biological model, environment, population, engine, metabolic inventory, generative domain system, selective pressures, quorum sensing, network topology, time, micro/macroscale, anti-griefing, stack, integral use case)
- [DESIGN_STRESS-TEST.en.md](DESIGN_STRESS-TEST.en.md) — walk-through "Chronicles of a contested estuary" that validates design coherence by traversing all 15 blocks
- [IMPLEMENTATION-PLAN.en.md](IMPLEMENTATION-PLAN.en.md) — architectural choice (Active Record + structured audit log + pure-functional tick), analysis of the discarded Event Sourcing alternative, roadmap of 12 incremental phases, development discipline

## Project subagents

In `.claude/agents/`: five specialized agents (Elixir/OTP, Ecto/Postgres, biological realism, property testing, design coherence) that assist development in their specific domain.

## License

[GNU General Public License v3.0](LICENSE) (GPL-3.0).
