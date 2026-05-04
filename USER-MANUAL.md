> 🇮🇹 Italiano (questa pagina) · [🇬🇧 English](USER-MANUAL.en.md)

# Manuale d'uso · Arkea

Benvenuto in **Arkea**. Questo manuale ti guida nella creazione del tuo primo player, nella progettazione di un *Arkeon* seed, nella colonizzazione di un biotopo e nell'osservazione dell'evoluzione che ne consegue.

Arkea è una **simulazione persistente condivisa** scritta per chi ha solide basi di microbiologia / biologia molecolare. Non aspettarti shortcut narrativi: ogni meccanismo riflette una controparte biologica reale (referenze in [`devel-docs/CALIBRATION.md`](devel-docs/CALIBRATION.md)).

> **Stato del runtime**: la simulazione gira 24/7 sul server. Quando ti disconnetti, il tuo biotopo continua ad evolvere. Quando torni, troverai la popolazione al tick corrente.

---

## 1. Primo accesso

### 1.1 Creare un account

1. Apri la home (`/`) e scegli **"Crea player"**.
2. Inserisci `display_name` (visibile in `Audit` e `Community`) ed `email` (chiave di resume).
3. Al click su "Create player" vieni reindirizzato al **Seed Lab**.

Non c'è password: il resume è basato sull'email. Cambia indirizzo se vuoi separare identità.

### 1.2 Riprendere

Da `/` scegli **"Riprendi player"** e inserisci l'email registrata. Vieni reindirizzato alla **Dashboard**.

---

## 2. Dashboard

La Dashboard è la landing post-login. È strutturata in **6 pannelli card-link**:

| Pannello | Apre | Cosa contiene |
|---|---|---|
| **World** | `/world` | Grafo SVG dei biotopi attivi (tuoi + wild + di altri player) |
| **Seed Lab** | `/seed-lab` | Editor del seed; bloccato dopo la prima colonizzazione |
| **My Biotopes** | `/biotopes/:id` | Lista compatta dei biotopi che possiedi, con tick e lineage count |
| **Community** | `/community` | Run multi-seed di altri player (read-only) |
| **Audit** | `/audit` | Stream globale di eventi tipizzati persistiti |
| **Docs** | (placeholder) | Riferimenti DESIGN/CALIBRATION (rendering Markdown in arrivo) |

Click su un pannello per aprire la vista a pagina intera. Nessuna view ha scrollbar globale: quando i contenuti eccedono, scrollano i sotto-pannelli.

---

## 3. Seed Lab — progettare l'Arkeon iniziale

Il Seed Lab è il punto di partenza: scegli **archetipo del biotopo da colonizzare**, **profili di base** del fenotipo, e — se vuoi — **componi geni custom** dominio per dominio.

### 3.1 Form principale (colonna sinistra)

- **Nome del seed**: identifica il blueprint nel sistema di provisioning.
- **Archetipo del biotopo**: 3 opzioni starter (Eutrophic Pond, Oligotrophic Lake, Mesophilic Soil). Ogni archetipo ha fasi, metaboliti di starting pool e zone diverse — vedi descrizioni nelle radio cards.
- **Cassette metabolica** (`metabolism_profile`): seleziona il profilo che imposta i kcat/Km dei domini catalitici di base. Opzioni: balanced / thrifty / bloom.
- **Profilo di membrana**: porous / fortified / salinity-tuned. Modula tolleranza osmotica e n_transmembrane.
- **Modalità di regolazione**: responsive / steady / mutator. Impatta `repair_efficiency` e dna_binding_affinity.
- **Modulo mobile**: none / conjugative_plasmid / latent_prophage. Aggiunge un plasmide o un profago al genoma di partenza.

Il **preview** si aggiorna in tempo reale: vedi il fenotipo derivato (µ, ε, n_TM, σ-affinity, QS signals) nella sidebar destra.

### 3.2 Cromosoma circolare (centro)

Il cromosoma è renderizzato come **anello SVG** con i geni come archi colorati. Ogni gene ha una **corona di domini** concentrica (mini-archi più stretti verso il centro).

- **Click su un gene** → highlight + popola l'inspector.
- **Plasmidi** sotto come cerchi più piccoli (stesso schema, scala 0.6×).
- **Geni editabili** (custom genes che hai aggiunto) hanno un'outline tratteggiata per distinguerli dai geni base derivati dai profili.

### 3.3 Editor draft del gene custom

Sotto il canvas, l'**editor del draft gene**:

