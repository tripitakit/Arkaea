> 🇮🇹 Italiano (questa pagina) · [🇬🇧 English](DESIGN.en.md)

# Arkea — Documento di Inception & Design

## Contesto

**Arkea** è un gioco/simulazione di evoluzione di organismi proto-batterici (gli *Arkeon*). L'obiettivo del progetto è creare un'esperienza che sia:

- **Scientificamente accurata**, rivolta a un pubblico di biologi, microbiologi, genetisti e biologi molecolari
- Una **web app con UI 2D WebGL**
- Centrata sulla creazione di un Arkeon: il giocatore ne definisce **struttura cellulare** (membrana, parete, proteine integrate) e **genoma** (geni strutturali ed enzimatici per metabolismo e replicazione)
- Capace di simulare **elementi genetici mobili** (plasmidi, profagi) per il trasferimento orizzontale di tratti, vie metaboliche e resistenze

Il vincolo guida è: **semplificare di diversi ordini di grandezza** la complessità di un genoma batterico reale, **senza banalizzare la biologia**. Il pubblico esperto deve riconoscere meccanismi reali (operoni, regolazione σ-factor, riboswitch, integrasi, mutagenesi puntiforme, riarrangiamenti) e poter ragionare con la propria expertise.

Questo documento consolida le decisioni di scope prese nelle prime sessioni di brainstorming e rimane il riferimento di design da cui derivare i piani implementativi successivi.

---

## Decisioni consolidate

### Blocco 1 — Architettura del mondo

| Asse | Scelta |
|---|---|
| Genere | Sandbox evolutivo + ecosistema strategico-competitivo (ibrido) |
| Persistenza | Mondo persistente, simulazione 24/7 server-side |
| Multiplayer | **Mondo unico condiviso (MMO-like)**: tutti i giocatori popolano lo stesso ecosistema |
| Tempo | **Continuo accelerato anche offline**: l'ecosistema evolve a prescindere dalla presenza del giocatore |
| Ruolo del giocatore | **Designer + Allevatore/ingegnere**: progetta l'Arkeon iniziale e poi interviene attivamente (selezione, introduzione di plasmidi, modifiche genomiche mirate) |

**Tensioni note rimandate a fase successiva:**
- Comportamento dell'Arkeon del giocatore quando offline (estinzione possibile? stasi? autopilota AI?)
- Onboarding di nuovi giocatori in mondo già evoluto
- Anti-griefing e bilanciamento competitivo
- Costi infrastrutturali della simulazione 24/7
- Sharding/scaling all'aumentare della popolazione di giocatori

### Blocco 2 — Granularità del modello biologico

**Scelta: livello "B+C" — modulare con tocchi sub-genici.**

#### Genoma
- **Cromosoma** = sequenza ordinata di **geni** (oggetti discreti) raggruppati in **operoni**
- Ogni gene ha:
  - **Identità funzionale** generata da un **sistema astratto/generativo** (le funzioni emergono da parametri composabili, non da catalogo finito predefinito)
  - **Parametri quantitativi** (Km, Vmax, affinità, stabilità) — substrato della selezione
  - **Sequenza simbolica corta** (~50-200 codoni logici, non ATGC reali) sufficiente a supportare mutazioni puntiformi, hotspot di ricombinazione, siti di integrazione
- **Plasmidi e profagi** = frammenti genomici separati con propria dinamica (replicazione, perdita, integrazione cromosomica, escissione)

#### Regolazione genica (profondità scelta)
- **Operoni** con promotori on/off modulati da **metaboliti ambientali** (induzione/repressione)
- **Sigma factor** per programmi trascrizionali globali (es. risposta a stress, sporulation-like, fase stazionaria)
- **Riboswitch** per regolazione post-trascrizionale rapida (es. legame diretto a metabolita)

#### Mutazioni supportate
- Puntiformi (sostituzioni di codoni logici)
- Indels
- Duplicazioni di geni (substrato per neofunzionalizzazione)
- **Riarrangiamenti grandi**: inversioni e traslocazioni

#### Metabolismo
- 8-15 metaboliti chiave come "valuta chimica" (set esatto da definire nel Blocco 3)
- Reazioni catalizzate dagli enzimi codificati nel genoma, cinetica Michaelis-Menten semplificata
- Bilancio ATP-equivalente come vincolo centrale (replicazione, sintesi proteica, trasporto attivo costano)
- Proto-FBA stazionario ricalcolato per tick (non simulazione molecolare)

#### Membrana e parete
- **Membrana**: composizione lipidica (fluidità, permeabilità) + proteine integrali (porine, trasportatori, recettori, pompe di efflusso)
- **Parete**: tipo (assente / Gram-like sottile / Gram-like spessa / S-layer) → costo metabolico + resistenza a stress osmotico, lisi, fagi
- È il principale **fenotipo visibile** sulla UI 2D WebGL

#### Esclusioni deliberate
- Niente ribosomi/traduzione reali (i geni producono enzimi a un rate parametrico)
- Niente replisoma reale (divisione = evento con costo + tasso d'errore)
- Niente strutture intracellulari complesse (no compartimenti, no citoscheletro)
- Niente DNA ATGC reale (sequenza simbolica più astratta)

**Razionale del sistema generativo per le funzioni**: un catalogo finito (es. 200 famiglie KEGG predefinite) sarebbe più leggibile ma chiuderebbe lo spazio evolutivo. Un sistema generativo (parametri composabili che producono funzioni nuove sotto pressione selettiva) preserva la natura aperta dell'evoluzione, a costo di maggiore complessità di design del modello.

---

### Blocco 3 — Ambiente e pressione selettiva

#### Spazialità — modello ibrido a due scale

**Macroscala**: il mondo è un grafo di **biotopi multipli connessi**. Ogni biotopo è un chemostato locale con propria chimica (concentrazioni di metaboliti), parametri fisici (temperatura, pH, osmolarità), e popolazione di Arkeon. La **migrazione** fra biotopi avviene tramite flussi/dispersione parametrici. Questa è la scala su cui gira la simulazione 24/7 server-side.

**Microscala**: quando un giocatore osserva un biotopo da vicino, viene presentata una **rappresentazione 2D continua locale** della stessa popolazione e chimica. La microscala è prevalentemente di **visualizzazione/interazione** (la fisica dettagliata non è autoritativa per la simulazione globale, ma il giocatore vede gradienti, biofilm, colonie). Questo permette UI WebGL ricca senza pagare il costo di diffusione 2D ovunque.

**Conseguenze:**
- Le nicchie ecologiche sono globali (per biotopo) ma riconoscibili visivamente
- Il costo di simulazione scala con il numero di biotopi, non con l'area visualizzata
- Il design dovrà chiarire che cosa della microscala è autoritativo (es. eventi locali del giocatore?) e che cosa è puramente decorativo

#### Eventi e perturbazioni — sistema + giocatore sul proprio biotopo

- **Eventi sistemici**: cicli stagionali, perturbazioni casuali, evoluzione naturale di fagi e altri elementi mobili, arrivi di nutrienti
- **Interventi del giocatore**: limitati al **proprio biotopo** — può introdurre antibiotici, regolare nutrienti, inoculare ceppi, rilasciare plasmidi, modificare parametri fisici
- **Niente PvP diretto**: i giocatori non possono perturbare il biotopo altrui. La competizione fra giocatori avviene **indirettamente** via:
  - Migrazione di Arkeon e elementi mobili fra biotopi connessi
  - Successo evolutivo dei propri ceppi nei biotopi del network
  - Eventuale "leaderboard" ecologica (occupazione di nicchie, dominanza, diversità)

Questa scelta riduce drasticamente i requisiti di anti-griefing e tiene il gioco accessibile, pur preservando l'interazione ecologica genuina via flussi inter-biotopo.

#### Sotto-temi ancora da definire (rimandati a esercizi dedicati)

1. **Inventario chimico**: 8-15 metaboliti chiave (glucosio, NH₃, O₂, lattato, H₂S, PO₄, Fe²⁺...). Da ancorare a microbiologia reale.
2. **Pressioni selettive**: meccanismi di morte e perdita (lisi osmotica, starvation, predazione fagica, antibiosi, competizione, dilution).
3. **Topologia del network di biotopi**: numero, connessioni, regole di flusso, eterogeneità ambientale.
4. **Cosa della microscala è autoritativo** vs puramente di visualizzazione.

---

### Blocco 4 — Modello di popolazione

**Scelta: popolazione polimorfica con tracciamento per lignaggi (lineage-based modeling).**

L'unità base è il **lignaggio** (un genotipo distinto + un'abbondanza), non la cellula. Ogni biotopo mantiene una **foresta di lignaggi** ciascuno con genoma completo, abbondanza Nᵢ, fitness wᵢ, puntatore al parent → albero filogenetico ricostruibile.

#### Dinamica di un tick (per biotopo)

