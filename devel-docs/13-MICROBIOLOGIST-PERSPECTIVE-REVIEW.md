> 🇮🇹 Italiano (questa pagina)

# Review Arkea — Prospettiva ricercatore / studente di microbiologia

**Data**: 2026-05-08
**Scope**: review dell'app Arkea allo stato corrente (post-Fase 20, post Community Mode) dal punto di vista di **uno studente magistrale / dottorando in microbiologia ambientale** che apre il sistema per la prima volta dopo aver letto README e USER-MANUAL. Categorizza punti di forza, attriti e funzionalità mancanti per il pubblico target dichiarato (biologi/microbiologi/genetisti). Non è un piano di implementazione: è feedback strutturato per il prossimo round di prioritizzazione.

---

## 1. Premessa

Arkea è oggi un sandbox evolutivo persistente con un modello biologico end-to-end internamente coerente: genoma generativo a 11 domini, metabolismo Michaelis-Menten su 13 metaboliti, HGT su 4 canali, R-M, ciclo fagico chiuso, SOS, error catastrophe, QS, bacteriocine, biofilm, mixing event. La documentazione scientifica (`USER-MANUAL.md`, `04-CALIBRATION.md`) è rigorosa e calibrata su letteratura primaria.

La superficie utente, però, è **frammentaria rispetto alla profondità del modello sotto**: meccanismi importanti girano "muti" in audit, gli interventi del giocatore sono pochissimi, mancano strumenti di analisi che un microbiologo si aspetta da un sistema che si propone come "rigoroso, non gamificato".

Questa review è scritta dal punto di vista di chi *vuole credere* nel sistema e *vuole usarlo per studiare*, ma deve testarne la trasparenza.

---

## 2. Cosa funziona bene (riconoscimenti, da preservare)

- **Tono scientifico, non gamificato.** Il manuale parla di "displacement plasmidico" e "error catastrophe" anziché di "boss battles". È raro e prezioso per il pubblico target.
- **Modello generativo dei domini funzionali.** L'idea che β-lattamasi emerga da `Substrate-binding + Catalytic` con parametri continui, e non sia un attributo speciale, è didatticamente potentissima.
- **Audit log + export JSON/CSV.** Il fatto che ogni evento sia ricostruibile post-hoc è esattamente l'aspettativa di chi tiene un lab notebook.
- **Calibrazione documentata con riferimenti primari** (`04-CALIBRATION.md`). Costanti difendibili, override configurabili — il setup giusto per benchmark di ipotesi.
- **Dendrogramma filogenetico con `mutation_summary` per branch.** Non lo si vede in molti simulatori didattici.
- **Glossario in-app con tooltip e link contestuali** (`arkea_web/components/help.ex`).

---

## 3. Priorità A — Visibilità dei meccanismi che oggi sono muti

> "Se non posso *vedere* la R-M digerire un plasmide, non posso insegnare il concetto né validare che il sistema lo stia davvero facendo."

Questi sono già implementati nel sim core ma **non emettono audit events**, quindi un ricercatore non sa quando avvengono. È il gap più demoralizzante per un nuovo utente: il manuale promette, l'UI tace.

1. **Distinguere i 4 canali HGT in audit** (oggi solo `:hgt_transfer` generico). Servono `:transformation_event`, `:transduction_event`, `:conjugation_event`, `:phage_infection`. Il `HGTLedgerLive` li aspetta già ma non li riceve.
2. **Eventi di difesa**: `:rm_digestion` (R-M che taglia DNA esogeno), `:plasmid_displaced` (incompatibilità o entry exclusion), `:bacteriocin_kill` (con coppia killer/target lineage). Senza questi, l'arms race è invisibile.
3. **SOS / stress molecolare**: `:sos_active` (con `dna_damage_score` e trigger), `:mutator_emergence` (quando un lignaggio sale a hypermutator), `:error_catastrophe_death`. Oggi `dna_damage` è interno al fenotipo ma non viene mai loggato; risultato: l'utente vede il `:phage_burst` ma non capisce che era stato preceduto da SOS-induction.
4. **Biofilm formation / dispersal** come evento (oggi solo `:biofilm_capable` come tratto continuo).
5. **Migrazione tra biotopi**: oggi nessun audit. Servono almeno aggregati periodici (`:migration_pulse` per archi top-N).

