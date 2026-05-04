> 🇮🇹 Italiano (questa pagina) · [🇬🇧 English](README.en.md)

# Arkea

Simulazione persistente condivisa di evoluzione di organismi proto-batterici. Pubblico target: biologi, microbiologi, genetisti, biologi molecolari.

I player creano un account, progettano un *Arkeon* seed (struttura cellulare + genoma generativo) e colonizzano un biotopo controllato all'interno di un ecosistema che evolve 24/7 server-side. La simulazione è autoritativa: ogni biotopo è un processo BEAM con tick puro-funzionale; gli eventi tipizzati (HGT, mutazioni notevoli, lisi, interventi) vengono persistiti su PostgreSQL come audit log append-only.

Arkea **non è un game competitivo**: niente scoreboard, niente contest loop. Il fenomeno osservabile è lo stesso che osservi al microscopio in un ambiente naturale — speciazione, coevoluzione, arms race ospite-fago, displacement plasmidico, error catastrophe.

## Caratteristiche scientifiche

- **Genoma generativo**: ogni gene è una sequenza di codoni, parsata in `domains` (11 tipi funzionali: substrate-binding, catalytic, transmembrane, channel, energy-coupling, DNA-binding, regulator-output, ligand-sensor, structural-fold, surface-tag, repair-fidelity).
- **Metabolismo Michaelis-Menten** su 13 metaboliti (glucosio, lattato, acetato, NH₃, NO₃⁻, SO₄²⁻, H₂S, Fe²⁺/Fe³⁺, H₂, CO₂, CH₄, ossigeno).
- **HGT completo**: coniugazione plasmidica, trasformazione naturale, trasduzione (generalized + specialized), ciclo fagico chiuso (induction da SOS → lytic burst → virion pool → infection con receptor matching).
- **Difese R-M** (Restriction-Modification) con Arber-Dussoix host modification.
- **Quorum sensing 4D gaussiano**, fasi intra-biotopo (surface/water-column/sediment/biofilm/...), migrazione inter-biotopo.
- **Biomassa continua** (membrane/wall/dna progress) → lisi alla divisione → error catastrophe come upper bound naturale a µ.
- **SOS response** trigger via DNA damage score.
- **Bacteriocine** come arms race surface-tag.
- **Calibrazione documentata** in [`devel-docs/CALIBRATION.md`](devel-docs/CALIBRATION.md): ogni costante mappata al range biologico di letteratura primaria.

## Stack

- **Elixir + Phoenix LiveView** (rendering 100% server-authoritative; nessun framework JS, nessuna build SPA).
- **PostgreSQL via Ecto** per persistenza biotopi, blueprints, audit log, accounts player.
- **SVG nativo** per la grafica (cromosoma circolare, scena biotope, world graph). Bundle JS ~50 KB.
- **Single-node BEAM**: ogni biotopo è un processo `Arkea.Sim.Biotope.Server` registrato sotto `Arkea.Sim.Registry`.

## Routes

| Route | Vista | Cosa fa |
|---|---|---|
| `/` | Login | Crea o riprende un account player |
| `/dashboard` | Dashboard | Pannelli card-link su World, Seed Lab, biotopi posseduti, Community, Audit |
| `/world` | World | Grafo SVG dei biotopi attivi + side panel selezionato |
| `/seed-lab` | Seed Lab | Editor visuale di fenotipo + genoma; cromosoma circolare con geni-segmento e domini come sotto-archi colorati |
| `/biotopes/:id` | Biotope viewport | Scena SVG realtime + sidebar fasi + drawer lineage + bottom tabs (Events / Lineages / Chemistry / Interventions) |
| `/audit` | Audit | Stream paginato di `audit_log` con filter tabs |
| `/community` | Community | Lista read-only di multi-seed runs |

## Avvio locale

```bash
cd arkea
mix setup
mix ecto.migrate
mix phx.server
```

Poi apri [`localhost:4000`](http://localhost:4000) e crea un player dalla route `/`.

Requisiti: Erlang 28.x · Elixir 1.19.x · PostgreSQL ≥14.

## Struttura repo

```
Arkea/
├── arkea/                    # Phoenix application
│   ├── lib/
│   │   ├── arkea/            # sim core, persistence, game logic
│   │   ├── arkea_web/        # LiveView, components, controllers
│   │   └── arkea/views/      # pure view-model layer
│   ├── assets/css/arkea/     # 11 moduli CSS (tokens, shell, panel, …)
│   └── test/                 # 429 test, 131 properties
├── devel-docs/               # documentazione di sviluppo (design, piani)
├── USER-MANUAL.md            # manuale d'uso per biologi
├── README.md                 # questa pagina
└── LICENSE
```

## Documenti

### Per gli utenti

- [USER-MANUAL.md](USER-MANUAL.md) — manuale d'uso per biologi: registrazione, design del seed, colonizzazione, osservazione del biotopo, interventi, glossario.

### Per gli sviluppatori (`devel-docs/`)

- [DESIGN.md](devel-docs/DESIGN.md) — documento di design completo, 15 blocchi (architettura, modello biologico, ambiente, popolazione, motore, inventario metabolico, sistema generativo dei domini, pressioni selettive, quorum sensing, topologia network, tempo, micro/macroscala, anti-griefing, stack, caso d'uso integrale).
- [DESIGN_STRESS-TEST.md](devel-docs/DESIGN_STRESS-TEST.md) — walk-through "Cronache di un estuario contestato" che valida la coerenza del design attraverso tutti i 15 blocchi.
- [IMPLEMENTATION-PLAN.md](devel-docs/IMPLEMENTATION-PLAN.md) — scelta architetturale (Active Record + audit log strutturato + tick pure-functional) e roadmap implementata.
- [BIOLOGICAL-MODEL-REVIEW.md](devel-docs/BIOLOGICAL-MODEL-REVIEW.md) — revisione scientifica del modello biologico e piano di intervento per chiudere i gap (HGT completo, ciclo fagico, R-M, trasformazione, trasduzione, xenobiotici/RAS, biomassa, SOS, error catastrophe, operoni, bacteriocine).
- [UI-OPTIMIZATION-PLAN.md](UI-OPTIMIZATION-PLAN.md) — piano fasato (A–G) per rendere l'interfaccia un banco di indagine scientifica: event pipeline backfill, time-series visualization, phylogeny, HGT ledger Sankey, comparazione seed/biotopi, export JSON/CSV/FASTA/Newick, onboarding e scenario preset.
- [CALIBRATION.md](devel-docs/CALIBRATION.md) — appendice di calibrazione: scale temporali e di concentrazione dichiarate, costanti chiave del codice mappate al range biologico, override per benchmark scientifici.
- [UI-REWRITE-PLAN.md](devel-docs/UI-REWRITE-PLAN.md) — piano di riscrittura UI/UX (8 fasi U0..U7+ tutte consegnate): rimozione PixiJS, sistema di layout, vista per vista, componenti, refactor CSS, view-model layer.

## Subagent di progetto

In `.claude/agents/`: cinque agent specializzati (Elixir/OTP, Ecto/Postgres, biological realism, property testing, design coherence) + un `bilingual-docs-maintainer` che mantiene allineate le coppie IT↔EN.

## Licenza

[GNU General Public License v3.0](LICENSE) (GPL-3.0).
