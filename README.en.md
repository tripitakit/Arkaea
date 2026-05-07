> 🇮🇹 [Italiano](README.md) · 🇬🇧 English (this page)

# Arkea

**Arkea is a persistent evolutionary sandbox of proto-bacterial organisms.** Target audience: microbiologists, geneticists, molecular biologists, and researchers interested in observing microbial evolution as an emergent phenomenon — not as a canned animation.

Players design an *Arkeon* (cellular composition + generative genome) and introduce it into a biotope that keeps evolving 24/7 server-side. The observable phenomenon is the same one you'd watch under a microscope in a natural microbial system: speciation, host-phage coevolution, plasmid displacement, error catastrophe, syntrophy, bacterial warfare. **No scoreboard, no contest loop** — observation is the point.

## Biological model

The genome is a codon sequence parsed into **11 functional domain types** (substrate-binding, catalytic, transmembrane, channel, energy-coupling, DNA-binding, regulator-output, ligand-sensor, structural-fold, surface-tag, repair-fidelity). Every lineage capability — uptake, catalysis, resistance, communication, defence — emerges from domain composition, with no finite catalogs or hardcoded special cases.

### Mechanisms simulated end-to-end

- **Michaelis-Menten metabolism** over 13 metabolites, with closed C/N/S/Fe/H₂ cycles and syntrophy emerging from stoichiometric cross-feeding.
- **HGT across four channels**: plasmid conjugation with inc-group entry exclusion, natural transformation (ComEC/ComEA/ComX-like competence triad), lateral transduction (Chen 2018), phage infection with receptor matching.
- **Restriction-Modification defenses** with bypass via host methylation (Arber-Dussoix).
- **Closed phage cycle**: RecA-mediated SOS induction → lytic burst → virion decay → re-infection with a cI/cro switch derived from the cassette's `:dna_binding` domains.
- **Mutation + SOS response**: damage accumulation, mutator strains emerging under stress, error catastrophe as the *theoretical ceiling* given by Eigen `(1−µ/L)^L > 1/σ`.
- **4D quorum sensing**: Gaussian LuxR/AHL-like receptor matching, with communicative drift acting as a speciation mechanism.
- **Bacteriocins**: kin-recognition warfare with mandatory producer/immunity coupling (self-destruction without an immunity tag).
- **Xenobiotics and RAS**: β-lactamase-driven feedback over a shared environmental pool with dynamic MIC.
- **Continuous biomass** (membrane / wall / DNA progress) → lysis at division → drives the loss-of-receptor arms race naturally.
- **Intra-biotope phase model**: surface, water column, sediment, biofilm — each with its own chemistry, oxygenation and dilution; stochastic mixing events on a Poisson cadence.

Every numeric constant is anchored to primary literature with an explicit biological range (see [`devel-docs/04-CALIBRATION.en.md`](devel-docs/04-CALIBRATION.en.md)).

## Architecture

- **Elixir + Phoenix LiveView**: 100% server-authoritative rendering, zero JS framework, zero SPA build.
- **Single-node BEAM**: each biotope is an `Arkea.Sim.Biotope.Server` process with a pure-functional tick, deterministically reproducible from the RNG seed.
- **PostgreSQL via Ecto** for biotope, lineage, append-only audit log and player-account persistence.
- **Native SVG** for the circular chromosome, biotope scene and world graph. JS bundle ≈ 50 KB.

## Local setup

```bash
cd arkea
mix setup
mix ecto.migrate
mix phx.server
```

Then open [`localhost:4000`](http://localhost:4000) and create a player from route `/`.

Requirements: Erlang 28.x · Elixir 1.19.x · PostgreSQL ≥14.

## License

[GNU General Public License v3.0](LICENSE) (GPL-3.0).