**Why per il microbiologo**: il manuale promette *forensic completo*, ma se cerco "quando è arrivato il prophage in questo biotopo" oggi devo desumerlo dai diff di stato. È esattamente il problema che l'audit log dovrebbe risolvere.

---

## 4. Priorità B — Strumenti di analisi che un biologo si aspetta

Il sistema espone fenotipo e abbondanza in snapshot, ma **non in vista live confrontabile**. Aggiungere queste 4 viste sarebbe più utile di qualunque nuova meccanica.

1. **Trait tracker per lignaggio**: time-series di un singolo tratto fenotipico (es. `hydrolase_capacity`, `repair_efficiency`, `n_transmembrane`) per uno o più lineage selezionati, con eventi audit sovrapposti. Senza questo è impossibile mostrare *evoluzione di un tratto*, che è il punto del simulatore.
2. **Diff genoma tra due lineage**. Selezione multipla nel dendrogramma → pannello con: geni condivisi, geni unici, mutazioni puntiformi sui codoni, riarrangiamenti. È il workflow standard di chiunque studi adattamento.
3. **Mappa metabolica del biotopo**: heatmap o piccolo network dei 13 metaboliti per fase, con flussi netti tra lineage (chi produce acetato → chi lo consuma). Dichiara visivamente la sintrofia che oggi è solo nei pool numerici.
4. **Distribuzione fenotipica del biotopo**: violin plot di un tratto across lineage, pesato per abbondanza. Permette di vedere "il biotopo si sta polarizzando su due strategie di crescita?".

**Why**: oggi l'export JSON ha tutto, ma il flusso è "esporta → carica in un notebook → analizza". Serve almeno la vista live per le 3-4 domande più ricorrenti, perché la maggior parte degli osservatori non scriverà un notebook ad ogni dubbio.

---

## 5. Priorità C — Onboarding e modello mentale

Il manuale è ottimo ma assume lettura sequenziale. Un microbiologo curioso vuole *toccare* in 5 minuti.

1. **Quick-start scenari "ipotesi pronte"**: oggi `Scenarios` ne ha 3 generici (lake/prophage, cross-feeding bloom, soil generalist). Servono scenari *con domanda di studio dichiarata*, ad es:
   - "Evoluzione di resistenza a β-lattamico sotto dosaggi ripetuti" (intervento `:xenobiotic_pulse` schedulato).
   - "Arms race ospite-fago con perdita di recettore vs R-M".
   - "Speciazione comunicativa sotto QS dialect drift".
   Ogni scenario specifica: ipotesi attesa, KPI da osservare, tempo stimato in tick reali.
2. **Tutorial guidato sul primo biotopo demo** con tooltip sequenziali (3-5 step): "Questa è una fase. Questo è un lignaggio. Clicca questo gene per vedere i suoi domini. Questo evento è una coniugazione." Il manuale lo descrive a parole; in-app non c'è.
3. **Cheat-sheet 13 metaboliti × 8 archetipi**: una matrice in `/help` (o popup) che dice quale metabolita è abbondante in quale archetipo e quali nicchie metaboliche apre. Oggi è ricostruibile ma sparso.
4. **Glossario espanso a tutti i campi tecnici dei pannelli**: oggi solo nei doc. Ad esempio nel Lineage panel mostro `dna_damage 0.18`, `repair_efficiency 0.42` — un primo utente non sa interpretarli senza saltare al manuale.
5. **Help context-sensitive nel pannello**: pulsante "?" per ogni sezione che apre il glossario alla voce giusta, non l'index.

---

## 6. Priorità D — Interventi del giocatore (oggi solo 4)

Per un microbiologo l'aspetto più "lab-like" sono gli interventi: oggi sono `:nutrient_pulse`, `:plasmid_inoculation` (con plasmide modello hardcoded a 1 gene!), `:xenobiotic_pulse` (solo β-lattam), `:mixing_event`. Sono pochi e poco controllabili.