- **Palette dei domini funzionali** (11 tipi). Click su un dominio → si aggiunge in coda al draft.
- **Riordino**: ogni dominio nel draft ha tre pulsanti — `↑` (sposta su), `↓` (sposta giù), `×` (rimuovi). Tutti accessibili da tastiera.
- **Blocchi intergenici**: 3 famiglie (`expression`, `transfer`, `duplication`) con moduli toggable (es. sigma_promoter, oriT_site, repeat_array). Influenzano sigma factor, HGT bias, copy number.
- **Commit** del gene → si aggiunge al cromosoma e appare come arco editabile.
- **Rimuovi gene custom** dalla lista compatta sotto.

> Massimo **9 domini per gene custom**. Massimo gene editor scope: chromosome only (no plasmide custom in fase 1).

### 3.4 Provisioning

Quando il seed è completo (nome + archetipo scelto + form valido) il pulsante **"Colonize selected biotope"** si abilita.

Click → il sistema:
1. Crea un `ArkeonBlueprint` persistente con il tuo fenotipo+genome.
2. Avvia un nuovo `Biotope.Server` registrato per te.
3. Inocula il seed lineage nel biotopo (`N=420` distribuito sulle fasi).
4. Reindirizza alla **viewport del biotopo**.

> **Importante**: il seed si **lock-a** alla prima colonizzazione. Il blueprint resta visualizzabile ma non più editabile. Per progettare un nuovo seed, registra un altro player.

---

## 4. Biotope viewport — osservare l'evoluzione

La viewport del biotopo è la vista più densa: telemetria realtime + ispezione + interventi.

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

### 4.2 Sidebar (sinistra)

**Biotope KPIs**: tick, lineages, N total, stream status (live/shell).

**Phases list**: ogni fase è un pulsante con swatch colorato + nome + (T, pH) + popolazione corrente. Click → seleziona la fase. La fase selezionata determina:
- l'highlight dell'arco corrispondente nella scena SVG
- il **Phase inspector** sotto (KPI fase: N, richness, H′ (Shannon), phage load; environment: T, pH, Osm, D = dilution rate)
- il target di alcune intervention (es. `nutrient_pulse`)

### 4.3 Scena SVG (centro)

La scena rende il biotopo come **bande orizzontali** (una per fase) con **particelle** dentro ciascuna che rappresentano i lineage.

- Particelle deterministicamente posizionate via hash → quando l'abbondanza cambia, i punti si muovono ma non saltano.
- **Forma per cluster fenotipico**:
  - cerchio = generalist
  - quadrato arrotondato = biofilm
  - ellisse = motile
- **Colore** = palette per cluster + hash dell'`id` lineage (stabile).
- **Click su una banda fase** → seleziona la fase nella sidebar.
- Tick overlay in alto a destra.

### 4.4 Bottom tabs (basso, ~220 px)

Quattro tab. Solo il body della tab attiva è renderizzato; lo scroll è interno.

- **Events** — stream degli ultimi ~20 eventi del biotopo (born, extinct, hgt_transfer, intervention).
- **Lineages** — tabella ordinabile (per `N` / `µ` / `ε` / `born`). **Click su una riga → apre il drawer destro** con il dettaglio del lineage.
- **Chemistry** — heatmap `phases × metabolites` con colore proporzionale alla concentrazione; sotto, token cloud con signal load + phage load per fase.
- **Interventions** — vedi §4.6.

### 4.5 Lineage drawer (destra, slide-in)

Si apre cliccando una riga della tab Lineages. Mostra:

- ID completo + colore swatch.
- Cluster fenotipico (biofilm / motile / stress-tolerant / generalist / cryptic).
- N totale, tick di nascita.
- µ (h⁻¹), ε (repair efficiency), surface tags principali.
- Per-phase abundance.

Pulsante "Close" o click di nuovo sulla riga per chiudere.

### 4.6 Interventions

Solo i biotopi che **possiedi** accettano intervention; altri sono read-only.

Apri il pannello dal pulsante **"Interventions"** in header (drawer sinistro) o dalla tab "Interventions" sotto. Le opzioni correnti:

- **Nutrient pulse** → aggiunge metaboliti alla fase selezionata (target del kcat dei profili).
- **Plasmid inoculation** → introduce un plasmide noto nel pool della fase selezionata (può ricombinare).
- **Mixing event** → applica un mescolamento tra le fasi del biotopo (omogeneizza temporaneamente le concentrazioni e le popolazioni).

Ogni intervention consuma un **slot del budget** (rate limiting anti-griefing). Lo stato dello slot è visibile nel pannello: `Slot open` o `Locked X` (contatore al ripristino).

### 4.7 Topology modal

Click sul pulsante ⚙ in header → modal con metadati di rete: id biotope, zona, coordinate display, owner, lista neighbor IDs.

---

## 5. World — overview macroscala

`/world` rende il **grafo SVG** dei biotopi attivi.

