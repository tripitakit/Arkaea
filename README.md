# Arkea

Simulazione MMO persistente di evoluzione di organismi proto-batterici. Il giocatore progetta un *Arkeon* (struttura cellulare + genoma) e lo allena in un ecosistema condiviso che evolve 24/7 server-side. Pubblico target: biologi, microbiologi, genetisti, biologi molecolari.

**Stato**: design consolidato (15 blocchi), validato da stress test "a tavolino", architettura definita. Pronto per Fase 0 di implementazione.

**Stack**: Elixir + Phoenix (LiveView + Channels) · PostgreSQL via Ecto · PixiJS per la vista 2D WebGL · prototipo su VPS DigitalOcean.

## Documenti

- [INCEPTION.md](INCEPTION.md) — la richiesta originale che ha dato avvio al progetto
- [DESIGN.md](DESIGN.md) — documento di design completo, 15 blocchi (architettura, modello biologico, ambiente, popolazione, motore, inventario metabolico, sistema generativo dei domini, pressioni selettive, quorum sensing, topologia network, tempo, micro/macroscala, anti-griefing, stack, caso d'uso integrale)
- [DESIGN_STRESS-TEST.md](DESIGN_STRESS-TEST.md) — walk-through "Cronache di un estuario contestato" che valida la coerenza del design attraversando tutti i 15 blocchi
- [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md) — scelta architetturale (Active Record + audit log strutturato + tick pure-functional), analisi dell'alternativa Event Sourcing scartata, roadmap di 12 fasi incrementali, disciplina di sviluppo

## Subagent di progetto

In `.claude/agents/`: cinque agent specializzati (Elixir/OTP, Ecto/Postgres, biological realism, property testing, design coherence) che assistono lo sviluppo nel loro dominio specifico.

## Licenza

Da definire.