1. **Plasmide custom inoculabile**: pescato dal Seed Lab del giocatore o costruito mini-editor (subset di domini). Senza questo, "inoculazione di plasmide" è un placeholder.
2. **Xenobiotici diversi da β-lattam**: aminoglicosidico (target `ribosome_like` quando esisterà davvero), fluorochinolonico (target repair/topoisomerasi), polimixina (target membrane). Il framework `target_class` è già generativo, ma in UI ne dosi solo uno.
3. **Pulse di nutrienti specifici**: oggi è un mix fisso `{glucose, nh3, po4}`. Permettere di scegliere il metabolita (anche tossico, es. H₂S, NO₃⁻) trasforma `nutrient_pulse` da "fertilizzante" a *strumento di selezione*.
4. **Knockdown / pressione selettiva mirata**: rimozione di un metabolita (chemiostat shift), shift di pH/temperatura/osmolarità entro un range, hit a fase specifica. Sono micro-perturbazioni che un microbiologo userebbe per ipotesi mirate.
5. **Inoculazione di un lignaggio osservato altrove**: "voglio prendere quel mutator emerso nel mio biotopo A e introdurlo in B per vedere se invade". Oggi impossibile.
6. **Dosaggio temporale**: schedulare un pulse ogni N tick (oggi solo one-shot). Per studi di resistenza è essenziale.

**Vincolo da rispettare**: il design ha già fissato l'intervention budget rigenerativo (~1 grande ogni 30 min reali) come anti-griefing. La proposta è **arricchire i tipi entro lo stesso budget**, non aumentarne la frequenza.

---

## 7. Priorità E — Filogenesi e analisi evolutiva

Il dendrogramma è bello ma è un dead-end: lo guardi, e basta.

1. **Click su nodo ancestrale → ricostruzione genoma ancestrale** (anche solo come "genoma del MRCA dei lineage selezionati"). È il workflow di chiunque studi origini di un tratto.
2. **Filtro per tratto**: "colora il dendrogramma per `hydrolase_capacity`" o "per presenza di prophage X". Oggi colora solo per abbondanza.
3. **Highlight delle convergenze**: quando due lineage indipendenti acquisiscono lo stesso tratto a soglia (es. β-lattamasi attiva > Y), evidenziarli. Insegna *parallelismo evolutivo* visivamente.
4. **Tasso di mutazione per branch** (sub/indel/dup/inv per generazione): il dato c'è in `mutation_summary`, manca normalizzazione su branch length. Permette di identificare i mutator a colpo d'occhio.
5. **Rate eventi HGT in linea**: per ogni branch, quanti `hgt_transfer` ricevuti / inviati. Identifica "hub" di scambio.

---

## 8. Priorità F — Notebook scientifico, condivisione, replay

Oggi puoi esportare ma non puoi annotare né condividere uno stato.

1. **Annotazioni / lab notebook per biotopo**: campo testo libero attaccato a uno specifico tick per il giocatore. "Tick 1827: β-lactam pulse ha selezionato lineage L42 (hydrolase 0.87)." È *davvero* un quaderno di laboratorio.
2. **Permalink temporali**: link che riapre il biotopo allo stato del tick X. Indispensabile per condividere con un collega o per discussione asincrona.
3. **Snapshot bookmarkati**: marcatori a un certo tick con label utente, visibili sulla time-series.
4. **Replay con scrubbing**: cursore temporale sul biotopo viewport per scorrere gli ultimi N tick (lo stato è ricostruibile da snapshot ogni 10 tick + WAL).
5. **Export "notebook-ready"**: oltre JSON/CSV, formato direttamente importabile (parquet via `polars`, o pickled `AnnData` per single-cell-like). Non bloccante, ma molto apprezzato dagli utenti tecnici.

---

## 9. Priorità G — Polish UX di basso costo, alto impatto

Cose piccole che un nuovo utente nota nei primi 5 minuti.

1. **Countdown al prossimo tick** sul biotope panel ("prossimo tick fra 2:47"). L'asincronia 24/7 è un'idea forte ma deve essere palpabile, non astratta.
2. **Indicatore di stress globale del biotopo**: chip visibile (verde/giallo/rosso) basato su `mean(dna_damage)`, `mass_lysis_rate_recent`, `xenobiotic_concentration`. Oggi devi aprire il pannello chimica per intuirlo.
3. **Numeri formattati** (oggi `total_abundance` può essere `4.231e7` in test ma nei panel a volte è raw). Notazione SI consistente.
4. **Unità di misura ovunque**: `kcat 12` è ambiguo, `kcat 12 s⁻¹` no. Richiesto da pubblico tecnico.
5. **Vuoto/zero state** per i pannelli: cosa mostrare se un biotopo non ha lineage, fagi liberi, o eventi audit nelle ultime N ore.
6. **Loading skeletons** invece di "Loading...": LiveView lo permette nativamente.
7. **Mobile/tablet responsive**: in laboratorio si consulta da iPad o telefono accanto al banco. Oggi alcuni pannelli sono desktop-only.