1. **Crescita differenziale** del lignaggio dipendente da fitness × ambiente − costi metabolici − death rate − dilution
2. **Mutazione**: probabilità µ ad ogni divisione (modulata da σ-factor di stress) → nasce un nuovo lignaggio figlio
3. **HGT**: eventi probabilistici di coniugazione/trasduzione/trasformazione fra lignaggi del biotopo (inclusi migranti) → nuovo lignaggio con elemento mobile acquisito
4. **Migrazione**: frazione dell'abbondanza fluisce ai biotopi vicini mantenendo il genotipo
5. **Pruning**: lignaggi con N sotto soglia rimossi dalla foresta locale (ma conservati nell'albero filogenetico globale)

#### Storage genomico — delta encoding

- Genoma di riferimento per ogni ceppo fondatore
- Ogni lignaggio memorizza solo un **delta** (lista di mutazioni rispetto al riferimento del proprio clade), come VCF
- Riarrangiamenti grandi possono consolidare un nuovo riferimento se il delta diventa eccessivo

#### Cap operativi (deciso 2026-04-25)

- **Cap di lignaggi per biotopo**: **1.000**
- **Politica al raggiungimento del cap**: **estinzione dei lignaggi più rari** (i meno abbondanti vengono eliminati dalla foresta locale)
- **Albero filogenetico storico**: **decimazione periodica** (mantenere solo le ramificazioni di interesse, es. quelle che hanno raggiunto un'abbondanza massima storica sopra soglia)

#### Implicazioni su UI e DB

- **UI**: aggregazione per cluster fenotipico (1.000 lignaggi non sono leggibili individualmente); vista filogenetica opzionale; highlight dei lignaggi del giocatore e dei dominanti
- **DB**: tabella `lineages(id, biotope_id, parent_id, abundance, delta_genome, fitness_cache)`; albero storico in tabella separata, decimato periodicamente

---

### Blocco 5 — Meccanismi del motore biologico

**Principio unificante**: *tutto è metabolismo* (anche i farmaci) e *tutto è codificato nel genoma* (anche la coniugazione, il tasso di mutazione, i costi). Nessun meccanismo speciale "sopra" il modello biologico.

#### Xenobiotici come metaboliti speciali (target → drug → effetto)

Ogni farmaco/xenobiotico è un metabolita del modello chimico, con concentrazione nel biotopo, trasporto via porine/efflux codificati, e degradazione enzimatica possibile (es. β-lattamasi → idrolisi). In più ha:
- **`target_class`** (es. `pbp_like`, `ribosome_like`, `dna_polymerase_like`, `membrane`, `efflux_pump`)
- **`affinity`** (Kd verso il target)
- **`mode`** (cidal vs static; meccanismo: blocca-sintesi, fora-membrana, induce-mismutazioni…)

Quando presente, lega le proteine target del lignaggio con rate ∝ `[drug] × [target] / Kd`. Il target legato è non-funzionale → conseguenza dipendente dal target. La "MIC" emerge dalla quantità di target libero che il lignaggio mantiene.

**Conseguenza**: nessun sistema "antibiotici" separato. Un framework unico copre β-lattamici, aminoglicosidi-like, fluorochinoloni-like, ecc., e l'evoluzione di resistenza emerge dagli stessi meccanismi che gestiscono ogni metabolismo.

#### Tasso di mutazione modulabile (SOS-like)

Ogni lignaggio ha un µ corrente:

```
µ = µ_baseline × Π (1 + α_i × expr(repair_gene_i))
```

dove i `repair_gene_i` sono geni codificati di riparazione/fidelity (`mutS_like`, `dnaQ_like`, ecc.). In più, σ-factor di stress può attivare una **polimerasi error-prone** (DinB/Pol-V-like) che alza µ direttamente. **Il tasso di mutazione è un fenotipo evolvibile** — i mutator strains emergono naturalmente.

#### Coniugazione gene-encoded

Un plasmide è coniugativo se e solo se porta `pili_like + relaxase_like + oriT_like`. Rate di coniugazione fra donatore D e ricevente R nello stesso biotopo:

```
rate = expr(pili_D) × Nᴅ × Nʀ × compatibility(D, R)
```

`compatibility` dipende da recettori superficiali del ricevente, entry-exclusion, ecc. Plasmidi non-coniugativi si spostano per trasformazione (DNA libero) o mobilizzazione tramite plasmide helper.

#### Costo del plasmide

Due componenti, niente "slot" (il "costo di slot" è un artefatto della rappresentazione, non biologia):
- **Replicazione**: ATP proporzionale alla dimensione del plasmide (numero di geni × costo per gene), pagato ad ogni divisione
- **Burden trascrizionale**: ogni tick, somma dell'espressione dei geni del plasmide × costo per proteina (aminoacidi-eq / ATP)

Plasmidi grandi e fortemente espressi sono costosi → trade-off naturale: utili sotto pressione selettiva, perdita per dilution quando la pressione cessa.

#### Migrazione fra biotopi

**Drip continuo come default**. Per ogni arco A → B e ogni lignaggio i:

```
ΔNᵢ_migrato = base_flow × edge_weight × (Nᵢ_A / N_totale_A) × biotope_compatibility
```

`base_flow` globale; `edge_weight` riflette la connettività (canale stretto vs flusso ampio); `biotope_compatibility` riduce migrazione fra ambienti molto diversi.

**Eventi discreti (Poisson)** riservati a fenomeni rari: trasporto da fagi liberi, dispersione massiva (airborne), eventi catastrofici.

#### Sistema generativo per le funzioni geniche — innovazioni discontinue

Le funzioni dei geni emergono da un sistema **a domini con composizione**, non da un catalogo finito né da soli parametri continui:

1. **Spazio funzione misto discreto+continuo**: ogni proteina ha un descrittore `(dominio_funzionale_categorico, parametri_continui)`. Mutazioni puntiformi tipicamente cambiano i parametri continui (tuning fine). Mutazioni in codoni "strutturali" possono **flippare il dominio_funzionale_categorico** — eventi rari ma possibili (es. cambio di specificità di substrato in un trasportatore).
2. **Fusione/scissione tramite riarrangiamenti grandi**: una traslocazione che fonde due geni produce una proteina chimera con funzione genuinamente nuova (combinazione dei domini). È il meccanismo principale dell'innovazione evolutiva reale, e il modello lo supporta esplicitamente.

**Conseguenza**: il modello permette tre regimi di evoluzione: drift parametrico (tuning), salti di specificità (cambio di dominio), innovazione composta (fusione). Tutti emergono dallo stesso sistema di mutazioni.

---

### Blocco 6 — Inventario metabolico

**Scelta: 13 metaboliti** ancorati a microbiologia reale, progettati per supportare nicchie ecologiche distinte e cicli biogeochimici interconnessi (C, N, S, Fe).

| # | Metabolita | Ruoli |
|---|---|---|
| 1 | **Glucosio** (zucchero-eq, CHO_org) | Substrato C/energia (donatore di elettroni), heterotrofia |
| 2 | **Acetato** | Substrato + prodotto fermentazione, cross-feeding chiave |
| 3 | **Lattato** | Prodotto fermentazione + substrato per altri; alta concentrazione → acidifica |
| 4 | **CO₂** | Prodotto universale + fissabile da autotrofi; ↑ acidifica leggermente |
| 5 | **CH₄** (metano) | Prodotto metanogenesi (H₂ + CO₂) + substrato per metanotrofi (con O₂) |
| 6 | **H₂** (idrogeno) | Donatore inorganico per chemiolitotrofi e metanogeni |
| 7 | **O₂** | Accettore aerobico; tossico per anaerobi obbligati (induce stress σ-factor) |
| 8 | **NH₃/NH₄⁺** | Fonte N + donatore inorganico (nitrificatori) |
| 9 | **NO₃⁻** | Accettore anaerobico + fonte N (denitrificazione → N₂ gassoso) |
| 10 | **H₂S** | Donatore inorganico + fonte S; tossico ad alte concentrazioni (inibisce citocromi) |
| 11 | **SO₄²⁻** | Accettore anaerobico + fonte S (riduttori → H₂S, ciclo dello zolfo) |
| 12 | **Fe²⁺ ⇌ Fe³⁺** (coppia redox) | Accettore (Fe³⁺) + cofattore + donatore (Fe²⁺); supporta riduttori e ossidatori del ferro |
| 13 | **PO₄³⁻** | Nutriente essenziale (acidi nucleici, fosfolipidi); spesso limitante in biotopi oligotrofici |

**Esclusioni deliberate (riserva di estensione futura):**
- Aminoacidi e peptidi liberi (auxotrofie, cross-feeding amminoacidico)
- Vitamine / cofattori organici (B12-like, biotina-like, growth factors)

**ATP-eq** non è in questo elenco: è la valuta energetica *interna* del lignaggio (Blocco 2), non una concentrazione ambientale.

#### Strategie metaboliche supportate (≥10 nicchie distinte)

| Strategia | Equazione semplificata | Nicchia tipica |
|---|---|---|
| Heterotrofo aerobico | Glucosio + O₂ → CO₂ + ATP (alto yield) | Biotopo ossigenato organico |
| Fermentatore | Glucosio → Lattato/Acetato + ATP (basso yield) | Anaerobico organico |
| Denitrificatore | Glucosio + NO₃⁻ → CO₂ + N₂ + ATP | Anaerobico nitrico |
| Riduttore di solfato | Glucosio (o H₂) + SO₄²⁻ → H₂S + ATP | Anaerobico solforoso |
| Riduttore di ferro | Glucosio + Fe³⁺ → CO₂ + Fe²⁺ + ATP | Anaerobico ferroso |
| **Metanogeno** | H₂ + CO₂ → CH₄ + ATP (o acetato → CH₄ + CO₂) | Anaerobico stretto |
| **Metanotrofo** | CH₄ + O₂ → CO₂ + ATP | Interfaccia ossico/anossico |
| Idrogenotrofo aerobico | H₂ + O₂ → H₂O + ATP | Chemiolitotrofia, autotrofia con CO₂ |
| Ossidatore di solfuri | H₂S + O₂ → SO₄²⁻ + ATP | Interfaccia ossico/anossico, idrotermale |
| Nitrificatore | NH₃ + O₂ → NO₃⁻ + ATP | Aerobico oligotrofico |
| Ossidatore di ferro | Fe²⁺ + O₂ → Fe³⁺ + ATP | Acidofili, drenaggi acidi |

Cicli chiusi: **C** (CO₂↔CH₄, glucosio↔acetato/lattato↔CO₂), **N** (NH₃↔NO₃⁻↔N₂), **S** (SO₄²⁻↔H₂S), **Fe** (Fe²⁺↔Fe³⁺). Le nicchie sono interdipendenti — prodotti di una alimentano un'altra → cross-feeding emergente.

#### Parametri ambientali (non metaboliti, ma stato del biotopo)

- **Temperatura**: modula k cinetiche; ranges di tolleranza specie-specifici (psicrofilo/mesofilo/termofilo/iperterifilo)
- **pH**: *emergente* dalle concentrazioni — CO₂↑, lattato↑, H₂S↑ acidificano; NH₃↑ alcalinizza. Ranges di tolleranza specie-specifici
- **Osmolarità**: somma dei soluti; impatta lisi osmotica e scelta della parete

Questi tre parametri permettono biotopi *fisicamente* distinti (idrotermale acido-caldo vs lago freddo-alcalino) oltre che chimicamente, moltiplicando le nicchie.

---

### Blocco 7 — Sistema generativo dei domini funzionali

#### Struttura del gene

Un gene è una sequenza ordinata di **codoni logici** (50–200 simboli), su un alfabeto di **20 simboli** (analogo agli aminoacidi). I codoni si raggruppano in blocchi consecutivi, ciascuno dei quali codifica un **dominio funzionale**:

```
gene = [ promoter_block ] [ regulatory_block (opzionale) ] domain_1 domain_2 ... domain_N
```

Ogni dominio:
- **Type tag** (primi ~3 codoni): identifica categoricamente il tipo
- **Parameter codons** (resto, 10–30 codoni): codificano i parametri continui

Lunghezza tipica: 2–10 domini per gene, coerente con proteine reali.

#### Tassonomia dei tipi di dominio (11)

| # | Tipo | Parametri continui chiave |
|---|---|---|
| 1 | **Substrate-binding pocket** | target_metabolite_id, Km, specificity_breadth |
| 2 | **Catalytic site** | reaction_class (hyd/ox/red/isom/lig/lyase), kcat, cofactor |
| 3 | **Transmembrane anchor** | hydrophobicity, n_passes |
| 4 | **Channel/pore** | selectivity, gating_threshold |
| 5 | **Energy-coupling site** | atp_cost, pmf_coupling |
| 6 | **DNA-binding** | promoter_specificity, affinity |
| 7 | **Regulator output** | mode (activator/repressor), cooperativity |
| 8 | **Ligand sensor** | sensed_metabolite_id, threshold, response_curve |
| 9 | **Structural fold** | stability, multimerization_n |
| 10 | **Surface tag** | tag_class (pilus_receptor / phage_receptor / surface_antigen) |
| 11 | **Repair/Fidelity** | repair_class (mismatch/proofreading/error-prone), efficiency |

**Parametri trasversali**: thermal_stability, pH_optimum, expression_cost (codoni "structural" nel blocco).

**Codifica dei parametri continui**: somma pesata dei valori dei codoni del blocco-parametri (smooth landscape: mutazioni puntiformi → piccoli spostamenti del valore).

#### Regulatory block — siti di binding multipli

Il `regulatory_block` di un gene/operone permette **binding sites multipli sovrapponibili** per σ-factor diversi e per riboswitch → regolazione combinatoria realistica (programmi globali σ + regolazioni locali metabolite-specifiche).

#### Composizione e regole di coerenza

Una proteina = sequenza di domini. La funzione emerge da composizione e parametri. Esempi:

| Funzione | Composizione |
|---|---|
| Trasportatore glucosio | `[Substrate-binding(Glu, Km)] [Channel/pore] [Transmembrane]` |
| Trasportatore attivo (ABC-like) | `[Substrate-binding] [Channel/pore] [Energy-coupling] [Transmembrane]` |
| β-lattamasi | `[Substrate-binding(β-lactam)] [Catalytic site(hydrolysis)]` |
| Pompa di efflusso | `[Substrate-binding(broad)] [Channel/pore] [Energy-coupling] [Transmembrane]` |
| σ-factor | `[Ligand sensor] [DNA-binding] [Regulator output]` |
| Riboswitch | nel `regulatory_block`: `[Ligand sensor] [translation_modulator]` |
| PBP-like | `[Substrate-binding(peptidoglycan_precursor)] [Catalytic site(transpeptidation)] [Transmembrane]` |
| DinB-like (error-prone pol) | `[Substrate-binding(dNTP, low spec)] [Catalytic site(polymerization)] [Repair/Fidelity(error-prone)]` |
| Subunità di pilo | `[Structural fold(rigid, n=80)] [Surface tag(pilus_receptor)]` |

**Regole di coerenza** (emergono dal calcolo del fitness, non sono hard constraints):
- `Catalytic site` senza `Substrate-binding` adiacente → inerte
- `Energy-coupling` senza `Channel/pore` o `Catalytic` → inerte
- `Regulator output` senza `DNA-binding` → inerte
- `Ligand sensor` isolato → utile solo in regulatory_block

La "resistenza a un farmaco" non è un attributo speciale: è il risultato di parametri (Km alto su PBP) o della presenza di un dominio aggiuntivo (β-lattamasi). Coerente con biologia reale.

#### Mutazioni e generazione di novità

| Tipo mutazione | Effetto | Frequenza relativa |
|---|---|---|
| Puntiforme in parameter codon | Drift continuo del parametro | Alta (maggioranza) |
| Puntiforme nel type tag | Flip categorico del tipo (innovazione discontinua) | Bassa (tag = 3 codoni) |
| Indel | Shift confini, rottura tag, frame shift | Media |
| Duplicazione | Copia dominio o gene → substrato per neofunzionalizzazione | Media |
| Inversione | Rovescia segmento, flippa orientamento tag | Bassa |
| **Traslocazione tra geni** | **Fonde domini di geni diversi → chimera composta** | Bassa (motore principale dell'innovazione vera) |

#### Complessi multi-subunità

Dichiarati da `Structural fold(multimerization_n=k)` + `Surface tag` di self-recognition. Attività ∝ min delle abbondanze di subunità compatibili. Nessuna astrazione aggiuntiva.

#### Bilancio biomassa (no tracking molecolare)

Variabili continue per lignaggio: `membrane_integrity`, `wall_integrity`, `dna_progress` ∈ [0,1].
- Prodotte da enzimi del lignaggio (es. PBP-like → wall_integrity), consumando metaboliti del Blocco 6 + ATP
- Degradate da stress (osmotico, antibiotico, lisi)
- `wall_integrity < soglia` durante divisione → lisi → riduzione N o estinzione

---

### Blocco 8 — Pressioni selettive

#### A. Pressioni continue (riducono fitness)

1. **Stress fisico-chimico fuori-range**: temperatura/pH/osmolarità deviano dai range delle proteine (`thermal_stability`, `pH_optimum`) → calo progressivo di kcat (denaturazione) → fitness scende.
2. **Tossicità di metaboliti**: O₂ per anaerobi obbligati (induce σ-stress, alza µ via DinB-like); H₂S inibisce citocromi via binding competitivo su Catalytic site di redox; lattato accumulato → acidifica → effetto (1).
3. **Carenze metaboliche**: ATP balance cronicamente negativo → rate di divisione → 0; carenze specifiche (P → no DNA, N → no proteine, Fe → no cofattori, S → no aa solforati). Selezione per Km basso in nicchie oligotrofiche.

#### B. Eventi di morte discreta

4. **Lisi alla divisione**: probabilità ∝ deficit di `wall_integrity` × stress osmotico.
5. **Lisi fagica**: vedi sotto-sistema fagico.
6. **Errori letali di replicazione**: µ estremo → frazione dei figli non vitali → upper bound naturale a µ (error catastrophe emergente).

#### C. Outflow non-selettivo

7. **Dilution rate**: parametro **per-biotopo** (eterogeneità ecologica gratis: stagni vs fiumi). Frazione costante della popolazione lavata via per tick. Diluisce metaboliti, segnali, fagi liberi. Inflow di nutrienti freschi accoppiato (chemostato classico). Imposta carrying capacity, seleziona per growth rate assoluto.

#### D. Competizione

8. **Competizione per risorse condivise**: emergente, no meccanismo dedicato. Lignaggi con Km basso o trasportatori più espressi vincono il pool condiviso → altri patiscono carenze.
9. **Bacteriocine**: tossine secrete `[Substrate-binding(target_surface_tag)] [Catalytic(membrane_disruption)]` + flag "secreted". Warfare biologico fra ceppi → diversificazione delle superfici per evasione.

#### Sotto-sistema fagico

- **Profago** = cassetta nel cromosoma/plasmide: receptor (Surface tag), repressore lisogenico (Regulator output + DNA-binding), polimerasi virale, capside (Structural fold × N), geni di lisi (Catalytic membrane_disruption).
- **Switch lisogenico ↔ litico**: stress (DNA damage, σ-SOS) degrada il repressore → induzione. Switch stocastico modulato da stress.
- **Fagi liberi**: entità persistenti del biotopo, con genoma + Surface tag per riconoscimento. Diffondono via migrazione (eventi Poisson — Blocco 5).
- **Difese** (coperte dai domini esistenti):
  - **Loss-of-receptor**: mutazione del Surface tag dell'ospite
  - **Restriction-Modification**: enzima `[Substrate-binding(DNA, palindrome)] [Catalytic(DNA cleavage)]` + methylase con stessa specificità → arms race su palindromi virali
- **CRISPR**: omesso dalla v1 (richiede memoria adattiva qualitativamente diversa). Riserva di estensione futura.
- **Co-evoluzione**: i fagi mutano come gli Arkeon (stesso sistema generativo) → arms race genuino.

##### Fase 12 — Stato implementativo

- **Cassette profago** (`Genome.prophage()` → `%{genes, state, repressor_strength}`): il flag `state :: :lysogenic | :induced` rende esplicito il commit verso il ciclo litico; `repressor_strength :: float()` (0.0..1.0) modula la sensibilità all'induzione da stress: `p_induction = 0.03 × stress_factor × (1 − repressor_strength)`.
- **Virioni liberi** (`Arkea.Sim.HGT.Virion`): pool di particelle persistenti per fase, con `genes` (cassette confezionata), `surface_signature` (chiave 4-codoni per receptor matching), `methylation_profile` (host modification ereditato), `decay_age`. Decadimento `Phage.decay_step/1` indipendente dalla dilution: `decay = 0.20 + 0.05 × decay_age`.
- **`HGT.Phage.lytic_burst/5`**: produce virioni nel `phage_pool` della fase primaria (burst size emergente da `Σ multimerization_n` dei `:structural_fold` del cassette, range biologicamente plausibile 10–500); rilascia frammenti chromosomiali nel `dna_pool` della stessa fase (substrato per Fase 13 trasformazione); rimuove la cassette dal genome dell'ospite lisato.
- **`HGT.Phage.infection_step/4`** (`Tick.step_phage_infection/1` nel pipeline): ogni virione tenta l'infection sui recipient compatibili nella stessa fase. Receptor matching via `surface_signature`. Gating uniforme via `HGT.Defense.restriction_check_virion/3`. Decisione lytic/lysogenic dal `repressor_strength` del cassette: alta repressione → lisogenia (child lineage con prophage integrato), bassa repressione → lisi immediata.
- **`HGT.Defense.restriction_check/3`**: gate R-M generativo. Riconoscimento sito = `signal_key` del Catalytic site di un gene contenente sia `:dna_binding` che `:catalytic_site(reaction_class: :hydrolysis)` (restrizione) o `:isomerization` (metilazione). Bypass via metilazione del donor che condivide signal_key con l'enzima del recipient (Arber-Dussoix host-modification). Cleavage probabilistico (`@cleave_p = 0.70` per sito vulnerabile) per riprodurre l'escape baseline in vivo (Tock & Dryden 2005).
- **Phenotype esteso** (Phase 12): `restriction_profile :: [signal_key]` e `methylation_profile :: [signal_key]` derivati da composizione di geni con `dna_binding + catalytic_site` co-occorrenti.
- **Audit log mobile_elements**: schema esistente; il write path per gli eventi del ciclo fagico (`:phage_infection`, `:rm_digestion`) sarà cablato in Fase 16 con il behaviour `HGT.Channel`.

##### Fase 13 — Trasformazione naturale

- **DNA libero come substrato** (`Arkea.Sim.HGT.DnaFragment`): pool di frammenti per fase (`Phase.dna_pool :: %{fragment_id => DnaFragment.t()}`) con `genes` (cromosoma del lisato), `methylation_profile` (host modification ereditato), `abundance`, `decay_age`, `origin_lineage_id`. Sources: lisi fagica (`HGT.Phage.lytic_burst` deposita il cromosoma della cellula lisata); future Fasi 14+ aggiungeranno lisi alla divisione.
- **Competenza emergente** (`Phenotype.competence_score :: 0.0..1.0`): non-zero solo se il genoma esprime la triade Phase-13 — `:channel_pore` (proxy ComEC/ComEA) + `:transmembrane_anchor` (proxy pseudopilus tipo IV) + `:ligand_sensor` (proxy ComX / segnale di induzione). Score = `min(1.0, geom_mean(n_channel × n_membrane × n_sensor) × 0.2)`. Soglia di gating effettiva 0.10. Genoma "naïf" → competence 0.0 (niente uptake gratuito).
- **`HGT.Channel.Transformation.step/4`** (nel pipeline `Tick.step_hgt` tra coniugazione e induzione): per ogni recipient competente, scorre il `dna_pool` della fase, calcola `p_uptake = 0.0006 × competence × fragment.abundance` (cap 0.20), gating R-M via `HGT.Defense.restriction_check/3` con `fragment.methylation_profile`, ricombinazione omologa posizionale (allelic replacement: gene a posizione *i* del donor → posizione *i* del recipient se entrambi gli indici esistono).
- **Self-uptake escluso**: `fragment.origin_lineage_id == recipient.id` → rifiutato (no-op deterministico, evita inflazione).
- **Conservazione**: ogni evento di gate (digestione o uptake o rifiuto omologia) consuma una unit di `fragment.abundance`. Fragments a abundance 0 sono potati.
- **Decay**: `Phase.dilute/1` applica il dilution rate ai frammenti come per i virioni; ageing implicito via `decay_age` (preparato per refinement Fase 18 se servirà decay accelerato).
- **Audit log**: schema esistente; eventi `:transformation_event` saranno cablati in Fase 16 con il behaviour `HGT.Channel`.

##### Fase 14 — Tossicità, vincoli elementari, biomassa continua

- **Toxicity** (`Metabolism.toxicity_factor/2` + `Phenotype.detoxify_targets`): tre metaboliti tossici (`:oxygen`, `:h2s`, `:lactate`) hanno `(threshold, scale)` codificato. Per ogni metabolita non protetto, contributo = `1 - max(0, [met] - threshold)/scale`, clampato in `0..1`; i contributi compongono moltiplicativamente. Detoxify enzima generativo: gene con co-occorrenza `:substrate_binding(target=metabolita)` + `:catalytic_site(reaction_class: :reduction)` → `detoxify_targets ∋ metabolita` → bypass completo per quel target. Riproduce catalase (O₂), sulfide oxidoreductase (H₂S), lactate dehydrogenase (lattato) come traits emergenti.
- **Elemental constraints** (`Metabolism.elemental_factor/3`): per ogni elemento essenziale (P/N/Fe/S) tracciato (`@elemental_metabolites`), score = `min(1.0, uptake / floor)` con `floor = 0.001 × abundance`. Geometric mean → fattore globale. **Solo elementi che il fenotipo cerca attivamente (substrate_binding presente)** contano come vincolo; un genoma naïf non viene penalizzato per nutrienti che non cerca (la prototype non modella il riciclo cellulare). Fattore in `0.0..1.0` applicato solo alla biosintesi (biomass progress), non alla respirazione.
- **Continuous biomass** (`Lineage.biomass :: %{membrane, wall, dna}`): tre componenti in `0.0..1.0` (default 1.0 = founder intatto). Per-tick:
  - `progress`: scalato da `(atp_yield/50) × tox`. Capability per componente: membrana ∝ `n_transmembrane/5`, wall ∝ `n_transmembrane/5` (proxy PBP-like), DNA ∝ `repair_efficiency × elemental`.
  - `decay`: osmotic shock fuori band tolerance ±200 mOsm/L (decay membrana + wall); penuria elementare (decay DNA `(1-elemental) × 0.05`).
- **`Arkea.Sim.Biomass.lysis_probability/1`**: pressioni per componente sotto soglia (membrana 0.30, wall 0.40, DNA 0.25) compongono come max → probabilità di lisi in `0..1`.
- **Pipeline** (`Tick`): nuovo `step_biomass` dopo `step_metabolism` (riusa `state.uptake_by_lineage` per evitare ricomputo su pool già drenato); nuovo `step_lysis` dopo `step_environment` e prima di `step_pruning` (Bernoulli per lineage, riduce abundance per phase di `floor(count × p)`).
- **State**: aggiunto `BiotopeState.uptake_by_lineage` per condividere uptake da `step_metabolism` a `step_biomass`.
- Phase 17 userà la stessa biomass come substrato per `error_catastrophe` e SOS coupling.

#### Senescence & error-handling

- **Senescence/aging**: omesso (batteri immortali a questo livello di astrazione).

---

### Blocco 9 — Quorum sensing & signaling

Cell-cell signaling è meccanismo centrale dell'ecologia batterica. Integrato in v1 senza nuovi tipi di dominio.

#### Molecole di segnale come quarta classe ambientale del biotopo

| Classe | Ruolo |
|---|---|
| Metaboliti (13) | Substrati, accettori, nutrienti, prodotti |
| Xenobiotici | target_class + affinity + mode |
| **Molecole di segnale** | Comunicazione cell-cell, **nessun ruolo metabolico** |
| Particelle fagiche | Predazione, HGT trasduzionale |

I segnali hanno concentrazione, decadimento, dilution come i metaboliti, ma non vengono consumati da reazioni metaboliche.

#### Generatività: nessun catalogo

Ogni segnale ha una **signature** (vettore 4D codificato nei parameter codons della synthase). Mutazioni della synthase → segnali leggermente diversi (analogia: i diversi AHL nel mondo reale).

#### Geni del signaling (coperti dai domini esistenti del Blocco 7)

| Funzione | Composizione |
|---|---|
| Synthase di segnale | `[Substrate-binding(precursor)] [Catalytic(reaction_class=signal_synthesis, signature=X)]` |
| Recettore di segnale | `[Ligand sensor(target_signature=Y, threshold)] [DNA-binding] [Regulator output]` |
| Trasportatore di segnale | `[Substrate-binding(signature)] [Channel/pore] [Transmembrane]` |

Estensioni minime alla tassonomia del Blocco 7:
- Aggiunta di `signal_synthesis` alle reaction_class di `Catalytic site`
- Generalizzazione di `sensed_metabolite_id` a `sensed_chemical_id` (metaboliti **o** segnali)

#### Specificità segnale-recettore: matching continuo

```
binding_affinity = exp(− ||signal_signature − receptor_target||² / σ²)
```

Coevoluzione necessaria fra synthase e recettore. `σ` largo → eavesdropping; `σ` stretto → comunicazione privata. Divergenza comunicativa = meccanismo di speciazione naturale.

#### Comportamento di quorum (emergente)

Densità-dipendenza emerge da concentrazioni:
- Bassa densità → bassa produzione → segnale sotto soglia → programma OFF
- Alta densità → segnale sopra soglia → programma ON

Programmi tipici sotto controllo QS (decisione evolutiva o di design del giocatore): bacteriocine, biofilm formation, conjugazione, virulenza fagica, sporulation-like.

#### Migrazione, diluizione, decadimento

I segnali seguono le stesse regole dei metaboliti per dilution e migrazione fra biotopi. Decadimento spontaneo (parametro per signature) di default rapido — i segnali sono instabili.

#### Estensioni gratuite (emergenti dal framework)

- **Cross-talk inter-specie** (eavesdropping)
- **Quorum quenching**: idrolasi dei segnali altrui `[Substrate-binding(signature)] [Catalytic(hydrolysis)]` → distrugge QS dei competitor
- **Signaling fagico**: fagi che rilasciano segnali alla lisi (richiamo, avvertimento) — emergente se sopravvive evolutivamente

#### Cap operativi

- Massimo segnali distinti coesistenti per biotopo: ~50–100 (con merging se troppo simili) — parametro di tuning
- Dimensionalità signature: **4D** (default; supporta migliaia di dialetti)

---

### Blocco 10 — Topologia del network di biotopi

#### Archetipi (8) e progressione di sblocco

| # | Archetipo | Profilo | Tier sblocco |
|---|---|---|---|
| 1 | Lago oligotrofico ossigenato | mesofilo, pH neutro, basso glucosio, alto O₂, dilution media | **Tier 1** (starter) |
| 2 | Stagno eutrofico | mesofilo, neutro/acido, alto glucosio, O₂ stratificato, dilution bassa | **Tier 1** |
| 3 | Sedimento marino solforoso | anaerobico, alto SO₄²⁻, alta osmolarità, dilution bassissima | Tier 2 |
| 4 | Sorgente idrotermale | alta T (50–80°C), neutro, H₂+H₂S, anaerobico, dilution alta | Tier 3 |
| 5 | Drenaggio acido ferroso | basso pH (2–4), alto Fe²⁺/Fe³⁺, ossico, mesofilo | Tier 3 |
| 6 | Bog metanogeno | anaerobico, neutro, ricco di organico, freddo, dilution bassissima | Tier 2 |
| 7 | Suolo mesofilo eterogeneo | mesofilo, neutro, O₂ intermittente, dilution variabile | **Tier 1** |
| 8 | Estuario salino | mesofilo, alta osmolarità, gradiente di nutrienti, dilution alta | Tier 2 |

Eterogeneità intra-tipo: i parametri di base sono samplati attorno al centroide dell'archetipo. Criteri precisi di sblocco Tier 2/3 sono parametri di balancing (milestones evolutivi/temporali).

#### Topologia geometrica

- Graph **planare in 2D astratto** (mappa navigabile)
- Ogni biotopo: coordinate `(x, y)` + 3–5 vicini più prossimi
- **Long-range bridges**: ~1–2% degli archi → HGT inter-regionale, world connesso
- **Distribuzione geografica clusterizzata**: gli archetipi formano *zone* (regione idrotermale, regione paludosa, regione marina, ecc.). Ai bordi delle zone emergono biotopi intermedi → gradient ecologici naturali. I bridges connettono zone lontane raramente.

#### Archi: pesi e direzionalità

- `edge_weight` ∝ 1/distanza geografica
- `biotope_compatibility(A, B)` derivata da distanza nel profilo ambientale (T, pH, osmolarità) → un termofilo non attecchisce nel lago freddo
- **Direzionalità per archetipo**: simmetrica per stagni (laghi, bog), asimmetrica per fluenti (sorgenti=upstream, sedimenti=downstream)
- Lungo gli archi fluiscono (con scaling indipendente): lignaggi, fagi liberi, metaboliti, segnali

#### Allocazione e colonizzazione (multi-biotopo, cap 3)

Cap **3 biotopi per giocatore** = 1 home + fino a 2 colonizzati.

- Nuovo giocatore: sceglie archetipo Tier 1 → home biotope nella zona corrispondente
- Tier 2 e Tier 3 sbloccati per progressione
- **Meccanismo di colonizzazione** (appoggiato a migrazione del Blocco 5 + lignaggi del Blocco 4):
  1. Lignaggi del giocatore migrano nei biotopi vicini
  2. Se un lignaggio originato nell'home raggiunge **abbondanza ≥ soglia** in un biotopo **wild adiacente**, mantenuta per **≥ N tick**, il biotopo viene **reclamato**
  3. **First-to-threshold** in caso di competizione fra giocatori
  4. Solo biotopi wild sono colonizzabili (no claim su biotopi di altri giocatori — coerente con no-PvP-diretto)
- Espansione **emergente dall'evoluzione**: specialisti colonizzano la propria zona facilmente, generalisti più ampiamente ma con meno specializzazione. Per zone lontane: cross-tolleranza o bridge edge fortunato.

#### Biotopi abbandonati → wild *(default da confermare)*

Giocatore inattivo per ≥ T giorni → biotopi tornano **wild**:
- Popolazione persiste e continua a evolvere autonomamente
- Diritti di intervento revocati
- Biotopo di nuovo colonizzabile (anche dal giocatore originale se rientra)

**Risolve simultaneamente**: comportamento offline-state dell'Arkeon (Blocco 1) + churn/saturazione del network (i wild sono riserva di colonizzazione per i nuovi entrati).

#### Dimensionamento del world

| Risorsa | Quantità a regime |
|---|---|
| Biotopi naturali fissi (al lancio) | ~200–400 distribuiti sugli 8 archetipi e le zone |
| Biotopi giocatore home | 1 per giocatore attivo |
| Biotopi giocatore colonizzati | 0–2 per giocatore attivo |
| Biotopi wild (ex-giocatori inattivi) | crescente nel tempo, riserva di colonizzazione |

**Costo simulazione (stima)**: cap 1.000 lignaggi/biotopo × ~10⁴ biotopi totali a regime = 10⁷ lineage update per tick. Con tick ogni 5 min (vedi Blocco 11), ampiamente alla portata di un cluster moderato.

---

### Blocco 11 — Dimensionamento temporale

#### Unità fondamentale

- **1 tick = 5 minuti reali = 1 generazione di riferimento** (Arkeon ideale in condizioni perfette)
- I lignaggi reali variano: stressati possono richiedere 5–10 tick per dividersi; in fioritura 1 tick. La "generazione di riferimento" è solo unità di calibrazione cinetica.
- Scelta "gioco lento": privilegia profondità evolutiva e gameplay multi-sessione su feedback rapido.

#### Scala dei fenomeni evolutivi

| Tempo reale | Tick / generazioni | Osservabile dal giocatore |
|---|---|---|
| 5 min | 1 | Mutazioni isolate; risposta a stress acuto |
| 30 min | 6 | Drift visibile; prime varianti |
| 1 ora | 12 | Selezione direzionale visibile; effetti dei primi interventi |
| Sessione 2h | 24 | Eventi selettivi consolidati |
| Sessione 5h | 60 | Caso d'uso parziale (resistenze visibili) |
| 1 giorno | ~288 | Resistenza completa; co-evoluzione fagi-ospite avviata |
| 1 settimana | ~2.000 | Co-evoluzione completa; colonizzazione; speciazione iniziale |
| 1 mese | ~8.600 | Macro-evoluzione: cambio archetipo dominante in zona; speciazione comunicativa |

Il caso d'uso "resistenza antibiotica in 100 generazioni" del Blocco 5 richiede **~8 ore reali** → multi-sessione, coerente con MMO persistente.

#### Cinetica del tick (ordine di esecuzione)

Per ogni biotopo, per tick:
1. Bilancio metabolico (proto-FBA stazionario sui pool intracellulari + ambiente)
2. Espressione genica (σ-factor, riboswitch, regolatori valutati; livelli aggiornati)
3. Eventi cellulari (divisioni, morti, lisi, mutazioni → nuovi lignaggi)
4. HGT (coniugazione/trasformazione/trasduzione fra lignaggi del biotopo)
5. Eventi ambientali (decadimento metaboliti/segnali, dilution)
6. Pruning (lignaggi sotto soglia → estinti localmente, conservati nell'albero globale)

Tra tick, step coordinato globale:

7. Migrazione inter-biotopo (flussi sugli archi: lignaggi, fagi, metaboliti, segnali)

#### Server: walltime = simulation clock

- Server processa **esattamente 1 tick ogni 5 minuti wall-clock**
- **Tempo uniforme sempre** — niente fast-forward locale (coerente con MMO unitario)
- Tutti i giocatori condividono lo stesso "now"
- Restart del server: tick resta sincronizzato col wall-clock; al riavvio, riprende dal tick corrispondente all'ora attuale

**Parallelizzazione**: i biotopi sono indipendenti durante i passi 1–6 (intra-tick) → parallelizzabili massicciamente. Il passo 7 richiede sincronizzazione fra archi vicini → step coordinato globale.

#### Persistenza

- **Snapshot DB completo ogni 10 tick (50 minuti reali)**: stato di tutti i biotopi
- **Write-ahead log** intra-snapshot per ogni cambiamento (nuovo lignaggio, HGT, mutazione, intervento giocatore) → recovery completo in caso di crash
- **Albero filogenetico storico** scritto incrementalmente con decimazione periodica (Blocco 4)

#### Polling lato client

- Vista panoramica: polling server ogni 15–30 secondi
- Vista zoom su biotopo: polling 5–10 secondi
- Eventi notevoli (estinzioni dominanti, colonizzazioni, picchi QS, lisi massive fagiche) → push notifications asincrone

#### Costo computazionale (rivisto con tick da 5 min)

- 10⁴ biotopi × 1.000 lignaggi cap = 10⁷ lineage update per tick
- 1 tick = 300 sec di walltime disponibili → ~33k updates/sec richiesti
- A ~1 µs per lineage update (ottimistico) = 10s di CPU per tick → ampio margine
- Con realismo 10× peggiore, ancora 100s su 300s → **margine 3×**
- A regime con 10⁴ biotopi → **cluster di 2–5 nodi** sufficiente con shard per regione

#### Latenza percettiva degli interventi

Azioni del giocatore (antibiotico, nutrienti, inoculo, plasmide) → applicate al tick successivo. **Latenza max 5 minuti**. Effetti misurabili in 5–30 tick (25–150 minuti). Cadenza coerente con MMO strategico "lento".

---

### Blocco 12 — Confine micro/macroscala

#### Modello a fasi (phase-based)

Ogni biotopo è suddiviso in **2–3 fasi** (sotto-ambienti concettuali, non spazialmente discretizzati). La simulazione è autoritativa **a livello di fase**, non di posizione 2D.

#### Numero di fasi per archetipo (variabile)

| Archetipo | Fasi (autoritative) |
|---|---|
| Lago oligotrofico | `surface (ossica)`, `water_column (semi-mixed)` |
| Stagno eutrofico | `surface (ossica)`, `water_column`, `sediment (anossica)` |
| Sedimento marino | `interface (gradiente)`, `bulk_sediment (anossica)` |
| Sorgente idrotermale | `vent_core (caldo)`, `mixing_zone (gradient T)` |
| Drenaggio acido | `acid_water`, `mineral_surface (biofilm-friendly)` |
| Bog metanogeno | `surface_oxic`, `peat_core (anossico)` |
| Suolo eterogeneo | `aerated_pore`, `wet_clump (anossico)`, `soil_water` |
| Estuario salino | `freshwater_layer`, `mixing_zone`, `marine_layer` |

Ogni fase ha:
- Propri pool di metaboliti, segnali, fagi liberi
- Propri sottoinsiemi di lignaggi (ogni lignaggio ha abbondanza per fase, possibilmente zero in alcune)
- Propri parametri ambientali (T, pH, osmolarità) — possono divergere dal biotope-medio
- Propria dilution rate (es. surface alta, sediment bassissima)

#### Cosa è autoritativo vs visualizzazione

| Aspetto | Authoritative | Pure visualization |
|---|---|---|
| Abbondanze lignaggio per fase | ✅ | — |
| Concentrazioni metaboliti / segnali / fagi per fase | ✅ | — |
| Parametri ambientali per fase | ✅ | — |
| Posizioni 2D individuali dei "puntini" | — | ✅ derivate dalla distribuzione di fase |
| Forme di biofilm, colonie, animazioni | — | ✅ procedurali dalla densità di fase |
| Heatmap di concentrazione interpolata | — | ✅ dalla concentrazione di fase |
| Onde di lisi fagica | — | ✅ animazione dell'evento di lisi massiva |

#### Preferenza di fase: codificata nel genoma

Coperta dai domini del Blocco 7, senza nuovi tipi:
- **Adesione → biofilm/superficie**: `Surface tag(adhesin)` + `Structural fold(rigid)`
- **Motilità → water_column**: subunità flagellari (`Structural fold(filamentous)` + `Energy-coupling`)
- **Tolleranza O₂ → fasi ossiche**: presenza geni protettivi (catalasi-like)
- **Tolleranza stress fisico → fasi estreme**: thermal_stability/pH_optimum delle proteine

Distribuzione fra fasi calcolata per tick in funzione del fenotipo del lignaggio e dei parametri delle fasi. Emergente, non scelta del giocatore.

#### Migrazione fase-a-fase

La migrazione (Blocco 5) fluisce **a livello di fase**: cellula in `surface` di A migra preferenzialmente verso `surface` di B. `biotope_compatibility` generalizzata a `phase_compatibility(A.phase_x, B.phase_y)`.

Conseguenza: lignaggio "biofilm-ist" si sposta poco (ancorato), "planctonico" diffonde rapidamente. Coerente con biologia reale.

#### Interventi del giocatore

Granularità: **biotope-wide oppure phase-level**, mai coordinata 2D precisa.

Esempi:
- "Antibiotico nel sediment del mio stagno" — phase-level
- "Inoculo plasmide in surface" — phase-level
- "Mixing event" — **azione strategica disponibile**: rimescola temporaneamente le fasi (omogeneizza concentrazioni e popolazioni), con costo metabolico/risorsa per il giocatore. Permette manovre tipo "espongo gli anaerobi all'O₂" o "diluisco un metabolita tossico in tutto il volume"
- "Cliccare un puntino specifico nella vista 2D" — **non disponibile** (la posizione non è autoritativa)

#### Visualizzazione 2D: rendering procedurale

- Le abbondanze di fase determinano regioni dello schermo (es. fascia superiore = surface, fascia inferiore = sediment)
- I "puntini" rappresentano frazioni di lignaggi, posizionati casualmente entro la regione della loro fase
- Densità rendering ∝ N del lignaggio (con clustering procedurale per simulare colonie/biofilm)
- Colorazione per cluster fenotipico (Blocco 4)
- Eventi (lisi massiva, sweep selettivo) come effetti procedurali animati sopra il rendering base

Il rendering è **derivato** dallo stato autoritativo, non lo influenza.

#### Costo aggiuntivo

10⁴ biotopi × 2.5 fasi medie × 1k lignaggi = ~2.5 × 10⁷ lineage-phase update per tick. Con 300s walltime, ampio margine (≥ 3×) rispetto al budget del Blocco 11.

---

### Blocco 13 — Anti-griefing residuo

#### Vettori identificati

Nonostante la scelta no-PvP-diretto (Blocco 3), restano vie indirette per danneggiare altri giocatori:

| # | Vettore | Meccanismo |
|---|---|---|
| 1 | Plasmid burden flooding | Plasmide costoso/non-utile rilasciato → migrazione + HGT → indebolisce ricettori |
| 2 | Hyper-virulent phage release | Fago iperaggressivo → particelle libere migrano (Poisson) → infettano altrui |
| 3 | Bacteriocin shotgun | Bacteriocine evolute per surface tag comuni → spread via migrazione |
| 4 | Signal spam / quorum quenching | Flooding segnali o idrolasi anti-segnale → disrompe QS altrui |
| 5 | Resource depletion in wild colonizzato | Iperconsumo metaboliti → carenza per migranti altrui |
| 6 | Colonization grabbing | Colonizzazione rapida dei wild adiacenti per murare |
| 7 | Abandoned-biotope seeding | Pre-evoluzione "trojan" + abbandono → wild nocivo permanente |
| 8 | Multi-account coordination | Più account coordinati per amplificare attacchi |

#### Mitigazioni già coperte dal design

La maggior parte dei vettori è auto-neutralizzata dai blocchi precedenti:

- **Dilution + decadimento** (Blocchi 3, 8, 9, 10): tutti gli effetti decadono con la distanza dal punto di rilascio. Attacchi a giocatori in zone lontane impossibili.
- **Costo del plasmide** (Blocco 5): burden plasmid selezionato contro → estinto in poche generazioni se non vantaggioso. **Vettore #1 auto-neutralizzato**.
- **Co-evoluzione fagi-ospite** (Blocco 8): difese RM e loss-of-receptor evolvono naturalmente. Niente "fago invincibile" sostenibile. **Vettore #2 si esaurisce**.
- **Bacteriocine target-match** (Blocco 8): efficaci solo contro Surface tag specifici → diversificazione delle superfici (Blocco 7) le rende inefficaci a tappeto. **Vettore #3 limitato**.
- **Tempo reale come bottleneck** (Blocco 11): tutti gli interventi richiedono wall-clock. Costo umano del griefing alto.
- **Cap colonizzazione 2** (Blocco 10): scala di murata limitata.
- **Distanza nel network** (Blocco 10): zone clusterizzate + rare bridge edges → attacchi zone-cross devono attraversare biotopi intermedi.

#### Mitigazioni residue esplicite

**A. Cooldown sulla colonizzazione**
Dopo una colonizzazione riuscita: **cooldown 24h reali** prima della successiva. Limita "grabbing" senza penalizzare l'espansione organica (1–2 colonizzazioni/settimana è scope ragionevole). *Mitiga vettore #6.*

**B. Audit log degli elementi mobili (origin tracking)**
Ogni elemento mobile (plasmide, profago) carica un metadato invisibile in-game con `origin_lineage_id` e `origin_biotope_id`. Permette ai sistemi ops di rilevare patterns abusivi (es. "fago X originato da player Y compare in N biotopi attaccati a player Z entro 1 settimana"). *Mitiga vettori #1, #2, #7.*

**C. Sostenibilità del claim**
Oltre alla soglia di abbondanza (Blocco 10): il claim regge solo se la popolazione del lignaggio cresce o resta stabile per **N tick post-claim**. Se collassa → claim revocato, biotopo torna wild. Penalizza grab opportunistici, premia adattamento reale. *Mitiga vettore #6.*

**D. Intervention budget per biotopo**
Cap rigenerativo sugli interventi del giocatore: es. **1 intervento maggiore ogni 30 minuti reali per biotopo**. Non punitivo nel gioco normale (gli interventi sono comunque centellinati), chiude abuso automatizzato. *Mitiga vettori #1, #2, #4 in modalità flooding.*

#### "No action needed" documentati

**E. Pre-evoluzione + abbandono (vettore #7)**: i wild seguono normale ecologia. Selezione naturale erode tratti puramente nocivi senza beneficio per il portatore (li penalizza per costo metabolico/genomico). **Mitigazione strutturale**: il design ecologico previene la persistenza di tratti "nocivi-senza-beneficio". Nessuna azione esplicita necessaria.

**F. Multi-account / bot (vettore #8)**: tema **operativo** (registrazione, IP detection, behavioral analysis), non di design ecologico. Va affrontato nel piano operativo ma fuori scope per il modello biologico.

---

### Blocco 14 — Stack tecnologico

#### Decisione di runtime: BEAM/Elixir

**Sim core + orchestrazione**: Elixir + OTP. Le forze di BEAM si allineano alle esigenze di Arkea:
- Fault tolerance via supervision trees ("let it crash + recover") per sim 24/7
- Cluster distribuito out-of-the-box via `libcluster` + `:net_kernel`
- Process model leggero (~3 KB/processo): un GenServer per biotopo è naturale e scala
- Phoenix Channels + Presence + PubSub per push real-time al client
- Hot code reload per deploy senza downtime su MMO persistente

**Debolezza nota**: performance numerica pura (10⁻100× più lenta di Rust). **Mitigazione futura**: estrarre i kernel hot (proto-FBA, calcolo parametri dai codoni, kinetic update batch) come **NIF Rust** via Rustler/Zigler quando la profilazione lo giustifica. **Per il prototipo: Elixir puro**, ottimizzare solo dopo aver profilato colli di bottiglia reali.

#### Stack completo

| Layer | Scelta |
|---|---|
| Sim core + orchestrazione | **Elixir + OTP** |
| Web framework | **Phoenix** |
| Server-rendered UI (chrome, dashboard, controlli, vista filogenetica) | **Phoenix LiveView** |
| Real-time data al client | **Phoenix Channels + PubSub + Presence** |
| 2D WebGL nel browser | **TypeScript + PixiJS** (montato in un LiveView Hook) |
| Coordinamento Hook ↔ LiveView | `phx-hook`, `pushEvent`, eventi push del server |
| DB | **PostgreSQL** via Ecto |
| Hot path numerici (rinviato) | NIF Rust via Rustler |
| Cluster multi-nodo (rinviato) | libcluster + Horde/Swarm |
| Background jobs (snapshot, decimazione) | Oban |
| Telemetria | `:telemetry` + LiveDashboard → Prometheus exporter (produzione) |
| Reverse proxy + TLS | Caddy |
| Deploy | `mix release` + systemd (Docker opzionale) |
| Test | ExUnit + StreamData (property-based per invarianti evolutivi) |
| CI | GitHub Actions |

#### Architettura process-level (Elixir)

```
Application Supervisor
├── WorldClock (GenServer, batte tick ogni 5 min)
├── Biotope.Supervisor (DynamicSupervisor)
│   └── Biotope.Server × N (uno per biotopo attivo)
│       state: phases, lignaggi (con delta_genome), metabolites, signals, phages
│       handle_tick: bilancio metabolico → espressione → eventi cellulari → HGT → ambiente → pruning
├── Migration.Coordinator (orchestra step inter-biotopo dopo ogni tick)
├── Player.Supervisor (DynamicSupervisor)
│   └── Player.Session × M
├── Phoenix.PubSub (broadcast eventi al client)
├── Persistence.Snapshot (Oban worker, ogni 10 tick)
└── Persistence.WAL (changeset stream → Ecto)
```

Biotope.Server indipendenti → parallelizzazione nativa intra-tick. Migration.Coordinator gestisce il passo 7 (migrazione inter-biotopo del Blocco 11) come step coordinato globale.

#### Modello UI ibrido

- **Phoenix LiveView ~80% della UI**: dashboard, log eventi, controlli intervento, vista filogenetica
- **PixiJS embedded in un LV Hook**: sola vista 2D WebGL del biotopo (rendering procedurale del Blocco 12)
- **Phoenix Channels** per data stream a bassa latenza verso il componente WebGL

Sfrutta le forze di entrambi: server-rendered semplice dove possibile, JS+WebGL dove serve.

#### Genoma e persistenza in Elixir

- **Rappresentazione in memoria**: liste di codoni (integer/atom), domini come struct, delta come mappa di mutazioni rispetto a un genoma di riferimento per clade
- **Serializzazione DB**: `:erlang.term_to_binary/1` per dump compatto; jsonb opzionale per analytics
- **Schema Ecto base**: `biotopes`, `phases`, `lignaggi`, `mobile_elements` (con audit log Blocco 13), `phylogenetic_history`, `interventions_log`, `players`
- **TimescaleDB** rinviato a fase post-prototipo

#### Hosting prototipo

**VPS DigitalOcean 1 CPU / 1 GB RAM** dell'utente.

Footprint stimato:
- BEAM VM ~50 MB
- 5–10 biotopi × ~100 KB stato ≈ 1 MB
- Postgres minimal (shared_buffers 128 MB) ~200 MB
- Phoenix + LiveView ~50 MB
- OS ~150 MB
- **Totale ~500 MB** → margine confortevole

CPU: con tick ogni 5 min e poche biotopi, 1 core abbondante (BEAM I/O-friendly, concorrenza efficiente sul singolo core).

#### Scope del prototipo (validazione end-to-end)

| Risorsa | Prototipo | Produzione (target lontano) |
|---|---|---|
| Biotopi simulati | **5–10** | ~10⁴ |
| Cap lignaggi/biotopo | **100** | 1.000 |
| Cap segnali/biotopo | 10 | 50–100 |
| Player accounts | **1–4** | migliaia |
| Tick rate | 5 min | 5 min |
| DB | Postgres sullo stesso VPS | DB dedicato/cluster |
| Frontend | Servito da Phoenix sullo stesso VPS | CDN + nodo dedicato |

**Obiettivo prototipo**: validare il design integrale end-to-end. Da un Arkeon seed, in qualche ora di tempo reale (qualche dozzina di tick) devono emergere mutazione, selezione, almeno un evento HGT, almeno un evento di lisi. È lo stress test implementativo del design.

---

### Blocco 15 — Caso d'uso integrale (stress test "a tavolino")

Walk-through di una campagna multi-settimana che attraversa tutti i 14 blocchi precedenti in uno scenario continuo. Scopo: validare la coerenza interna prima dell'implementazione.

#### Setup

- **Anna** (account Tier 1): home `STAGNO-A` (archetipo Stagno eutrofico) in zona paludosa. Arkeon Gram-positive, parete spessa, heterotrofo aerobico facoltativo + fermentatore.
- **Bartolomeo** (account Tier 2): home `ESTUARIO-B` (archetipo Estuario salino) in zona costiera. Arkeon alofilo Gram-negative.
- **Topologia**: zone connesse da un bridge edge raro (~5 hop di distanza grafo).
- **Tempo**: 30 giorni reali ≈ 8.640 tick ≈ 8.600 generazioni.

#### Settimana 1 — Insediamento e biofilm emergente

- Anna inocula 10 cellule in STAGNO-A; crescita esponenziale a 10⁴; distribuzione fase emergente (70% water_column / 25% surface / 5% sediment)
- Drift puntiforme produce 30–40 lignaggi figli; selezione lieve; pruning attivo
- Anna alimenta extra-glucosio in `surface` (intervention budget −1) → soglia QS attivata → biofilm emergente in surface; distribuzione si sposta a 50/35/15

[Blocchi: 3, 4, 5, 6, 7, 8, 9, 12, 13]

#### Settimana 2 — Stress, mutator, resistenza

- Anna introduce β-lattam-like (0.5× MIC) in water_column; lisi massiva 10⁶ → 10⁴; surface biofilm e sediment protetti
- σ-stress attiva DinB-like (µ × 50); mutazione puntiforme su PBP-like sposta Km → resistenza parziale fissata
- Dose alzata a 1× MIC; duplicazione di un trasportatore di efflusso + neofunzionalizzazione → MIC 4×; rimossa, polimorfismo bilanciato per costo

[Blocchi: 4, 5, 7, 8, 12]

#### Settimana 3 — Profago, difese, prima colonizzazione

- Fago libero arriva da wild (Poisson); lisi diretta + lisogenesi
- Difese evolvono: loss-of-receptor (con costo) + Restriction-Modification (idrolasi DNA + metilasi tandem da traslocazione)
- Anna colonizza LAGO-W (sub-lineage planctonico raggiunge 30% per >100 tick → claim, cooldown 24h scatta)
- Anna induce separazione comunicativa nel LAGO-W: synthase deriva → segnale fuori σ del recettore di STAGNO-A → speciazione comunicativa parziale

[Blocchi: 3, 5, 7, 8, 9, 10, 13]

#### Settimana 4 — L'attacco indiretto

- Bartolomeo rilascia plasmide burden non-coniugativo da ESTUARIO-B (audit log: origin_lineage_id, origin_biotope_id)
- Costo del plasmide → diffusione locale si stabilizza a ~5%
- Migrazione lungo bridge edge: dilution + selezione attraverso 5 hop intermedi → frazione < 0.1% all'arrivo nella zona di Anna
- In LAGO-W solo trasformazione passiva (non-coniugativo) → < 0.05%
- Selezione contro completa l'eliminazione in 500 generazioni; nessun danno per Anna; principio E ("no action needed") confermato

[Blocchi: 5, 8, 10, 13]

#### Settimana 5 — Macro-evoluzione

- STAGNO-A: lignaggio fondatore dominante; foresta a 2.000 lignaggi (cap 1.000 + pruning, decimazione albero storico)
- LAGO-W: chimera per traslocazione fonde `Substrate-binding(Fe³⁺)` + `Catalytic(reduction)` → ferri-reduttasi nuova → nicchia in fasi sub-ossiche; **innovazione composta**
- I due ceppi geneticamente e comunicativamente distinti, HGT-linkati per migrazione

[Blocchi: 4, 7, 9]

#### Copertura dei 14 blocchi

| Blocco | Esercitato |
|---|---|
| 1. Architettura | ✅ MMO, persistente, ruoli Designer+Allevatore |
| 2. Modello biologico | ✅ operoni, σ-factor, riboswitch, riarrangiamenti |
| 3. Ambiente | ✅ eventi sistemici + interventi phase-level, no PvP diretto |
| 4. Popolazione | ✅ delta encoding, cap 1k, pruning, albero filogenetico |
| 5. Motore biologico | ✅ xenobiotici, µ modulabile, coniugazione gene-encoded, costo plasmide, migrazione |
| 6. Inventario metabolico | ⚠️ parziale (glucosio, O₂, Fe³⁺ usati; H₂/CH₄/SO₄²⁻/H₂S/NH₃/NO₃⁻ non esercitati) |
| 7. Sistema generativo | ✅ tutti tre i regimi: drift, salto categorico, innovazione composta |
| 8. Pressioni selettive | ✅ stress, lisi divisione, lisi fagica, dilution, competizione |
| 9. Quorum sensing | ✅ emergenza, biofilm-induction, speciazione comunicativa |
| 10. Topologia network | ✅ archetipi multipli, zone, bridge, colonizzazione |
| 11. Tempo | ✅ scale rispettate (settimane = 10³ gen) |
| 12. Micro/macroscala | ✅ 3 fasi, distribuzione emergente, intervento phase-level |
| 13. Anti-griefing | ✅ cooldown, intervention budget, audit log, principio E |
| 14. Stack | ✅ implicito: ogni meccanismo mappa a GenServer + Ecto |

**Coperture parziali da rinforzare in casi d'uso futuri** (non lacune di design):
- Chemiolitotrofia (termofilo idrogenotrofo in sorgente idrotermale → H₂/H₂S/CH₄)
- Tossicità di metaboliti naturali accumulati (H₂S, lattato)
- Bacteriocine
- Co-evoluzione fagi-ospite a lungo termine (10⁴+ generazioni)

#### Buchi nel design emersi

A differenza del primo caso d'uso (8 gap), il walk-through integrale **non rivela inconsistenze gravi**. Tre considerazioni minori, di balancing/implementazione:

1. **Intervention budget vs sessioni esplorative**: 1 azione/30 min può essere stretto per chi sperimenta intensivamente. Possibile pool accumulabile fino a N azioni stoccate. Decisione di balancing.
2. **Distribuzione fase per neonati**: lignaggio appena nato eredita la distribuzione del parent (snapshot all'istante di nascita), ricomputa al tick successivo. Da chiarire in implementation.
3. **Cap 1.000 in wild appena colonizzato**: i lignaggi wild residenti restano e seguono le stesse regole. Wildness = flag di non-controllo, niente trattamento meccanico differente. Da confermare in implementation.

#### Conclusione

Design **internamente coerente**. I 14 blocchi si integrano in uno scenario continuo che produce fenomeni biologicamente plausibili: resistenza, biofilm, profagi, RM, colonizzazione, speciazione, innovazione composta, fallimento di un attacco indiretto. I 3 punti rimanenti sono raffinamenti, non lacune. **Pronto per la fase implementativa.**

---

## Verifica del design

Questo è un documento di design, non un piano di codice. La sua verifica avviene per **iterazione di scope** prima dell'implementazione:

- [x] Tutti i meccanismi biologici scelti (operoni, σ-factor, riboswitch, riarrangiamenti, HGT) sono coerenti tra loro e con la granularità B+C
- [x] Il modello di popolazione (lignaggi con delta encoding) supporta tutti i meccanismi del Blocco 5
- [x] Un caso d'uso end-to-end (resistenza a β-lattam in 100 generazioni) percorre coerentemente tutti i meccanismi scelti
- [x] **Caso d'uso integrale "Cronache di un estuario contestato"** (Blocco 15) attraversa coerentemente tutti i 14 blocchi senza rivelare inconsistenze gravi
- [x] Il modello è abbastanza astratto da girare 24/7 server-side con N giocatori (stima Blocco 11: cluster 2–5 nodi a regime, margine 3×)
- [x] La rete di biotopi (macroscala) supporta nicchie ecologiche sufficienti per giustificare la competizione fra giocatori (8 archetipi su 3 tier, zone clusterizzate, colonizzazione multi-biotopo emergente da evoluzione)
- [x] La microscala 2D WebGL è chiaramente delimitata (modello a fasi: autoritativo a livello di fase 2–3 per archetipo; rendering 2D procedurale e derivato; interventi giocatore phase-level, mai coordinata 2D)
- [x] Esiste un percorso plausibile di onboarding (biotopi wild come riserva di colonizzazione per i nuovi)
- [x] Comportamento Arkeon offline risolto (biotopi → wild dopo inattività; popolazione persiste, controllo perso)
- [x] Inventario metabolico definito (13 specie chimiche, cicli C/N/S/Fe chiusi, ≥10 nicchie supportate)
- [x] Sistema generativo dei domini funzionali specificato concretamente (11 tipi di dominio, alfabeto 20 simboli, parametri come somma pesata, regulatory block con binding sites multipli)

Solo dopo aver chiuso questi punti ha senso passare a un piano implementativo (scelta dello stack, prototipazione del simulatore biologico, prototipazione UI WebGL, scelta DB per stato persistente).

---

## Prossimi passi

1. Definire l'**inventario metabolico** (8-15 specie chimiche di base) ancorato a microbiologia reale
2. Definire le **pressioni selettive** (meccanismi di morte, lisi, starvation, predazione fagica, antibiosi, competizione, dilution)
3. Definire la **topologia del network di biotopi** (numero, connessioni, regole di flusso, eterogeneità)
4. Chiarire **cosa della microscala 2D è autoritativo** vs puramente di visualizzazione
5. Affrontare le **tensioni aperte del Blocco 1** (offline state, onboarding, costi infrastrutturali)
6. **Caso d'uso a tavolino**: tracciare l'evoluzione di una resistenza antibiotica in ~100 generazioni per stress-testare la coerenza dei meccanismi scelti
7. Solo dopo: scelta tecnologica e piano implementativo (stack web/WebGL, motore di simulazione, DB di stato persistente, infrastruttura server 24/7)
