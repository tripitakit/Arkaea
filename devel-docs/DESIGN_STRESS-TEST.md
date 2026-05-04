> 🇮🇹 Italiano (questa pagina) · [🇬🇧 English](DESIGN_STRESS-TEST.en.md)

# Arkea — Stress test del design "a tavolino"

**Riferimenti**: [DESIGN.md](DESIGN.md) (Blocchi 1–14)
**Data del walk-through**: 2026-04-26
**Scopo**: validare la coerenza interna del design integrale prima della fase implementativa, attraversando in uno scenario continuo tutti i 14 blocchi del documento di design.

---

## 1. Metodo

Walk-through narrativo di una **campagna multi-settimana** con due giocatori in zone diverse del network di biotopi. Lo scenario è progettato per esercitare contemporaneamente meccanismi di:

- progettazione e adattamento di un Arkeon (Blocchi 1, 2, 7)
- evoluzione (drift, duplicazioni, riarrangiamenti, innovazioni composte) (Blocchi 5, 7)
- pressioni selettive multiple (antibiotico, fagi, competizione) (Blocchi 5, 8)
- comunicazione cell-cell e densità-dipendenza (Blocco 9)
- distribuzione di fase emergente (Blocco 12)
- topologia di mondo, colonizzazione e migrazione (Blocchi 3, 10)
- difese anti-griefing (Blocco 13)
- mantenimento dei costi simulativi entro i budget temporali (Blocchi 4, 11, 14)

Ad ogni evento sono annotati i blocchi del design effettivamente esercitati, in modo da costruire una **matrice di copertura** alla fine del walk-through.

---

## 2. Setup

### 2.1 Cast dei giocatori

**Anna** — account starter (Tier 1). Sceglie archetipo **Stagno eutrofico**. Riceve home biotope `STAGNO-A` nella zona paludosa della mappa. Configura un Arkeon seed: Gram-positive, parete spessa, repertoire metabolico baseline (heterotrofo aerobico facoltativo + fermentatore in carenza di O₂).

**Bartolomeo** — account avanzato (ha sbloccato Tier 2). Sceglie **Estuario salino** in una zona costiera della mappa. Riceve home biotope `ESTUARIO-B`. Configura un Arkeon alofilo, Gram-negative con porine selettive.

### 2.2 Topologia rilevante

`STAGNO-A` è in zona paludosa; `ESTUARIO-B` in zona costiera. Le due zone sono connesse da **un bridge edge raro** (~1% degli archi del grafo). Distanza ~5 hop. Tra le due zone esistono biotopi intermedi wild di archetipi misti.

### 2.3 Tempo del mondo

Il mondo gira 24/7. La narrazione segue **30 giorni di tempo reale ≈ 8.640 tick ≈ 8.600 generazioni di riferimento** (Blocco 11: 1 tick = 5 minuti = 1 generazione ideale). Anna e Bartolomeo accedono in sessioni di 1–2 ore, alternati.

[Blocchi: 1, 4, 7, 10, 11]

---

## 3. Walk-through narrativo

### 3.1 Settimana 1 — Insediamento e biofilm emergente

**Giorno 1, t=0**. Anna inocula 10 cellule del seed Arkeon in `STAGNO-A`. Tre fasi del biotopo: `surface` (ossica, illuminata), `water_column` (semi-mixed, eterotrofa), `sediment` (anossica, ricca di organico). [Blocco 12]

**Tick 1–50** (~4 ore reali). Le 10 cellule si dividono. Il fenotipo "heterotrofo facoltativo" del seed è ben adattato a `water_column`. Crescita esponenziale → 100 → 10⁴ cellule del lignaggio root. La **distribuzione di fase emerge dal genoma**: 70% in water_column, 25% in surface, 5% in sediment (i pochi che riescono a tollerare anossia parziale). [Blocchi: 4, 6, 12]

**Tick 50–300** (giorni 1–3). Mutazione baseline. Compaiono i primi 30–40 lignaggi figli con drift puntiforme su parametri (Km di trasportatori, kcat di enzimi). Selezione lieve: lignaggi con miglior affinità per glucosio e migliore `wall_integrity` sono leggermente avvantaggiati. **Pruning attivo**: lignaggi con N<1 estinti localmente, conservati nell'albero filogenetico globale. [Blocchi: 4, 5, 7, 8]

**Giorno 4–7, tick 300–2000**. Densità nel water_column raggiunge 10⁶ cellule. Anna decide di provare a far emergere un biofilm. Strategia: usa un intervento "introdurre un metabolita induttore" (alimenta extra-glucosio in `surface`). Costo: **1 azione di intervention budget consumata** (Blocco 13). Effetto al tick successivo (latenza 5 min reale). [Blocchi: 3, 13]