- **Nodi** = biotopi; raggio ∝ log(N totale + lineage count). Colore = archetipo.
- **Edge** = connessioni di migrazione inter-biotopo.
- **Click su un nodo** → seleziona; il side-panel destro mostra: archetipo, owner, tick, lineages, N, fasi, link "Open biotope".
- **Filter tabs**: `All` / `Mine` / `Wild` per limitare la vista.

Il side-panel ha 3 sotto-pannelli:
1. **Operator** — il tuo nome + CTA al Seed Lab.
2. **Selected** — dettaglio del biotopo selezionato (vuoto se nessuno).
3. **Distribution** — barra colorata con la breakdown per archetipo.

---

## 6. Audit — eventi globali

`/audit` mostra il **log persistito** degli eventi tipizzati (Block 13 di `DESIGN.md`).

- **Filter tabs**: All / HGT / Mutations / Lysis / Interventions / Community / Colonisation / Mobile.
- **Pagination**: 50 eventi per pagina; pager `1–50 of 412`.
- Ogni riga: timestamp, tipo evento (badge colorato), tick, biotope_id, lineage_id, payload preview.

L'audit è **append-only** e sopravvive alla rimozione dei biotopi. È la fonte di verità per ricostruire qualsiasi storia evolutiva.

---

## 7. Community — multi-seed runs

`/community` lista i **biotopi inoculati con community-mode** (DESIGN Block 19). Sono biotopi avviati con più seed founder simultaneamente — utili per studiare interazioni inter-strain dal tick 0.

Ogni entry ha: archetipo, count founder, fase di inoculo, timestamp, tick corrente, lineage count, link "Open →" alla viewport.

> Il provisioning di una community avviene attualmente solo via API simulazione (`Arkea.Game.CommunityLab.provision_community/3`). Una UI di creazione è in roadmap.

---

## 8. Glossario rapido

| Termine UI | Significato |
|---|---|
| **Arkeon** | L'organismo proto-batterico (genoma + fenotipo derivato). |
| **Lineage** | Discendenza con genoma identico (un mutante è un nuovo lineage). |
| **Biotopo** | Mondo persistente con N fasi, K lineage, condizioni ambientali. |
| **Fase** | Sotto-volume del biotopo con condizioni omogenee (surface, sediment, …). |
| **µ** | Tasso di crescita specifico (h⁻¹). |
| **ε** | Repair efficiency (0..1). |
| **H′** | Shannon diversity index calcolato sulla fase. |
| **N** | Popolazione (counts), per fase o totale. |
| **D** | Dilution rate (%/tick). |
| **Cluster** | Categoria fenotipica derivata: biofilm / motile / stress-tolerant / generalist / cryptic. |
| **Phage load** | Somma delle abbondanze di virioni nel `phage_pool` di una fase. |
| **HGT** | Horizontal Gene Transfer — coniugazione + trasformazione + trasduzione + phage infection. |
| **Slot del budget** | Anti-griefing rate-limit per gli intervention. |
| **Audit log** | Tabella append-only degli eventi tipizzati persistiti. |

Glossario biologico più ampio in [`devel-docs/DESIGN.md`](devel-docs/DESIGN.md).

---

## 9. FAQ

**Posso resettare il biotopo?**
No: la simulazione è autoritativa e persistente. Per ricominciare, registra un nuovo player o aspetta che il tuo lineage si estingua naturalmente.

**Cosa succede se chiudo il browser durante un tick?**
Il server continua. Quando torni, ti riconnetti via PubSub al biotopo e ricevi lo stato corrente.

**Perché non vedo eventi nella tab Events?**
Probabilmente il biotopo è giovane o stabile. Gli eventi sono `:lineage_born`, `:lineage_extinct`, `:hgt_transfer`, `:intervention`. Senza pressione (mutazione neutra, no HGT spontaneo) la coda resta vuota.

**Il mio seed è loccato — come testo nuove configurazioni?**
Crea un nuovo player (email diversa). Il seed lock è per blueprint, non per istanza.

**Posso intervenire su un biotopo che non possiedo?**
No. Solo i biotopi che hai colonizzato accettano intervention. Gli altri sono ispezionabili ma read-only.

**Le mie modifiche al draft gene si perdono?**
Sì, il draft non è persistito. Vive nello stato della LiveView. Se ricarichi la pagina, riparti da zero — committa il gene quando sei pronto.

**Dove trovo le costanti del modello?**
Tutte le costanti chiave + range biologico di letteratura sono in [`devel-docs/CALIBRATION.md`](devel-docs/CALIBRATION.md).

---

## 10. Feedback e contributi

Bug, suggerimenti, walkthrough scientifici da validare → vedi [README.md](README.md) per i canali del progetto. Il modello biologico è in evoluzione: la roadmap è in [`devel-docs/BIOLOGICAL-MODEL-REVIEW.md`](devel-docs/BIOLOGICAL-MODEL-REVIEW.md).
