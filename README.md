> 🇮🇹 Italiano (questa pagina) · [🇬🇧 English](README.en.md)

# Arkea

Simulazione persistente condivisa di evoluzione di organismi proto-batterici. I player creano o riprendono un account, progettano un *Arkeon* seed (struttura cellulare + genoma) e avviano la colonizzazione di un biotopo controllato in un ecosistema che evolve 24/7 server-side. Pubblico target: biologi, microbiologi, genetisti, biologi molecolari.

**Stato**: fasi `0–11` completate + UI Evolution ✅. Shell web operativa con accesso player, `World`, `Seed Lab`, viewport autoritativo del biotopo, persistenza runtime, recovery e scenario “Cronache” riprodotto sul prototipo. Interfaccia minimale scientificamente corretta: layout `biotope-grid` (55fr/45fr, viewport-height), heatmap chimica 13-metaboliti, Shannon diversity H′, animazioni PixiJS per eventi evolutivi (born/extinct/HGT).

**Stack**: Elixir + Phoenix (LiveView + Channels) · PostgreSQL via Ecto · PixiJS per la vista 2D WebGL · prototipo su VPS DigitalOcean.

## Shell corrente

- `/` — accesso player: creazione account o resume via email
- `/world` — overview condivisa del network di biotopi e degli ecotipi attivi
- `/seed-lab` — costruzione del seed, editor fenotipico/genomico e prima colonizzazione
- `/biotopes/:id` — viewport realtime del biotopo con telemetria, ispezione di fase e interventi autorevoli

La web app resta una **shared simulation**, non un game competitivo: niente scoreboard, presence o contest loop nel runtime corrente.

## Avvio locale rapido

```bash
cd arkea
mix setup
mix ecto.migrate
mix phx.server
```

Poi apri [`localhost:4000`](http://localhost:4000) e crea o riprendi un player dalla route `/`.

## Documenti

- [DESIGN.md](DESIGN.md) — documento di design completo, 15 blocchi (architettura, modello biologico, ambiente, popolazione, motore, inventario metabolico, sistema generativo dei domini, pressioni selettive, quorum sensing, topologia network, tempo, micro/macroscala, anti-griefing, stack, caso d'uso integrale)
- [DESIGN_STRESS-TEST.md](DESIGN_STRESS-TEST.md) — walk-through "Cronache di un estuario contestato" che valida la coerenza del design attraversando tutti i 15 blocchi
- [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md) — scelta architetturale (Active Record + audit log strutturato + tick pure-functional), analisi dell'alternativa Event Sourcing scartata, roadmap implementata e note di consolidamento su UI, persistenza e onboarding player
- [BIOLOGICAL-MODEL-REVIEW.md](BIOLOGICAL-MODEL-REVIEW.md) — revisione scientifica del modello biologico implementato e piano di intervento per chiudere i gap (HGT completo, ciclo fagico, R-M, trasformazione, trasduzione, xenobiotici/RAS, biomassa, SOS, error catastrophe, operoni, bacteriocine)
- [CALIBRATION.md](CALIBRATION.md) — appendice di calibrazione: scale temporali e di concentrazione dichiarate, costanti chiave del codice mappate al range biologico, changelog Phase 20 e override per benchmark scientifici
- [UI-REWRITE-PLAN.md](UI-REWRITE-PLAN.md) — piano di riscrittura UI/UX: principi guida, rimozione PixiJS, sistema di layout, vista per vista, componenti, refactor CSS, view-model layer, fasi di migrazione U0–U7

## Subagent di progetto

In `.claude/agents/`: cinque agent specializzati (Elixir/OTP, Ecto/Postgres, biological realism, property testing, design coherence) che assistono lo sviluppo nel loro dominio specifico.

## Licenza

[GNU General Public License v3.0](LICENSE) (GPL-3.0).