L'alta densità in surface attiva il **QS emergente** del seed: la synthase di un segnale `signature ≈ (0.3, 0.7, 0.1, 0.4)` (4D) raggiunge soglia di attivazione del recettore. Il programma sotto controllo QS attiva i geni di adesione (`Surface tag(adhesin)` + `Structural fold(rigid)`) → comparsa di un **biofilm in surface**. Distribuzione di fase si sposta: 50% surface (biofilm), 35% water_column, 15% sediment. [Blocchi: 7, 9, 12]

### 3.2 Settimana 2 — Stress, mutator, resistenza

**Giorno 8**. Anna introduce un **β-lattam-like** in `water_column` (intervento phase-level, budget −1). Concentrazione 0.5× MIC nel water_column (non in surface né sediment). [Blocchi: 5, 13]

**Tick 2000–2050** (~4 ore reali, ~50 generazioni). Lisi massiva nel water_column durante divisione (parete compromessa). Popolazione del water_column: 10⁶ → 10⁴. Le cellule in surface (biofilm) sono protette: il farmaco non penetra nel biofilm; quelle in sediment sono protette dalla scarsa diffusione. [Blocchi: 5, 8, 12]

**Tick 2050–2200**. σ-factor di stress si attiva nei sopravvissuti del water_column. Espressione di **DinB-like (polimerasi error-prone)** sale → tasso di mutazione µ × 50 nei sopravvissuti. In ~50 generazioni una mutazione puntiforme nel parameter codon di una **PBP-like** sposta il Km del β-lattam da 0.1 µM a 1 µM (ridotta affinità → resistenza parziale). Mutazione fissata per selezione. [Blocchi: 5, 7]

**Tick 2200–2400**. Anna alza la dose a 1× MIC (budget −1). Nuovo ciclo. In 30 generazioni una **duplicazione** di un trasportatore di efflusso pre-esistente compare in un lignaggio. La copia, sotto pressione, accumula mutazioni puntiformi che ne allargano la specificità → espelle il β-lattam. Fitness ↑ → fissazione. **Tre regimi evolutivi del Blocco 7 esercitati**: drift parametrico (Km PBP), duplicazione, neofunzionalizzazione. MIC apparente è 4×. [Blocchi: 4, 5, 7]

Anna salva il caso e rimuove il farmaco. Le mutazioni resistenti sono lievemente costose (la PBP modificata è meno efficiente nella sintesi del peptidoglicano) → **polimorfismo bilanciato** si stabilizza.

### 3.3 Settimana 3 — Profago, difese, prima colonizzazione

**Giorno 14**. Evento sistemico (Blocco 3): un fago libero arriva in `STAGNO-A` da un biotopo wild adiacente (evento Poisson della migrazione, Blocco 5). Il fago ha un Surface tag compatibile con un recettore di alcuni lignaggi di Anna. **Lisi diretta** in alcune cellule del water_column. **Lisogenesi** in altre: il profago si integra nel cromosoma e il repressore lisogenico tiene il programma litico spento. [Blocchi: 3, 5, 8]

**Tick 2700–3000**. Lignaggi con il profago integrato sono frequenti (fenotipo simile al wild type, costo modesto del profago). **Difese contro fagi liberi residui evolvono**:

- Alcuni lignaggi mutano il `Surface tag` del recettore (**loss-of-receptor**) → fitness ↓ rispetto al wild perché il recettore aveva anche una funzione (era un trasportatore di un metabolita raro), ma protezione fagica ↑.
- Altri lignaggi guadagnano una **Restriction-Modification system** via traslocazione + sistema generativo: due geni in tandem (un'idrolasi di DNA + una metilasi della stessa specificità) compaiono per fusione/scissione di geni esistenti. La RM taglia il DNA fagico estraneo, protegge il proprio.

[Blocchi: 5, 7, 8]

**Tick 3000–3500**. Anna decide di **espandere**. Un sotto-lignaggio (varietà planctonica con preferenza water_column) diffonde naturalmente verso biotopi vicini. Raggiunge **30% della popolazione** del wild biotope `LAGO-W` adiacente, mantenuto per 100 tick. **Claim attivato** (Blocco 10): `LAGO-W` diventa il primo biotopo colonizzato di Anna. **Cooldown 24h reali** scatta (Blocco 13). [Blocchi: 5, 10, 13]

**Tick 3500–4000**. Anna ora controlla 2 biotopi (`STAGNO-A` home + `LAGO-W` colonizzato). Esegue un esperimento di **separazione comunicativa**: nel LAGO-W introduce una pressione artificiale (variazione di nutrienti) che favorisce lignaggi con synthase di segnale mutata. In 200 generazioni il signal signature nel LAGO-W deriva a `(0.5, 0.6, 0.3, 0.2)`. Il recettore del lignaggio principale di STAGNO-A non riconosce più questo segnale (drift > σ del recettore). **Speciazione comunicativa parziale**: i due ceppi sono ancora geneticamente vicini ma non si "parlano" più. [Blocchi: 7, 9]

### 3.4 Settimana 4 — L'attacco indiretto

**Giorno 22**. Bartolomeo, in `ESTUARIO-B`, ha un Arkeon ben evoluto. Per pure malizia, decide di **rilasciare un plasmide burden**: un plasmide non-coniugativo con un grosso operone di geni costosi che non dà alcun beneficio. Lo introduce nell'`ESTUARIO-B` via intervento (1 intervention budget). **Origin tracking** attivo (Blocco 13): `origin_lineage_id=B-7402`, `origin_biotope_id=ESTUARIO-B`. [Blocchi: 5, 13]

**Tick 4400–4800**. Nel proprio biotopo, il plasmide si diffonde via trasformazione passiva e qualche evento di coniugazione (cellule che avevano già pili). Ma il **costo del plasmide** (Blocco 5: replicazione + burden trascrizionale) è elevato → i lignaggi portatori sono leggermente meno fit. Selezione contro entro l'`ESTUARIO-B` stesso: il plasmide diffonde lentamente, raggiunge ~5% delle cellule, poi si stabilizza. [Blocchi: 5, 8]

**Tick 4800–5500**. Migrazione dall'`ESTUARIO-B` lungo gli archi. Il bridge edge raro che connette zona costiera a zona paludosa porta alcune cellule portatrici nel network di Anna, attraverso 5 biotopi intermedi wild. **Ad ogni hop la frazione di portatori scende** (dilution + selezione contro). Quando arriva a un biotopo wild adiacente al `LAGO-W` di Anna, la frazione di portatori è < 0.1%.

Un'ulteriore migrazione porta qualche cellula portatrice nel `LAGO-W`. Coniugazione possibile? Solo se il plasmide ha geni `pili_like + relaxase_like + oriT_like` → ma questo plasmide è non-coniugativo. Quindi diffonde solo per trasformazione di DNA libero (raro). Si stabilizza a < 0.05% delle cellule del LAGO-W. [Blocchi: 5, 8, 10]

**Tick 5500–6000**. Selezione contro fa il resto: in 500 generazioni il plasmide è eliminato dal LAGO-W (la rara cellula portatrice perde N più velocemente delle non-portatrici). **Anna nemmeno se ne accorge. Nessun danno reale.** Anti-griefing principio E confermato (no action needed).

L'audit log B (Blocco 13) registra però il plasmide con `origin_biotope_id=ESTUARIO-B` apparso in 5 biotopi del network paludoso entro 1 settimana. Il sistema ops, qualora monitorasse, avrebbe i dati per identificare il pattern (anche se in questo caso non c'è stato danno). [Blocchi: 5, 13]

### 3.5 Settimana 5 — Macro-evoluzione

**Giorno 30+**, ~8.500 generazioni dall'inizio. Tornando dopo qualche giorno offline, Anna trova:

- Nel `STAGNO-A`, il lignaggio fondatore è ancora dominante ma con ~2.000 lignaggi nella foresta (cap=1.000 raggiunto, **pruning attivo dei più rari**, decimazione dell'albero storico).
- Nel `LAGO-W`, una **chimera è emersa via traslocazione**: un gene fonde un dominio `Substrate-binding(Fe³⁺)` con un dominio `Catalytic(reduction)` esistente — risultato: una **ferri-reduttasi nuova**, qualitativamente diversa da qualsiasi cosa avesse prima. Apre una nicchia in fasi sub-ossiche del LAGO-W (un po' di Fe³⁺ presente per dilavamento minerali). **Innovazione composta** del Blocco 7.
- Il segnale del LAGO-W è ulteriormente derivato da quello dell'STAGNO-A: ora i due ceppi sono **comunicativamente distinti** anche se HGT-linkati per migrazione.

[Blocchi: 4, 7, 9]

---

## 4. Risultato

### 4.1 Matrice di copertura dei blocchi

| Blocco | Esercitato | Note |
|---|---|---|
| 1. Architettura | ✅ | MMO con due giocatori, mondo persistente, ruoli Designer+Allevatore |
| 2. Modello biologico | ✅ | operoni (QS), σ-factor (stress), riboswitch (regolazione), riarrangiamenti (duplicazione + traslocazione) |
| 3. Ambiente | ✅ | eventi sistemici (fago, migrazione), interventi giocatore phase-level, no PvP diretto |
| 4. Popolazione | ✅ | delta encoding, cap 1.000, pruning, albero filogenetico, decimazione |
| 5. Motore biologico | ✅ | xenobiotici-come-metaboliti, µ modulabile (DinB), coniugazione gene-encoded, costo plasmide, migrazione drip |
| 6. Inventario metabolico | ⚠️ | parziale: glucosio, O₂, Fe³⁺ usati; H₂/CH₄/SO₄²⁻/H₂S/NH₃/NO₃⁻ non esercitati (chemiolitotrofia non toccata) |
| 7. Sistema generativo | ✅ | tutti tre i regimi: drift parametrico, salto categorico (loss-of-receptor), innovazione composta (chimera ferri-reduttasi) |
| 8. Pressioni selettive | ✅ | A,B,C,D coperti: stress fisico-chimico, lisi alla divisione, lisi fagica, dilution, competizione emergente |
| 9. Quorum sensing | ✅ | emergenza density-dipendente, biofilm-induction, speciazione comunicativa indotta |
| 10. Topologia network | ✅ | archetipi multipli (eutrofico, salino, lago olig.), zone, bridge edge, colonizzazione con sostenibilità |
| 11. Tempo | ✅ | scale rispettate (settimane = migliaia di gen), tick 5 min, sessioni 1–2 ore |
| 12. Confine micro/macroscala | ✅ | 3 fasi nello stagno, distribuzione emergente, intervento phase-level |
| 13. Anti-griefing | ✅ | cooldown colonizzazione, intervention budget, audit log con origin tracking, principio E confermato |
| 14. Stack tecnologico | ✅ | implicito: ogni meccanismo mappa a GenServer + Ecto sostenibili nei limiti del prototipo |

### 4.2 Coperture parziali da rinforzare in casi d'uso futuri

Non sono lacune del design, ma ambiti che il singolo walk-through non ha esercitato a sufficienza:

- **Chemiolitotrofia**: serve un caso d'uso che esercitti H₂/H₂S/CH₄ (es. termofilo idrogenotrofo che si insedia in una sorgente idrotermale)
- **Tossicità di metaboliti naturali accumulati**: H₂S inibitore di citocromi, lattato che acidifica
- **Bacteriocine**: warfare biologico target-specifico fra ceppi
- **Co-evoluzione fagi-ospite di lungo termine** (>10⁴ generazioni): arms race profonda, mutazioni ricorrenti dei recettori e delle palindromi RM

### 4.3 Buchi nel design emersi

A differenza del primo caso d'uso (Blocco 5 di DESIGN.md, che produsse 8 gap di design corretti durante le iterazioni successive), il walk-through integrale **non rivela inconsistenze gravi**. Tre considerazioni minori, di balancing/implementazione:

1. **Intervention budget vs sessioni esplorative**. 1 azione/30 min reali può essere stretto per chi sperimenta intensivamente (es. testare in sequenza diversi antibiotici). Possibile mitigazione: pool accumulabile fino a N azioni stoccate (es. 5), che si rigenera con la stessa cadenza. **Decisione di balancing futura**, non di design.
2. **Distribuzione di fase per nuovo lignaggio neonato**. Quando un nuovo lignaggio nasce per mutazione/HGT, eredita la distribuzione di fase del parent (snapshot all'istante di nascita) e la ricomputa al tick successivo. **Da chiarire nell'implementazione**, non riapre la decisione di design.
3. **Cap 1.000 lignaggi in biotopo wild appena colonizzato**. I lignaggi wild residenti restano e seguono le stesse regole (selezione, migrazione, pruning) senza differenze meccaniche. La "wildness" è solo flag di non-controllo del giocatore. **Da confermare nell'implementazione**.

### 4.4 Verdetto

Il design è **internamente coerente**. Tutti i 14 blocchi si integrano in uno scenario continuo che produce fenomeni biologicamente plausibili e riconoscibili dal pubblico esperto target:

- emergenza di biofilm da quorum sensing
- evoluzione di resistenza antibiotica per drift + duplicazione/neofunzionalizzazione
- arrivo di un profago e arms race con difese codificate (loss-of-receptor + RM)
- colonizzazione emergente di un wild adiacente
- speciazione comunicativa indotta
- innovazione composta via traslocazione (chimera ferri-reduttasi)
- fallimento di un attacco indiretto (plasmide burden) per pure forze ecologiche, senza intervento ops

I 3 punti residui sono raffinamenti di balancing o di implementation, non lacune di design. **Il design è pronto per la fase implementativa.**
