> 🇮🇹 Italiano (questa pagina) · [🇬🇧 English](USER-MANUAL.en.md)

# Manuale d'uso · Arkea

Benvenuto in **Arkea**, una sandbox evolutiva persistente per organismi proto-batterici. Questo manuale ti guida da zero (registrazione del player) fino a osservare arms race ospite-fago, displacement plasmidico, error catastrophe e cycle closure metabolica nei tuoi biotopi.

Il manuale presuppone solide basi di **microbiologia / biologia molecolare**. Non aspettarti shortcut narrativi: ogni meccanismo riflette una controparte biologica reale, calibrata e documentata in [`devel-docs/CALIBRATION.md`](devel-docs/CALIBRATION.md). Se vuoi i numeri esatti, tienilo aperto a fianco.

> **Cosa Arkea NON è**: un game competitivo. Niente scoreboard, niente loop di vittoria. Il fenomeno osservabile *è* la ricompensa.

---

## Indice

1. [Modello mentale (leggimi prima)](#1-modello-mentale-leggimi-prima)
2. [Primo accesso](#2-primo-accesso)
3. [Tour della Dashboard](#3-tour-della-dashboard)
4. [Seed Lab — progettare l'Arkeon iniziale](#4-seed-lab--progettare-larkeon-iniziale)
5. [Biotope viewport — osservare l'evoluzione](#5-biotope-viewport--osservare-levoluzione)
6. [Pressioni selettive: cosa aspettarti](#6-pressioni-selettive-cosa-aspettarti)
7. [Leggere i segnali evolutivi](#7-leggere-i-segnali-evolutivi)
8. [World — overview macroscala](#8-world--overview-macroscala)
9. [Audit — il log degli eventi](#9-audit--il-log-degli-eventi)
10. [Community — multi-seed runs](#10-community--multi-seed-runs)
11. [Playbook: scenari ricorrenti](#11-playbook-scenari-ricorrenti)
12. [Glossario esteso](#12-glossario-esteso)
13. [FAQ](#13-faq)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Modello mentale (leggimi prima)

### 1.1 Server-authoritative

Arkea gira **24/7 sul server** (BEAM/OTP). Ogni biotopo è un processo Erlang isolato che esegue un *tick puro-funzionale* a cadenza regolare. Il browser **non** simula nulla: riceve solo lo stato corrente del biotopo via PubSub e lo renderizza come SVG nativo.

Conseguenze pratiche:

- **Quando chiudi il browser, il tuo biotopo continua ad evolvere.** Quando torni, il display ti mostra lo stato al tick corrente.
- **Non puoi mettere in pausa.** Il tempo nel server scorre uguale per tutti i player.
- **Se due player guardano lo stesso biotopo wild contemporaneamente, vedono esattamente le stesse cose.**

### 1.2 Scale di tempo

| Costrutto | Valore Arkea | Equivalente biologico |
|---|---|---|
| 1 tick | 5 minuti wall-clock | ~1 generazione cellulare di riferimento |
| Half-life del fago libero | 3–5 tick | ore–giorni in surface waters reali |
| SOS attivazione sotto stress | 4–10 tick | minuti in vivo |
| Emergenza di mutator strain | 50–200 tick | 100–1000 generazioni Lenski-style |
| Cycle closure cross-feeding | 100–500 tick | giorni in chemostat |

Quindi **un'ora di runtime ≈ 12 generazioni**, e una giornata di simulazione ≈ 288 generazioni: comparabile a un esperimento Lenski settimanale. Eventi rari in vivo (transduzione, hypermutazione SOS) sono **amplificati per visibilità nei tempi di gioco**; per benchmark scientifici esistono override (vedi `devel-docs/CALIBRATION.md`).

### 1.3 Ownership e visibilità

- I **biotopi che colonizzi tu** sono `player_controlled`: solo tu puoi applicare interventi.
- I biotopi `wild` (default scenario, eventi automatici) sono ispezionabili da chiunque ma non modificabili.
- I biotopi di altri player sono `foreign_controlled`: visibili nel `World`, non modificabili.
- Il tuo **seed** (genoma + fenotipo iniziale) è privato fino al provisioning, poi diventa parte del registro pubblico via `Audit`.

### 1.4 Anti-griefing minimo

Le `intervention` (nutrient pulse, plasmid inoculation, mixing event) consumano un **slot del budget** soggetto a **rate limit di 60 secondi** (in prototipo; in produzione era 30 minuti). Questo evita che un player possa "rovinare" un biotopo wild con interventi a raffica. Lo stato dello slot è sempre visibile nel pannello interventi: `Slot open` o `Locked X` (con countdown al ripristino).

### 1.5 Cosa è progettato dal player vs cosa emerge

| Decidi tu (Seed Lab) | Emerge dalla simulazione |
|---|---|
| Archetipo del biotopo | Speciazione (nuovi lineage da mutazione) |
| Cassette metabolica del seed | HGT events (coniugazione, trasformazione, trasduzione) |
| Profilo di membrana | Dinamiche fagiche (lytic burst, lysogeny, decay) |
| Modalità di regolazione | SOS response, error catastrophe |
| Modulo mobile (plasmide o profago) | Bacteriocine warfare |
| Geni custom (≤ 9 domini ciascuno) | Cross-feeding, niche partitioning |
| Blocchi intergenici | Biofilm formation, mixing events |

Tu progetti **il punto di partenza**. Il sistema fa evolvere tutto il resto.

---

## 2. Primo accesso

### 2.1 Creare un account

1. Apri la home `/` e scegli **"Crea player"**.
2. Inserisci `display_name` (visibile in `Audit` e `Community`) ed `email` (chiave di resume).
3. Al click su "Create player" vieni reindirizzato al **Seed Lab**.

> **Niente password.** Il resume è basato sull'email — chi conosce la tua email può riprendere la tua sessione. Per il prototipo questo è accettabile; in produzione cambierà.

### 2.2 Riprendere

Da `/` scegli **"Riprendi player"** e inserisci l'email registrata. Vieni reindirizzato alla **Dashboard** (non al Seed Lab — il seed è già locked se hai già provisionato).

### 2.3 Cosa aspettarti nel primo minuto

Subito dopo la registrazione:

1. La **Dashboard** mostra 6 pannelli; "Seed Lab" è quello che ti serve.
2. Nessun biotope è ancora avviato — il pannello "World" è vuoto, "My Biotopes" mostra "No owned biotopes".
3. La community e l'audit sono vuoti per te (eventi globali da altri player potrebbero essere già visibili).
4. Click su "Seed Lab" → progetti il seed.
5. Dopo il provisioning, il Biotope viewport ti porta dentro il tuo primo biotopo. Già al **tick 0** vedi la popolazione fondatrice (`N=420` distribuiti sulle fasi del biotopo).

Nei **primi 10–30 tick** non vedi quasi nulla di dinamico: la popolazione fondatrice è genomicamente uniforme, le mutazioni sono rare. È normale. Da tick ~50 in poi cominciano ad apparire i primi `:lineage_born` events.

---

## 3. Tour della Dashboard

La Dashboard è la landing post-login. È strutturata in **6 pannelli card-link**:

| Pannello | Apre | Quando ti serve |
|---|---|---|
| **World** | `/world` | Vista d'insieme: chi è dove, quanti biotopi attivi, distribuzione archetipi. |
| **Seed Lab** | `/seed-lab` | Solo prima del primo provisioning, oppure per ispezionare il seed locked. |
| **My Biotopes** | `/biotopes/:id` | Lista compatta dei biotopi che possiedi — quick jump alla viewport. |
| **Community** | `/community` | Read-only: biotopi avviati con community-mode (multi-seed). |
| **Audit** | `/audit` | Stream globale di eventi tipizzati persistiti — query forensiche. |
| **Docs** | (placeholder) | Riferimenti DESIGN/CALIBRATION (rendering Markdown in arrivo). |

### 3.1 Flusso tipico

- **Sessione di onboarding (prima volta)**: Dashboard → Seed Lab → provision → Biotope viewport. Una volta locked il seed, la Dashboard "Seed Lab" diventa solo ispezionabile.
- **Sessione di osservazione**: Dashboard → My Biotopes → Biotope viewport (o World → click su nodo → Open biotope).
- **Sessione di analisi forense**: Dashboard → Audit → filter su `mutation_notable` / `hgt_event` / `community_provisioned` per capire cosa è successo nelle ultime ore.

Nessuna view della Dashboard ha scrollbar globale: quando i contenuti eccedono, scrollano i sotto-pannelli.

---

## 4. Seed Lab — progettare l'Arkeon iniziale

Il Seed Lab è il punto di leva massima. Le scelte qui determinano:

- la **cellularità di base** del tuo lineage fondatore (membrana, regolazione, repair);
- la **cassetta metabolica iniziale** (kcat, Km, target metaboliti);
- gli **elementi mobili** che il seed porta con sé (plasmidi, profagi, gene custom);
- il **biotopo destinazione** (archetipo + zona).

Una volta colonizzato il primo biotopo, il seed si **lock-a** e non è più editabile. Per progettare un seed alternativo, devi registrare un nuovo player.

### 4.1 Form principale (colonna sinistra)

#### Nome del seed

Identificativo umano del blueprint nel sistema di provisioning. Visibile in Audit per `colonization` events. Massimo 40 caratteri.

#### Archetipo del biotopo da colonizzare

Tre opzioni starter, ognuna con fasi/metaboliti/zone diversi:

- **Eutrophic Pond** — alta densità di nutrienti, turnover rapido. Fasi: surface (high O₂), water column, sediment (anossico). Buon ambiente per generalist con metabolismo flessibile.
- **Oligotrophic Lake** — acqua pulita, basso C inflow. Fasi simili al pond ma con concentrazioni metaboliche più basse. Premia profili `thrifty` con bassa Km.
- **Mesophilic Soil** — ambiente patchy (aerobic pore, wet clump, soil water). Fasi più eterogenee → niche partitioning marcato. Premia membrane fortified e regolazione responsive.

Ogni archetipo carica un **starting pool** di metaboliti (vedi `devel-docs/DESIGN.md` Block 6 per la lista completa).

#### Cassette metabolica (`metabolism_profile`)

Imposta i parametri base dei domini catalitici del tuo seed:

- **`balanced`** — kcat medi, Km medi su target diversificati. Buon default per esplorare.
- **`thrifty`** — kcat bassi, Km bassi (alta affinità). Sopravvive in oligotrophic; cresce lento ovunque.
- **`bloom`** — kcat alti, Km alti (bassa affinità). Esplode in eutrophic; si schianta in oligotrophic.

#### Profilo di membrana (`membrane_profile`)

- **`porous`** — alta diffusione, bassa stabilità osmotica. Veloce uptake; fragile a osmolarity shock.
- **`fortified`** — più transmembrane anchor, robusta a stress osmotico e xenobiotici. Lento uptake.
- **`salinity_tuned`** — middle ground specifico per saline estuary / sediment.

#### Modalità di regolazione (`regulation_profile`)

Modula `repair_efficiency`, `dna_binding_affinity`, e la sensibilità del trigger SOS:

- **`steady`** — repair alto, dna_binding_affinity media, SOS conservativo. Bassa µ ma stabile.
- **`responsive`** — repair medio, regolazione adattiva, SOS-ready.
- **`mutator`** — repair basso → mutation rate alto → mutator strain. Speciazione veloce ma rischio di error catastrophe.

> Suggerimento: `mutator` è esplosivo. In oligotrophic lake con mutator vedrai 10+ lineage in 200 tick ma molti collasseranno per error catastrophe. È il modo più rapido per studiare il limite di Eigen.

#### Modulo mobile (`mobile_module`)

Aggiunge un elemento mobile al genoma di partenza:

- **`none`** — solo cromosoma.
- **`conjugative_plasmid`** — un plasmide con `oriT` site, copy number ~3, ~2 geni cassettati. Permette HGT verticale già al tick 1.
- **`latent_prophage`** — un profago integrato lisogenico, con repressor strength media. Sotto stress (SOS), entrerà in lytic cycle e libererà virioni.

Il modulo mobile è la chiave per innescare HGT veloce in scenari di pochi 100 tick.

#### Schema Arkeon (sidebar destra)

Mentre compili il form, sulla sidebar destra trovi uno **schema diagrammatico della cellula** aggiornato in tempo reale. Non è una rappresentazione fotorealistica — è una sintesi astratta in stile microbiologico, dove ogni feature visibile mappa una scelta di fenotipo. Ogni elemento porta un `<title>` SVG (tooltip al passaggio del mouse) che ne spiega il significato:

**Membrana / parete (`membrane_profile`).** Le tre opzioni sono visivamente molto distinte:

- **`porous`** — contorno azzurro sottile a singola bilayer + **8 cerchietti porini** distribuiti lungo la membrana (canali aperti per piccole molecole). Veloce uptake, fragile a stress osmotico.
- **`fortified`** — **vero envelope doppio**: membrana esterna spessa (color rust) + spazio periplasmico denso reso da brevi trattini radiali tra le due membrane (suggerimento di peptidoglicano/strato S) + membrana plasmatica interna più sottile. Più costoso ma robusto.
- **`salinity_tuned`** — contorno scalloppato profondo (anelli di adattamento osmotico) + **strato interno tratteggiato** che evoca il sistema di sequestrazione ionica caratteristico delle cellule alotolleranti.

**Caratteristiche interne**:

- **Trattini radiali brevi sull'envelope** = singole proteine transmembrana (`phenotype.n_transmembrane`, capped a 12 per leggibilità).
- **Citoplasma colorato** con tinta sky-blue, opacità proporzionale a `metabolism_profile` (bloom denso · thrifty rarefatto).
- **Granuli di stoccaggio (cerchi gialli/dorati con highlight bianco)** = inclusioni intracellulari analoghe a poli-β-idrossibutirrato (PHB), polifosfato e glicogeno. Il numero scala con `metabolism_profile`: bloom = 8, balanced = 5, thrifty = 2. Posizionati nella corona esterna del citoplasma per non sovrapporsi al nucleoide.
- **Nucleoide** = tre anse intersecanti (suggerendo il DNA cromosomale supercoiled e foldato) al centro della cellula. Più anse e wobble per metabolismi attivi.
- **Cerchi viola vicino al nucleoide** = plasmidi (anelli di DNA extra-cromosomale), uno per ogni plasmide nel genome. Se hai scelto `conjugative_plasmid` ma il genome non è ancora provisioned, vedi un plasmide tratteggiato come hint.
- **Cassetta profago** = arco rosso/magenta con etichetta **"Φ"** integrato nel cerchio del nucleoide. Si vede solo se `mobile_module = latent_prophage` o se il genome contiene già un profago. La forma rappresenta esplicitamente l'integrazione del genoma virale dentro il cromosoma — non è una decorazione esterna.

**Appendici di superficie** (derivano dai `surface_tags` del fenotipo):

- **Pili** = linee teal radiate fuori dall'envelope.
- **Adesine** = cerchietti verdi contro la membrana esterna.
- **Recettore fagico** = piccolo "T" arancione (stem + barra) che sporge dalla membrana.

**Altri elementi**:

- **Flagello** (lunga curva teal sul lato destro) = se il cluster fenotipico calcola "motile" (n_transmembrane ≥ 2 e nessun surface tag biofilm).
- **Alone (halo) caldo intorno alla cellula** = il `regulation_profile` è `mutator` (cellula sotto stress di hypermutazione cronica). L'effetto è composto da cinque anelli concentrici sovrapposti — bande esterne morbide che sfumano, un anello tratteggiato intermedio che ruota lentamente (shimmer), e un accento sottile sul bordo della cellula. Tutto pulsa con un respiro ~3.6 s. La rotazione e il pulse rispettano `prefers-reduced-motion`.

Sotto lo schema, una **legenda di 4 righe** (Envelope / Metabolism / Regulation / Accessory) descrive in linguaggio naturale la scelta corrente.

> **Suggerimento**: passa il mouse su qualsiasi elemento dello schema per vedere il tooltip che ne spiega il significato biologico. Tutti i feature hanno `<title>` SVG.

### 4.2 Cromosoma circolare (centro del Seed Lab)

Il cromosoma è renderizzato come **anello SVG chiuso** composto da segmenti contigui: **ogni gene è un segmento del cromosoma**, separato dai vicini da un sottile gap (~0.7°). Non c'è una "corona" radiale — il dettaglio dei domini vive *dentro* lo stesso segmento del gene.

Come leggerlo:

- **Segmento del cromosoma** = gene. La sua lunghezza angolare è uniforme tra i geni (il sistema non rappresenta lunghezze in codoni in scala visiva, solo l'ordine).
- **Sotto-porzioni colorate dentro un gene** = domini funzionali, accostati nell'ordine in cui compaiono nel gene. Ogni dominio occupa la **piena spessore radiale** dell'anello (non è concentrico). Il colore deriva dal tipo del dominio (vedi §4.3).
- **Plasmidi** sotto come cerchi più piccoli (scala 0.6×) con la stessa logica: ognuno è un anello chiuso di gene-segmenti.
- **Outline tratteggiato attorno al segmento** = gene editabile (custom, aggiunto da te). I geni base (derivati dai profili di cassette/membrana/regolazione) hanno outline trasparente.
- **Etichetta esterna** = label corto del gene, posizionato fuori dall'anello.

Click su un gene → il gene si highlighta (outline solido visibile) e popola l'**Inspector** sotto, dove vedi: lista dei domini con i loro parametri derivati, intergenic blocks, codon count.

### 4.3 I 11 domini funzionali

Block 7 di `DESIGN.md`. Ogni gene è una sequenza di codoni; il parser estrae uno o più *domini* sulla base di un `type_tag` di 3 codoni che indicizza in `0..10`. Ogni dominio ha 20 `parameter_codons` che, sommati con pesi log-normal, producono i parametri derivati.

| Tipo | Tag | Cosa fa | Parametri tipici |
|---|---|---|---|
| `:substrate_binding` | SB | Definisce affinità di binding e classe metabolita target | `target_metabolite_id` (0..12), `affinity_km` |
| `:catalytic_site` | CAT | Aggiunge turnover catalitico e classe di reazione | `kcat`, `reaction_class` (e.g. hydrolysis, oxidation) |
| `:transmembrane_anchor` | TM | Inserzione in membrana, modula `n_passes` | `n_passes` (1..10), `stability` |
| `:channel_pore` | CH | Selettività di trasporto + gating threshold | `selectivity_class`, `gating_threshold` |
| `:energy_coupling` | EC | Costo ATP / accoppiamento PMF | `atp_cost`, `pmf_couple` |
| `:dna_binding` | DNA | Affinità per promotori, accoppiamento a sigma | `binding_affinity`, `sigma_class` |
| `:regulator_output` | REG | Output di regolazione (activator/repressor) | `output_logic`, `target_operon` |
| `:ligand_sensor` | LIG | Soglia di sensing per metabolita o segnale | `signal_class`, `threshold_concentration` |
| `:structural_fold` | SF | Stabilità + supporto a multimerizzazione | `multimerization_n`, `stability` |
| `:surface_tag` | ST | Surface signature (pilus, recettore fagico, biofilm) | `surface_class` (adhesin, matrix, biofilm, phage_receptor, …) |
| `:repair_fidelity` | RPR | Repair DNA, modula `error_rate` per replicazione | `repair_class`, `efficiency` |

**Regola di composizione**: un gene custom può portare **da 1 a 9 domini**. Composizioni significative tipiche:

- `[catalytic, substrate_binding]` — un enzima monofunzionale.
- `[transmembrane, transmembrane, channel_pore, energy_coupling]` — un trasportatore attivo (es. ABC transporter).
- `[ligand_sensor, dna_binding, regulator_output]` — un fattore di trascrizione two-component.
- `[transmembrane, surface_tag]` — un'adesina di superficie.
- `[catalytic, substrate_binding, structural_fold]` — un enzima multimero.

Il sistema **non** valida la sensatezza biologica della composizione: puoi creare un gene "alieno" con domini che non hanno senso insieme. La selezione naturale farà il resto (i lineage non funzionali si estinguono velocemente).

### 4.4 Blocchi intergenici

Tre famiglie di blocchi attaccabili al draft gene; ognuna ha moduli toggable. Servono a fornire al gene contesto di regolazione e mobilità:

- **`expression`**:
  - `sigma_promoter` — il gene è espresso costitutivamente (sigma-70-like).
  - `cyclic_amp_response` — espressione modulata da catabolite.
  - `quorum_response` — espressione QS-dipendente.
- **`transfer`**:
  - `oriT_site` — il gene è trasferibile per coniugazione (rende il gene "mobile").
  - `pilus_attachment_site` — facilita HGT inter-cellulare.
- **`duplication`**:
  - `repeat_array` — sequenza ripetuta che aumenta la prob. di duplicazione genica (gene amplification).

Ogni blocco è opt-in nel draft; commit del gene → i blocchi diventano parte del `regulatory_block` del gene.

### 4.5 Editor del draft gene

Sotto il canvas, l'**editor del draft gene**:

1. **Palette dei domini funzionali** (11 tipi, click per aggiungere). I domini latenti (alcuni `:channel_pore`, `:regulator_output`) sono marcati `stored / future` — biologicamente codificati ma non aggregati nel runtime correntemente attivo.
2. **Lista del draft** con ogni dominio in ordine. Pulsanti per ognuno:
   - `↑` sposta su (a11y, anche da tastiera).
   - `↓` sposta giù.
   - `×` rimuove.
3. **Toggle dei blocchi intergenici** (3 famiglie × 3 moduli ciascuna).
4. **Errori del draft**: se la composizione non è valida (>9 domini, palette id sconosciuto), un messaggio d'errore appare sopra la palette.
5. **Commit** — il gene si aggiunge al cromosoma e appare come arco editabile nel canvas.
6. **Clear draft** — reset.

> Suggerimento: il draft non è persistito tra reload. Se ricarichi la pagina, riparti da zero. Committa quando sei soddisfatto.

### 4.6 Lock e provisioning

Quando il seed è completo (nome ≥ 1 char + archetipo selezionato + form valido), il pulsante **"Colonize selected biotope"** si abilita.

Click → il sistema:

1. Crea un `ArkeonBlueprint` persistente con il tuo fenotipo + genome.
2. Avvia un nuovo `Biotope.Server` registrato per te (ti diventi `owner`).
3. Inocula il seed lineage nel biotopo. Distribuzione iniziale: `N=420` cellule **divise tra le fasi** del biotopo secondo i pesi del seed (es. surface 60%, water_column 30%, sediment 10%).
4. Reindirizza alla **viewport del biotopo**.

**Importante**: il seed si **lock-a** alla prima colonizzazione. Il blueprint resta visualizzabile (Seed Lab in modalità read-only) ma non più editabile. Per progettare un nuovo seed → registra un altro player.

---

## 5. Biotope viewport — osservare l'evoluzione

La viewport del biotopo è la vista più densa. Fornisce telemetria realtime + ispezione dei lineage + applicazione di interventi.

### 5.1 Layout generale

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

Quando clicchi una riga lineage, si apre un **drawer** sul lato destro (375 px) con il dettaglio del lineage selezionato.

### 5.2 Header

- **Archetype chip** (es. "Eutrophic Pond") con dot colorato per archetipo.
- **Interventions** — apre il drawer sinistro col pannello interventi.
- **⚙ Topology** — modal con metadati di rete (id biotope, zone, coordinate, owner, neighbor_ids).
- **User menu** — il tuo nome e logout.

### 5.3 Sidebar (sinistra)

#### Biotope KPIs

Quattro tile:

- **Tick** — il tick corrente. Incrementa di 1 ogni 5 minuti server-side.
- **Lineages** — numero di lineage attualmente vivi (con `total_abundance > 0`).
- **N total** — popolazione complessiva del biotope, somma su tutte le fasi.
- **Stream** — `live` se sei subscribed al PubSub del biotope (dovrebbe essere sempre `live` in browser connesso); `shell` se la subscription è caduta (refresh la pagina).

#### Phases list

Ogni fase del biotope è un pulsante con:

- swatch colorato a sinistra (per archetipo della fase: surface=ambra, deep/sediment=ruggine, water_column=cyan, biofilm=verde, ecc.);
- nome della fase + (T, pH);
- popolazione corrente nella fase a destra (in formato compatto: `1.2k`).

Click → seleziona la fase. La fase selezionata determina:

- l'**highlight** dell'arco corrispondente nella scena SVG (stroke più spesso, ring di evidenziazione);
- il **Phase inspector** sotto (KPI fase + environment);
- il target di alcune interventi (es. `nutrient_pulse` agisce sulla fase selezionata).

#### Phase inspector

KPI della fase selezionata:

- **N** — popolazione nella fase.
- **richness** — numero di lineage diversi presenti nella fase.
- **H′ (Shannon)** — diversità di Shannon calcolata sui counts dei lineage. `H′ = 0` quando solo 1 lineage; cresce con N e con uniformità.
- **phages** — somma di virion abundance nel `phage_pool` della fase.

Environment readings:

- **T** — temperatura (°C).
- **pH** — pH della fase.
- **Osm** — osmolarity (mOsm/L equivalente).
- **D** — dilution rate (%/tick). D=2% significa che il 2% della popolazione fluisce fuori dalla fase ogni tick.

### 5.4 Scena SVG (centro)

La scena rende il biotope come **bande orizzontali** (una per fase) con **particelle** dentro ciascuna che rappresentano i lineage. Rilevante:

- **Altezza della banda ∝ popolazione totale della fase** (con un floor minimo). Una banda piccola = fase quasi vuota.
- **Numero di particelle ∝ √(popolazione) della fase**, capped a 60. Ogni particella rappresenta una frazione del lineage.
- **Posizione delle particelle** è deterministica via hash di `{phase, lineage_id, i}`. Quando l'abbondanza cambia, le particelle si spostano leggermente (CSS transition) ma non saltano. Particelle dello stesso lineage condividono colore.
- **Forma per cluster fenotipico**:
  - **cerchio** = `generalist` o `stress-tolerant` o `cryptic`.
  - **quadrato arrotondato** = `biofilm` (lineage con `:adhesin` / `:matrix` / `:biofilm` surface tags).
  - **ellisse** = `motile` (lineage con `n_transmembrane >= 2`).
- **Colore** = palette per cluster + hash dell'`id` lineage. Stabile attraverso i tick (non cambia se l'abbondanza cambia).
- **Click su una banda fase** → seleziona la fase (equivalente al click sulla phase list).
- **Tick overlay** in alto a destra.

> Nota: la scena è un **proxy denso**, non una rappresentazione 1:1. Con 100 lineage in una fase, vedrai max 60 particelle; il resto è "implicito". Il dettaglio numerico esatto è nella tab Lineages.

### 5.5 Bottom tabs (~220 px)

Quattro tab. Solo il body della tab attiva è renderizzato; lo scroll è interno.

#### Events

Stream degli ultimi ~20 eventi del biotope, in ordine cronologico decrescente. Tipi:

- **`:lineage_born`** — nuovo lineage nato (mutazione che produce un genome nuovo). Icona: ➕ verde.
- **`:lineage_extinct`** — lineage estinto (`total_abundance = 0`). Icona: ➖ rossa.
- **`:hgt_transfer`** — evento HGT (coniugazione, trasformazione, trasduzione, infezione lisogenica). Icona: ⇄ ambra.
- **`:intervention`** — intervento del player applicato. Icona: 🧪 teal.

Ogni entry mostra: icona, label, tick di occorrenza, short_id del lineage coinvolto.

#### Lineages

Tabella ordinabile della **population board**. Colonne:

- **ID** — short_id (8 char) + swatch colore.
- **Cluster** — biofilm / motile / stress-tolerant / generalist / cryptic.
- **Phase** — la fase dominante (quella con più cellule).
- **N** — total abundance, con barra orizzontale proporzionale a max(N).
- **µ (h⁻¹)** — base growth rate, derivato dai domini catalitici/repair.
- **ε** — repair efficiency (0..1).
- **Born** — il tick di nascita.

**Click sull'header colonna** → ordina per quella colonna. Default: ordina per N decrescente.

**Click sulla riga** → apre il **drawer destro** con il dettaglio del lineage.

#### Chemistry

Heatmap **fasi × metaboliti** (13 metaboliti canonici: glucose, acetate, lactate, oxygen, NO₃, SO₄, H₂S, NH₃, H₂, PO₄, CO₂, CH₄, iron). Ogni cella ha intensità di colore proporzionale alla concentrazione, normalizzata sulla concentrazione massima di quel metabolita attraverso le fasi.

Sotto la heatmap: token cloud con `signal load` + `phage load` per fase.

**Cosa cercare**:

- **Cycle closure**: in un biotope sano dopo 200+ tick, vedrai ad esempio glucose alto in surface + lactate alto in water_column + acetate/CO₂ alto in sediment → **cross-feeding** funzionante.
- **Anossic gradient**: O₂ alto in surface, basso in deep/sediment.
- **Phage load** elevato in una fase → arms race in corso.

#### Interventions

Pannello operatore. Solo se sei `owner` del biotope.

- **Status**: `Slot open` (puoi intervenire) o `Locked X` (countdown). Lo slot si apre dopo l'intervallo di rate limit.
- **Pulsanti** (ognuno consuma 1 slot):
  - **Pulse nutrients** → aggiunge metaboliti alla fase selezionata. Aumenta la concentrazione dei target metaboliti dei profili attualmente attivi. Utile per "sbloccare" un biotope stagnante.
  - **Inoculate plasmid** → introduce un plasmide noto nel pool della fase selezionata. Può ricombinare con i genomi presenti via trasformazione (se i recipient sono competenti).
  - **Trigger mixing event** → applica un mescolamento tra le fasi del biotope. Omogeneizza temporaneamente concentrazioni e popolazioni. Equivale a uno storm in nature.
- **Recent interventions** — mini-tabella con kind, scope, tick.

**Confirm prompt** appare prima di applicare ogni intervento. Click su Cancel se l'hai aperto per sbaglio.

### 5.6 Lineage drawer (slide-in destra)

Si apre cliccando una riga della tab Lineages. Mostra:

- **Header**: short_id + cluster fenotipico.
- **Swatch + ID completo** — copia/incolla l'UUID se vuoi cercarlo nell'audit.
- **KPI**: N totale, tick di nascita, µ (h⁻¹), ε (repair efficiency), surface tags principali (max 4).
- **Per-phase abundance** — il lineage in quale fase è più abbondante? Se è splittato 50-50, è probabile che sia in uno scenario di niche partitioning.

Pulsante **Close** in fondo, oppure click di nuovo sulla riga lineage o premi Esc.

### 5.7 Topology modal

Click su ⚙ in header → modal con metadati di rete:

- `biotope` — short_id.
- `zone` — zona ecologica (es. lacustrine, swamp_edge).
- `coords` — display X,Y (per il world graph).
- `owner` — short_id del player owner (o "wild" se nessuno).
- `Neighbor ids` — lista di biotopi connessi via migration edge. Ogni id ti permette di andare manualmente alla viewport `/biotopes/<id>`.

I neighbor sono usati dalla migration: cellule possono passare da un biotope all'altro lungo questi edge (probabilità configurata via `dilution_rate` × `migration_factor`).

### 5.8 Ricolonizzare un home estinto

Quando la popolazione totale del tuo biotopo home crolla a zero, sopra la scena compare un **banner "Colony extinct"** con un pulsante **"Recolonize home"**.

- Il banner è visibile **solo all'owner** del biotopo, e **solo** quando `BiotopeState.total_abundance(state) == 0`.
- Click → confirm dialog → il sistema costruisce un **fondatore fresco dallo stesso blueprint locked** (genoma identico a quello che avevi progettato originariamente nel Seed Lab) e lo inocula nel biotopo. Distribuzione iniziale: **N=420** spalmati sulle fasi correnti del biotopo.
- Il biotope mantiene il suo `id` e il suo `tick_count`: la sequenza temporale è continua. Quello che cambia è solo il pool di cellule.
- L'operazione è loggata in Audit come `intervention` con kind `home_recolonized` e l'`actor_player_id` del provisioning. Forensic-traceable.

Limiti correnti:

- Funziona solo sul biotopo home del player. Wild biotopes e biotopi di altri player non si possono ricolonizzare.
- La ricolonizzazione **non resetta** la chimica, i pool fagici, i plasmidi liberi nel `dna_pool` o l'ambiente: il fondatore eredita lo stato ambientale corrente del biotopo. Se il biotopo era stato sterilizzato da un fago dilagante, la ricolonizzazione lo riapre allo stesso stress.
- Non c'è rate limit dedicato (a differenza degli intervention): se la colonia ricolonizzata si estingue di nuovo dopo un tick, puoi premere ancora subito.

> **Suggerimento**: dopo una ricolonizzazione, è spesso utile applicare anche un **mixing event** (Interventions tab) per omogeneizzare il chimismo che ha portato alla precedente estinzione, oppure un **nutrient pulse** sulla fase con popolazione iniziale dominante.

---

## 6. Pressioni selettive: cosa aspettarti

Le pressioni selettive sono i meccanismi che fanno sopravvivere alcuni lineage e morire altri. Riconoscerle ti aiuta a interpretare quello che vedi.

### 6.1 Tossicità metaboliche

| Metabolita | Soglia tossica | Meccanismo | Detoxify gene |
|---|---|---|---|
| `oxygen` | ≥50 µM equivalente | ROS damage su anaerobi obbligati | `:catalytic_site` con `reaction_class=reduction` su target O₂ (catalase-like) |
| `h2s` | ≥20 µM | Inibizione citocromo c | gene con detoxify path specifico (Fase 21) |
| `lactate` | ≥30 (proxy pH bassa) | Acidità — sostituito da pH dinamico in Fase 21 | — |

**Cosa vedi**: un lineage senza catalase-like in una fase ad alta O₂ ha **kcat effettivo che decresce** monotonicamente. Se l'O₂ continua a salire, il lineage rallenta la crescita fino a estinzione.

### 6.2 Carenze elementari

P, N, Fe, S sono richiesti per la produzione di biomassa. Sotto un floor (`@elemental_floor_per_cell = 0.001` per cellula), il lineage **non cresce** (no fission). Mutazioni che riducono Km di trasporto del nutriente carente vengono selezionate positivamente.

**Cosa vedi**: in un biotope P-limited, un lineage con `:substrate_binding(target=PO₄)` con alto affinity_km cresce più degli altri. In Audit comparirà `mutation_notable` quando un mutante ha trovato la combinazione vincente.

### 6.3 Error catastrophe

Soglia di Eigen: per un genome di N geni con error rate per gene µ, se `µ × N > 1`, le mutazioni accumulate per replicazione sono troppe per essere riparate, e la fitness collassa.

**Cosa vedi**: lineage `mutator` (basso `repair_efficiency`) speciano velocemente nei primi 100-200 tick, poi cominciano a estinguersi. In Events vedrai un picco di `:lineage_born` seguito da un'ondata di `:lineage_extinct`. In Audit, cerca `error_catastrophe_death` events.

### 6.4 Predazione fagica

I profagi inducono sotto stress (SOS attivo). Un induction → lytic burst → 10–500 virioni nel `phage_pool`. I virioni decadono con half-life 3–5 tick. Se il pool è alto e ci sono recipient con `:phage_receptor` matching, l'infection rate decolla.

**Cosa vedi**:

- Phage load alto in una fase (visibile nella token cloud sotto Chemistry).
- Eventi `:hgt_transfer` ripetuti (l'hook `infection_step` emette questo tipo).
- Lineage con loss-of-receptor che improvvisamente esplodono (selezione positiva sulla mutazione che rimuove il `:phage_receptor`). Arms race classica.

### 6.5 Bacteriocine warfare

Un lineage con `[Substrate-binding(target=surface_tag_class)][Catalytic(membrane_disruption)]` produce bacteriocina. Lineage co-residenti con quel surface tag subiscono `wall_progress` damage → lisi alla divisione.

**Cosa vedi**: due lineage con surface tag in conflitto nella stessa fase. Uno produce bacteriocin, l'altro decresce monotonicamente fino a estinzione. Tempo: 80–160 tick (warfare cronica, deliberatamente lenta in Arkea).

### 6.6 Plasmid displacement (incompatibilità)

Due plasmidi con stesso `inc_group` non coesistono nello stesso lineage. Uno dei due viene `displaced` (perduto alla divisione).

**Cosa vedi**: dopo un'inoculazione di plasmide via intervention, in 50–100 tick uno dei plasmidi pre-esistenti dello stesso inc_group sparisce dal genome del lineage. Audit: `plasmid_displaced` events.

---

## 7. Leggere i segnali evolutivi

### 7.1 Dove cercare i segnali

| Segnale | Dove guardare |
|---|---|
| Speciazione | Tab Lineages (count cresce); Events `:lineage_born`. |
| Estinzione di clade | Tab Lineages (un cluster scompare); Events `:lineage_extinct` ripetuti. |
| HGT in corso | Audit con filter `hgt_event`; Events tab del biotope. |
| Mutator emergence | Tab Lineages cresce velocemente (5+ in 50 tick); ε nel drawer del lineage è basso. |
| Cycle closure | Chemistry heatmap mostra pattern complementari tra fasi. |
| Niche partitioning | Drawer lineage: per-phase abundance fortemente sbilanciata; H′ alto nel phase inspector. |

### 7.2 Pattern temporali tipici

#### Tick 0–50: silenzio relativo

La popolazione fondatrice è uniforme. Niente speciazione visibile. Vedi crescita / contrazione globale ma genome unico. Chemistry mostra come il seed sta consumando i metaboliti starting.

#### Tick 50–200: prima diversificazione

Mutazioni accumulate iniziano a produrre `:lineage_born` events. La phase inspector richness sale da 1 a 3-5. Il lineage fondatore (cluster `generalist`) tipicamente domina ancora ma comincia a cedere terreno.

#### Tick 200–500: niche partitioning

I lineage si specializzano per fase. H′ in ogni fase si stabilizza. Compaiono cluster `motile` e `biofilm`. Cross-feeding visibile in Chemistry.

#### Tick 500–1000: arms race

Se hai inoculato un profago o se uno è emerso da una mutazione, partono i cicli fagici. `:hgt_transfer` è frequente. Cluster `stress-tolerant` cresce.

#### Tick 1000+: stato pseudo-stazionario

I cicli metabolici sono chiusi. Le popolazioni oscillano in equilibri dinamici. Eventi rari (HGT inter-biotope via migration, mass lysis da bacteriocin warfare) sono ancora possibili.

### 7.3 Quando intervenire

Le intervention sono il tuo modo di **perturbare** un sistema in pseudo-stato. Buoni momenti:

- **Pulse nutrients** in una fase oligotrophic → osservi quale lineage risponde più velocemente (chi ha la migliore Km).
- **Inoculate plasmid** in una popolazione genomicamente uniforme → osservi se HGT verticale + selezione fissano il plasmide.
- **Mixing event** in un biotope con biofilm formation → osservi se l'aggregazione resiste al mixing o si dissolve.

**Quando NON intervenire**: durante un arms race attivo. Le tue perturbazioni mascherano i pattern endogeni che stai cercando di leggere.

---

## 8. World — overview macroscala

`/world` rende il **grafo SVG** dei biotopi attivi.

### 8.1 Come leggere il grafo

- **Nodi** = biotopi.
  - **Raggio** ∝ log(N totale) + log(lineage count). Un nodo grande è un biotope ricco.
  - **Colore** = archetipo (eutrophic_pond=ambra, oligotrophic_lake=cyan, mesophilic_soil=lime, …).
  - **Outline / dot** = ownership (player_controlled=teal, wild=blu, foreign_controlled=ruggine).
- **Edge** = connessioni di migration. Cellule possono passare da un nodo all'altro lungo questi edge (probabilità modulata da `dilution_rate × migration_factor`).
- **Click su un nodo** → seleziona; il side-panel destro si popola.

### 8.2 Filter tabs

`All` / `Mine` / `Wild` per limitare la vista. Utile in setup multi-player per non perdere i tuoi biotopi nel rumore.

### 8.3 Side-panel

- **Operator** — il tuo nome + CTA al Seed Lab (o ispezione del seed locked).
- **Selected** — dettaglio del biotope selezionato: archetype, ownership, tick, lineages, N, phases, link "Open biotope →".
- **Distribution** — barra colorata che mostra la breakdown per archetipo + lista per-archetipo con count.

---

## 9. Audit — il log degli eventi

`/audit` espone il **log persistito** degli eventi tipizzati (Block 13 di `DESIGN.md`). Append-only, sopravvive alla rimozione dei biotopi (tombstone IDs).

### 9.1 Tipi di evento

| Tipo | Cosa significa |
|---|---|
| `mutation_notable` | Mutazione con effetto fenotipico significativo (oltre soglia di rilevanza). |
| `hgt_event` | Trasferimento orizzontale di gene. |
| `mass_lysis` | Lisi massiva (≥10% della popolazione di una fase muore in 1 tick). |
| `intervention` | Intervento del player applicato. |
| `colonization` | Provisioning di un nuovo biotope da seed. |
| `mobile_element_release` | Plasmide o profago rilasciato nel pool della fase. |
| `community_provisioned` | Multi-seed inoculation (Phase 19). |

### 9.2 Filter tabs

Ogni filter restringe la query a un solo `event_type`. `All` è il default.

### 9.3 Pagination

50 eventi per pagina. Pager mostra `from–to of total`. Click `←` / `→` per navigare. Refresh `↻` ricarica la prima pagina (utile se il biotope sta producendo eventi mentre guardi).

### 9.4 Query forensiche tipiche

- "Cosa è successo in `biotope/<id>` nelle ultime ore?" → filter `All`, paginate fino a trovare il biotope_id e leggi cronologicamente.
- "Quanti HGT events ho visto in totale?" → filter `hgt_event` → guarda `total` nel pager.
- "Quando è stato inoculato il primo plasmide?" → filter `mobile_element_release` → vai all'ultima pagina (ordine desc → ultima pagina = prima cronologicamente).

### 9.5 Limiti

- Il payload preview mostra max 4 chiavi del payload. Per ispezione full-payload, attualmente serve query SQL diretta (la Docs view in arrivo la esporrà).
- Non c'è ricerca testuale full-text — solo filter per tipo. Per ricerche su lineage specifico, copia l'UUID del lineage dal drawer e cerca a occhio nella tabella.

---

## 10. Community — multi-seed runs

`/community` lista i **biotopi inoculati con community-mode** (`BIOLOGICAL-MODEL-REVIEW Phase 19`). Sono biotopi avviati con **più seed founder simultaneamente** — utili per studiare interazioni inter-strain dal tick 0.

Ogni entry mostra:

- archetipo del biotope;
- numero di founder seeds;
- fase di inoculo (in quale fase i founder sono stati immessi);
- timestamp di provisioning (UTC);
- tick corrente del biotope;
- lineage count (aumenta con la speciazione);
- link **Open →** alla viewport.

**Use case**: confrontare 2-3 strategie di seed nello stesso biotope. Esempio:

- Seed A = mutator, conjugative_plasmid.
- Seed B = thrifty, latent_prophage.
- Seed C = balanced, none.

In 500 tick, vedrai chi vince per fase. Il vincitore *non è scriptato* — emerge dalle interazioni.

> **Provisioning di una community**: attualmente solo via API simulazione (`Arkea.Game.CommunityLab.provision_community/3`). Una UI di creazione è in roadmap.

---

## 11. Playbook: scenari ricorrenti

### 11.1 "Voglio vedere speciazione veloce"

Setup:

- Archetype: `eutrophic_pond` (ricco di nutrienti, alta turnover).
- `metabolism_profile`: `bloom`.
- `regulation_profile`: `mutator`.
- `mobile_module`: `none`.

Aspettati:

- Tick 30–80: prima ondata di `:lineage_born`.
- Tick 100–200: 5+ lineage diversi.
- Tick 200–400: error catastrophe colpisce alcuni mutator extreme. `:lineage_extinct` events.
- Tick 400+: stato semi-stabile con i mutator "buoni" (quelli che hanno trovato repair fix).

### 11.2 "Voglio vedere arms race ospite-fago"

Setup:

- Archetype: `oligotrophic_lake` (popolazioni più piccole, dinamiche più chiare).
- `metabolism_profile`: `thrifty`.
- `regulation_profile`: `responsive`.
- `mobile_module`: `latent_prophage`.

Aggiungi un **gene custom** con `[transmembrane_anchor, surface_tag]` per dare al seed un `:phage_receptor`.

Aspettati:

- Tick 50–150: stress accumula → SOS attiva → induction del profago.
- Tick 150–300: prima ondata di virion nel phage_pool. Phage load alto in surface.
- Tick 300+: mutazioni loss-of-receptor diventano vantaggiose. Vedrai cluster `cryptic` espandersi (lineage senza phage_receptor).
- Tick 500+: arms race in steady state — alcuni hanno ricostruito il receptor (controvantaggio: meno fitness in altre dimensioni).

### 11.3 "Voglio vedere cycle closure metabolica"

Setup:

- Archetype: `mesophilic_soil` (multiple fasi con gradiente O₂).
- `metabolism_profile`: `balanced`.
- `regulation_profile`: `responsive`.
- `mobile_module`: `none`.

Aggiungi 2-3 **gene custom**:

- Gene 1: `[catalytic_site, substrate_binding]` su target `glucose`.
- Gene 2: `[catalytic_site, substrate_binding]` su target `lactate`.
- Gene 3: `[catalytic_site, substrate_binding]` su target `acetate`.

Aspettati:

- Tick 200–500: cross-feeding tra le tre fasi. La heatmap Chemistry mostra glucose alto in surface, lactate alto in water_column, acetate/CO₂ alto in sediment.
- Tick 500+: cicli stabili. La popolazione totale si mantiene quasi costante.

### 11.4 "Voglio testare la mia hypothesis"

Setup di base + intervention sequence:

1. Provisiona seed con la config che vuoi testare.
2. Aspetta tick ~100 perché il sistema si avvii.
3. Apri Audit, filtra per `mutation_notable` per il tuo biotope_id. Snapshot del baseline.
4. Apri Interventions tab, applica `nutrient_pulse` in una fase scelta.
5. Confronta lineage list a tick 100 vs tick 200 vs tick 400.
6. Documenta in un foglio esterno (no in-app note ancora).

---

## 12. Glossario esteso

### Biologico

| Termine | Significato in Arkea |
|---|---|
| **Arkeon** | L'organismo proto-batterico individuale (genoma + fenotipo derivato + abbondanza per fase). |
| **Lineage** | Discendenza con genoma identico. Un mutante è un **nuovo** lineage. Conta per `richness` e Shannon. |
| **Genome** | `chromosome` (lista di geni) + `plasmids` (lista di records `{genes, inc_group, copy_number, oriT_present}`) + `prophages` (lista `{genes, state, repressor_strength}`). |
| **Gene** | Sequenza di codoni `0..19`, parsata in `domains`. Ha intergenic blocks (expression / transfer / duplication). |
| **Domain** | Unit funzionale del gene. 11 tipi (vedi §4.3). 3 codoni `type_tag` + 20 codoni `parameter_codons`. |
| **Phenotype** | Struct derivato dal genome: `base_growth_rate`, `repair_efficiency`, `n_transmembrane`, `surface_tags`, `competence_score`, `dna_binding_affinity`, ecc. |
| **Cluster** | Categoria fenotipica derivata: `biofilm`, `motile`, `stress-tolerant`, `generalist`, `cryptic`. |
| **HGT** | Horizontal Gene Transfer — coniugazione, trasformazione, trasduzione, infezione fagica. |
| **R-M** | Restriction-Modification — difesa contro DNA esogeno. Methylase del donor bypassa il check (Arber-Dussoix). |
| **SOS response** | Risposta a DNA damage: alza µ e induce profagi. Trigger: `dna_damage_score` > soglia. |
| **Error catastrophe** | Collasso fitness quando `µ × genome_size > 1` (Eigen quasispecies). |
| **Cross-feeding** | Output metabolico di un lineage diventa input di un altro. Cycle closure se chiuso a stato stazionario. |

### Metaboliti (13 canonici)

| Atom | Nome | Note |
|---|---|---|
| `glucose` | Glucosio | Carbonio principale in eutrophic. |
| `acetate` | Acetato | Output di fermentazione. |
| `lactate` | Lattato | Output di fermentazione anaerobic. |
| `oxygen` | O₂ | Tossico per anaerobi (>50 µM). |
| `nh3` | NH₃ | Sorgente di N. |
| `no3` | NO₃⁻ | Accettore di elettroni in denitrificazione. |
| `so4` | SO₄²⁻ | Accettore in dissimilatory sulfate reduction. |
| `h2s` | H₂S | Tossico su citocromo c (>20 µM). Output di sulfate reduction. |
| `h2` | H₂ | Output di fermentazione, input methanogenesi. |
| `co2` | CO₂ | Output di respirazione + fixed via Calvin/Wood-Ljungdahl. |
| `ch4` | CH₄ | Output di methanogenesi. |
| `po4` | PO₄³⁻ | Limitante in oligotrophic lake. |
| `iron` | Fe²⁺/Fe³⁺ | Cofactor di citocromi. |

### UI

| Termine | Significato |
|---|---|
| **Biotope** | Mondo persistente con N fasi, K lineage, condizioni ambientali. |
| **Phase** | Sotto-volume del biotope con condizioni omogenee (surface, sediment, …). |
| **µ** | Tasso di crescita specifico (h⁻¹). |
| **ε** | Repair efficiency (0..1). |
| **H′** | Shannon diversity index calcolato sulla fase. |
| **N** | Popolazione (counts), per fase o totale. |
| **D** | Dilution rate (%/tick). |
| **Phage load** | Somma delle abbondanze di virioni nel `phage_pool` di una fase. |
| **Slot del budget** | Anti-griefing rate-limit per gli intervention. |
| **Audit log** | Tabella append-only degli eventi tipizzati persistiti. |
| **Tick** | Unità di tempo del simulatore. 1 tick = 5 minuti wall-clock. |

Per il glossario completo del modello biologico, vedi [`devel-docs/DESIGN.md`](devel-docs/DESIGN.md) (15 blocks) e [`devel-docs/CALIBRATION.md`](devel-docs/CALIBRATION.md) (range numerici).

---

## 13. FAQ

#### Posso mettere in pausa il simulatore?

No. La simulazione è server-authoritative e gira 24/7. La pausa nello simulatore distrugge la condivisione: se A mette in pausa il suo biotope, B non lo vede aggiornarsi. Per "mettere in pausa la tua attenzione" basta chiudere il browser.

#### Posso resettare il biotope?

Non c'è un reset arbitrario, ma se la **colonia seminata si è estinta** (popolazione totale = 0) puoi **ricolonizzare il biotopo home** con un fondatore fresco. Vedi §5.8 sotto.

#### La mia colonia si è estinta — perdo tutto?

No. Quando il biotopo home (e solo quello) collassa a popolazione 0, sopra la scena del biotopo compare un **banner rosso "Colony extinct"** con un pulsante **"Recolonize home"**. Il click conferma e re-inocula il biotopo con un fondatore costruito **dallo stesso blueprint locked** (lo stesso genoma che hai progettato in Seed Lab) — N=420 distribuito sulle fasi correnti del biotopo. L'evento è loggato in Audit come `intervention` con kind `home_recolonized`.

Solo l'owner del biotopo vede il banner. Biotopi `wild` o di altri player non si possono ricolonizzare.

#### Cosa succede se chiudo il browser durante un intervention?

L'intervention è già stato applicato server-side al click su Confirm. Il rate limit slot è già consumato. Quando torni, vedi solo il risultato.

#### Perché non vedo eventi nella tab Events?

Il biotope è giovane o stabile. Ricontrolla a tick ~100 in poi. Se anche allora la coda è vuota, controlla che il `running` chip sia `live` (non `shell`) — se è `shell` la PubSub subscription è caduta, refresh la pagina.

#### Il mio seed è loccato — come testo nuove configurazioni?

Crea un nuovo player (email diversa). Il seed lock è per blueprint, non per istanza.

#### Posso intervenire su un biotope wild?

No. Solo i biotopi che hai colonizzato (`player_controlled`) accettano intervention. I wild sono ispezionabili ma read-only.

#### Le mie modifiche al draft gene si perdono?

Sì, il draft non è persistito. Se ricarichi la pagina, riparti da zero. Committa quando sei soddisfatto.

#### Vedo `:hgt_transfer` events ma non capisco quale canale di HGT è stato usato

Il payload dell'evento contiene il channel (`:conjugation`, `:transformation`, `:transduction`, `:phage_infection`). Attualmente il preview mostra solo le prime 4 chiavi del payload — apri Audit con filter `hgt_event` per vedere il contesto completo (i payload preview includono il channel).

#### Posso forzare un mutation rate alto in un singolo lineage?

No, non direttamente. Mutation rate è derivato dal `repair_efficiency` del lineage (basso ε → alto µ). Per avere un lineage hypermutator, progetta il seed con `regulation_profile: mutator`. La risposta SOS amplifica ulteriormente µ in lineage stressati.

#### I lineage di altri player possono migrare nel mio biotope?

Sì, se i biotopi sono connessi via migration edge nel world graph. La migration è bilateral e gated da dilution rate. Cellule estranee possono attecchire solo se il phenotype regge le pressioni selettive locali.

#### Il bundle JS è davvero così piccolo?

Sì, ~50 KB minified. Tutta la grafica è SVG nativo renderizzato server-side via Phoenix LiveView. Niente WebGL, niente canvas, niente framework JS.

#### Dove trovo le costanti del modello?

Tutte le costanti chiave + range biologico di letteratura sono in [`devel-docs/CALIBRATION.md`](devel-docs/CALIBRATION.md). Override per benchmark scientifici sono nella stessa sezione.

#### Come sapere se la mia hypothesis è "originale"?

Non c'è un sistema di lookup. Confronta il tuo seed con quelli in `/community` se ce ne sono. Per il prototipo non c'è leaderboard né meccanismo di originalità.

---

## 14. Troubleshooting

### Sintomo: "Biotope viewport mostra No phases / popolazione zero"

**Causa probabile**: il `Biotope.Server` per quell'id non è registrato nel runtime. Può succedere se:

- Hai resettato il database (`mix ecto.reset`) ma il runtime BEAM è ancora vivo.
- Il seeding del default scenario è stato disabilitato (commit `fda5031`).

**Fix**: provisiona un nuovo seed dal Seed Lab (l'azione spawna un `Biotope.Server` fresco).

### Sintomo: "Events tab è sempre vuota"

**Causa probabile**: la tua subscription al PubSub del biotope è caduta.

**Verifica**:

1. Sidebar KPI: `Stream` chip deve essere `live` (verde). Se è `shell`, refresh.
2. Browser console (F12): cerca errori WebSocket. Se vedi disconnessioni ripetute, controlla la connettività al server.

### Sintomo: "Intervention button è sempre disabled"

**Cause possibili**:

- **Non sei owner del biotope**. Verifica `Topology modal` (⚙ in header): se `owner` è "wild" o un altro player, non puoi intervenire.
- **Rate limit attivo**. Lo status mostra `Locked X` con countdown. Aspetta.
- **`selected_phase_name` è nil**. Click su una fase nella sidebar prima di applicare l'intervento (per gli intervention scoped per fase).

### Sintomo: "Non vedo HGT events nonostante abbia un conjugative_plasmid"

**Cause possibili**:

- Densità di popolazione troppo bassa. La conjugazione richiede contact rate proporzionale a `density²`. Aspetta tick ~50–100 perché la popolazione cresca.
- Il plasmide non ha `oriT_site` nel suo `regulatory_block`. In Audit cerca `mobile_element_release` per il tuo biotope per verificare se il plasmide è stato rilasciato nel pool della fase.
- I recipient potenziali hanno R-M difensivo che digerisce il plasmide. Cerca `rm_digestion` events in audit.

### Sintomo: "Il mio mutator strain si estingue subito"

**Causa probabile**: error catastrophe. Con `repair_efficiency` molto basso, le mutazioni accumulate per replicazione superano il threshold di Eigen e la fitness collassa.

**Fix**:

- Aggiungi nel seed un `:repair_fidelity` domain con parametri alti per compensare.
- Riduci aggressività del mutator profile (passa da `mutator` a `responsive`).

### Sintomo: "Chemistry heatmap mostra colonne tutte gialle (saturazione)"

**Causa probabile**: una fase ha concentrazione molto più alta di tutte le altre, e la normalizzazione mette a 1 quella concentrazione, schiacciando le altre a quasi-0.

**Workaround**: ispeziona i valori puntuali via Phase inspector (KPI in sidebar) per la fase di interesse, oppure usa Audit per query specifiche.

### Sintomo: "Performance degrada dopo molti biotopi"

**Causa probabile**: il prototipo gira single-node BEAM. Ogni biotope è un processo indipendente, ma il rendering SVG nel browser scala con (lineage × particle count). Con 100+ lineage in un biotope, la viewport può rallentare.

**Mitigazione**: il `MAX_PHASE_PARTICLES = 60` cap già limita il render. Per biotopi molto popolosi, usa Lineages tab (più denso) invece della scena visuale.

### Sintomo: "Voglio chiudere la sessione e ripartire da zero"

`/players/log-out` chiude la sessione. Ti riporta a `/`. Per ripartire da zero, registra un nuovo account con email diversa. Il vecchio account resta accessibile via "Resume player".

---

## Feedback e contributi

Bug, suggerimenti, walkthrough scientifici da validare → vedi [README.md](README.md) per i canali del progetto. Il modello biologico è in evoluzione: la roadmap è in [`devel-docs/BIOLOGICAL-MODEL-REVIEW.md`](devel-docs/BIOLOGICAL-MODEL-REVIEW.md).

Se trovi una calibrazione che non quadra con la tua intuizione di microbiologo, apri un issue con una citazione di letteratura primaria. Tutti i parametri chiave sono già mappati al range biologico in [`devel-docs/CALIBRATION.md`](devel-docs/CALIBRATION.md), quindi possiamo confrontare e correggere.