---

## 10. Bug / incoerenze noti che impattano la credibilità scientifica

Da `09-BIOLOGICAL-MODEL-REVIEW-2.md` e debito documentato post-Fase 20. Per un ricercatore questi sono *deal-breaker* di credibilità: se il manuale promette X e il codice fa Y silenziosamente, il sistema perde fiducia.

- **`ribosome_like = 1.0` hardcoded** in `phenotype.ex` viola il principio "tutto è genoma" (Blocco 5). Va derivato dai domini, oppure va dichiarato il workaround in calibrazione.
- **SOS threshold = 0.20 modulo-level** anziché derivato da `:ligand_sensor`: nessuna evoluzione della sensibilità SOS. Anti-realistico per chi conosce LexA/RecA.
- **Coniugazione con proxy `:transmembrane_anchor`** anziché triade `pili_like + relaxase_like + oriT_like` prescritta. La distinzione conta per chi vuole studiare evoluzione di plasmidi non-coniugativi.
- **Operoni dichiarati ma non implementati a runtime**: `Gene.operon_id` esiste, `Arkea.Genome.Operon` no. Espressione coordinata non avviene. Va o tolto dalla narrativa o implementato.
- **`regulator_output` parsato ma non aggregato in σ**: nessuna cascata sigma. Limita la profondità della "regolazione" promessa nel manuale.

**Raccomandazione**: aggiungere a `USER-MANUAL.md` o a `04-CALIBRATION.md` una sezione **"Limitazioni note del modello v1"** che dichiari onestamente questi gap. Il pubblico target *preferisce* limitazioni dichiarate a meccanismi pubblicizzati che non funzionano.

---

## 11. Top 5 raccomandazioni (se si potesse fare solo questo)

In ordine di rapporto valore/sforzo per il pubblico target:

1. **Emettere gli eventi audit mancanti** (Priorità A) — disambigua HGT, SOS, R-M, bacteriocine. Lo `HGTLedgerLive` li aspetta già: serve solo cablare gli emittenti dal sim core.
2. **Trait tracker time-series per lignaggio** (Priorità B.1) — sblocca il workflow base "vedo evolvere un tratto".
3. **Quick-start scenari con ipotesi dichiarata** (Priorità C.1) — converte il manuale in *azioni* nei primi 10 minuti.
4. **Annotazioni + permalink temporali** (Priorità F.1, F.2) — trasforma il sistema da demo in lab notebook.
5. **Sezione "Limitazioni note del modello v1"** in CALIBRATION/USER-MANUAL — proteggere la credibilità preventivamente.

---

## 12. File di riferimento (non modificati in questa review)

- `arkea/lib/arkea/sim/hgt/`, `phage.ex`, `defense.ex` — emissione audit eventi mancanti (Priorità A)
- `arkea/lib/arkea_web/live/hgt_ledger_live.ex` — già pronto a ricevere event types non emessi
- `arkea/lib/arkea_web/live/sim_live.ex` — host del biotope viewport, dei tab Events/Lineages/Chemistry/Interventions
- `arkea/lib/arkea/sim/intervention.ex` — i 4 interventi attuali (Priorità D)
- `arkea/lib/arkea/scenarios.ex` — 3 scenari attuali, da estendere (Priorità C.1)
- `arkea/lib/arkea_web/components/help.ex` — glossario da estendere ai campi panel (Priorità C.4)
- `USER-MANUAL.md`, `devel-docs/04-CALIBRATION.md` — sede per "Limitazioni note v1" (Priorità Top 5)

---

## 13. Validazione del valore di queste raccomandazioni

Non esiste verifica software per una review di prodotto. Il test d'uso reale sarebbe:

1. **Test su 1-2 utenti microbiologi non coinvolti nello sviluppo**: 30 minuti di esplorazione libera + 15 minuti di task ("dimmi quando emerge il primo mutator", "trova un evento di trasformazione"). Misurare: quanti task completati senza assistenza, dove si bloccano, quali termini non capiscono.
2. **Validazione che ogni Priorità A item produca un evento osservabile** in un biotopo seedato con scenario "arms race fagico" (criterio: ledger HGT mostra almeno un evento per categoria entro 200 tick).
3. **Validazione narrativa**: aprire il manuale, leggere una promessa ("vedrai displacement plasmidico"), aprire l'app, dimostrare che è osservabile in <10 minuti senza spiegazioni esterne.
