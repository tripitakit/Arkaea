> 🇮🇹 Italiano (questa pagina)

# Review Arkea — Prospettiva ricercatore / studente di biologia molecolare

**Data**: 2026-05-08
**Scope**: review dell'app Arkea allo stato corrente (post-Fase 20, post Community Mode) dal punto di vista di **uno studente magistrale / dottorando in biologia molecolare** — focus su sequenza, struttura-funzione delle proteine, regolazione genica, meccanismi enzimatici, replicazione, ricombinazione, mutagenesi. Complementare alla review microbiologica (`13-MICROBIOLOGIST-PERSPECTIVE-REVIEW.md`), che guarda a livello di popolazione e dinamica ecologica. Qui il focus è **al di sotto della cellula**: cosa succede al DNA e alle proteine.

---

## 1. Premessa

Arkea ha una scelta di design potente: il genoma è una **sequenza di codoni logici (50–200 simboli)** su alfabeto 20, organizzata in domini funzionali con `type_tag` (3 codoni) + `parameter_codons` (10–30). Le mutazioni in `type_tag` causano flip categoriale del dominio, quelle in `parameter_codons` driftano i valori continui (kcat, Km, binding affinity). Questo è il livello su cui un biologo molecolare vive.

Il problema è che **questo livello, oggi, è quasi invisibile all'utente**:
- non esiste una vista delle sequenze di codoni per un gene (il `GenomeCanvas` mostra il cromosoma circolare con archi-gene e sub-archi-dominio, ma non *dentro* il dominio);
- `promoter_block` e `regulatory_block` esistono come campo nello schema `Gene` ma sono `nil` in Phase 1;
- `:regulator_output` è parsato (mode, cooperativity) ma non entra nell'aggregazione fenotipica;
- `Gene.operon_id` esiste come UUID ma non c'è modulo `Operon` né logica di espressione coordinata a runtime;
- `ribosome_like = 1.0` è hardcoded in `phenotype.ex:291`, in violazione del principio "tutto è genoma" (Blocco 5);
- la coniugazione usa il solo conteggio di `:transmembrane_anchor` come proxy del pilo, senza la triade `pili_like + relaxase_like + oriT_like` prescritta;
- il sistema R-M lavora su `signal_key` opachi a 4 codoni, senza una sequenza di riconoscimento DNA modellizzata.

Per il pubblico target di un biolmol, queste omissioni non sono "ottimizzazioni del prototipo": sono **il livello di astrazione su cui il sistema dovrebbe insegnare**. Questa review li elenca per impatto.

---

## 2. Cosa funziona bene (riconoscimenti, da preservare)

- **Modello di gene generativo coerente.** `[promoter] [regulatory] domain_1 ... domain_N` con codoni dell'alfabeto 20 e domini come `type_tag + parameter_codons` (`gene.ex`, `codon.ex`). È il cuore solido.
- **`weighted_sum(codons)` come kernel parametrico** (`codon.ex:136-148`). Pesi log-normali fissati a compile-time → stabilità inter-run, riproducibilità.
- **Distinzione strutturale vs parametrica delle mutazioni.** SNP nel `type_tag` flippa il dominio (raro), SNP nei `parameter_codons` driftano via `weighted_sum` (continuo). È biolmol-corretto.
- **Cinque tipi di mutazione** in `Arkea.Genome.Mutation`: substitution, indel, duplication, inversion, translocation. Coerente con i meccanismi reali.
- **Quorum sensing con signature 4D** (`signaling.ex:1-90`): matching gaussiano `exp(−dist²/(2σ²))` → drift comunicativo emergente, eavesdropping e privacy come bande di σ. Bel modello.
- **Trasformazione naturale con tre domini proxy + R-M gate + uptake stocastico** (`hgt/channel/transformation.ex`). Più maturo della coniugazione.
- **`Phenotype.from_genome/1`** itera tutti i domini (cromosoma + plasmidi + profagi) una sola volta — efficiente e semanticamente pulito.

---

## 3. Priorità A — Visibilità del livello molecolare (oggi assente)

> "Se il sistema mi dice che c'è una mutazione SNP nel codone 47 del gene G2, devo poterlo *vedere*."

1. **Codon-level viewer** per un gene selezionato. Zoom successivo: cromosoma → operone (quando esisterà) → gene → sequenza di 50–200 codoni rappresentati con i 20 simboli, con bande colorate per `type_tag` (3 codoni) vs `parameter_codons` (10–30). Highlight delle mutazioni accumulate dal lignaggio rispetto al riferimento clade. Senza questo, il modello generativo è solo numerico.
2. **Mappa lineare del gene con annotazioni**: in alto la sequenza di codoni; sotto le bande dei domini parsati con i loro `params` calcolati (kcat, Km, binding_affinity, thermal_stability, pH_optimum); a fianco i codoni intergenic (`intergenic_blocks.orit_site`, etc.) — oggi opachi, dovrebbero essere etichettati.
3. **Mutation hotspot map** per gene: per ogni codone, n. di mutazioni accumulate sul ramo del lignaggio dal MRCA, distinte in synonymous-like (param drift entro la classe) vs non-synonymous-like (cambio del valore aggregato del param) vs missense-like (flip del `type_tag`). Insegna il dN/dS-equivalente di Arkea.
4. **Diff codonico fra due varianti dello stesso gene** (allineamento posizionale, non BLAST — basta affiancare le due liste di codoni con highlight delle differenze e indicare se la differenza tocca il `type_tag` o un `parameter_codon`).
5. **Eventi audit per livello molecolare**: `:domain_flip` (un `type_tag` muta in modo da cambiare la categoria del dominio) e `:gene_chimera_birth` (translocazione che fonde due geni in un terzo) sono i due "salti" che il manuale promette come "innovazione composta". Oggi avvengono ma non sono etichettati come eventi visibili.

---

## 4. Priorità B — Strumenti di analisi molecolare

Quattro viste che un biolmol replicherebbe in un notebook se non gli fossero offerte.

1. **Network regolatorio del lignaggio**: i domini `:dna_binding` + `:regulator_output` (mode `:activator` / `:repressor`, cooperativity) puntano a target. Visualizzare il grafo dei target è il modo standard per studiare regolazione. Oggi `:regulator_output` non è nemmeno aggregato — quindi prima va implementato, poi visualizzato.
2. **Tracker di espressione per gene**: time-series del livello di espressione di un singolo gene in un singolo lignaggio, con marker delle perturbazioni (intervento, σ-factor stress, signal threshold superato). Oggi `Phenotype.from_genome/1` aggrega tutto in scalari globali (`base_growth_rate`, `dna_binding_affinity`); manca la granularità per-gene.
3. **Landscape struttura-funzione di un dominio**: dato un `:catalytic_site`, scatter 2D dei valori (kcat, Km) di tutte le sue varianti nel biotopo o nel clade, colorato per fitness/abbondanza. È *il* grafico che chiunque studi enzymology vorrebbe vedere.
4. **σ-factor activity tracker**: con la cascata sigma reale (vedi §10), tracker dei principali σ attivi nel lignaggio per tick — quale stress li sta inducendo, quale set di promotori stanno transcribendo. Oggi inesistente perché il modello è ridotto a uno scalare 0.5..1.5.

---

## 5. Priorità C — Onboarding e modello mentale (livello molecolare)

Il manuale spiega popolazione, fasi, archetipi. Sul livello molecolare assume che il lettore deduca da solo cosa significa "alfabeto 20" o "domini con type_tag".

1. **Tutorial "anatomia di un gene Arkea"** (in-app, 4 step): (i) ecco la sequenza di codoni; (ii) ecco i domini parsati; (iii) ecco i parametri continui derivati; (iv) ecco come una mutazione cambia uno o l'altro. Senza questo, il modello generativo resta una scatola nera anche per chi capisce il concetto.
2. **Glossario molecolare espanso**: oggi `help.ex` ha `kcat`, `km`, `oriT` ma non `codone logico` (nostro), `type_tag`, `parameter_codons`, `domain flip`, `chimeric gene`, `weighted_sum`, `signature 4D`. Senza questi termini, il pannello fenotipo è opaco.
3. **Mappa "dominio → funzione reale"**: gli 11 tipi di dominio (substrate-binding, catalytic_site, transmembrane_anchor, channel_pore, energy_coupling, dna_binding, regulator_output, ligand_sensor, structural_fold, surface_tag, repair_fidelity) andrebbero spiegati con un esempio di gene reale per ognuno (es. β-lactamasi = substrate-binding + catalytic_site, lac repressor = dna_binding + ligand_sensor + regulator_output). Oggi la mappatura va dedotta.
4. **Convenzioni di notazione**: `:catalytic_site(reaction_class: :hydrolysis)` vs `:catalytic_site(reaction_class: :isomerization)` per restrittasi vs metilasi è un'astrazione molto specifica di Arkea; va dichiarata esplicitamente.

---

## 6. Priorità D — Interventi a livello molecolare

Oggi i 4 interventi (`nutrient_pulse`, `plasmid_inoculation`, `xenobiotic_pulse`, `mixing_event`) operano tutti a livello di fase. Per un biolmol mancano interventi *intra-cellulari*, che sono la manipolazione classica di laboratorio.

1. **In silico mutagenesi guidata su lignaggio**: seleziono un lignaggio, scelgo un gene, scelgo un codone (o un range), applico una mutazione (`:substitution`, `:indel`, `:inversion`, `:duplication`) → genera un nuovo lignaggio child. È la versione "lab-bench" del processo di mutazione casuale che già avviene. Permette di rispondere a "cosa succederebbe se cambiassi il codone 12 di questo gene?".
2. **Knockout / knockdown**: rimuovi un gene da una copia del lignaggio (KO) o riducine l'espressione (KD modificando il `promoter_block` quando esisterà). Genera un mutante child da osservare in competizione con il parent.
3. **Heterologous expression**: prendi un gene (o operone) da un lignaggio e introducilo in un altro lignaggio ricevente (intervento più mirato della trasformazione naturale stocastica).
4. **Pulse mutageno**: UV-like / MMS-like che alza temporaneamente il `dna_damage_score` di tutti i lignaggi in una fase, attivando SOS e accelerando l'evoluzione. Permette di studiare la cascata SOS → mutator → resistenza in tempi compressi.
5. **Inibitore mirato di un dominio**: dosaggio di una piccola molecola che si lega a un target_class specifico (estensione del `:xenobiotic_pulse` attuale a target diversi da `:beta_lactam`). Vedi review microbiologo §6.

**Vincolo da rispettare**: tutti questi interventi devono restare entro l'intervention budget rigenerativo dichiarato nel design. Sono *ricchezza qualitativa*, non frequenza maggiore.

---

## 7. Priorità E — Filogenesi a livello di sequenza

Il dendrogramma in `phylogeny.ex` è macroscopico (lineage, abbondanza, branch length). Per un biolmol è incompleto.

1. **Filogenesi di un singolo gene** (gene tree, distinto dal species tree dei lignaggi). I geni passano per HGT, quindi il gene tree differisce dal species tree — è esattamente il fenomeno che un biolmol vuole studiare.
2. **Ricostruzione ancestrale della sequenza** di un gene a un nodo interno del dendrogramma: dati i codoni dei discendenti, infer il codoni più probabili dell'ancestor (anche solo majority rule per partire). Permette di rispondere a "questo dominio era già attivo nel MRCA o è emerso dopo?".
3. **Convergenza a livello di dominio**: quando due lineage indipendenti acquisiscono per drift parametrico lo stesso valore approssimativo di kcat o Kd, evidenziarli. Visualizza il parallelismo molecolare (omologi vs analoghi).
4. **Mutation rate per branch normalizzato per branch length**: il dato c'è (`mutation_summary` in `phylogeny.ex`), manca la normalizzazione. Permette di identificare i mutator a colpo d'occhio sul dendrogramma.

---

## 8. Priorità F — Lab notebook molecolare, replay, condivisione

Le esigenze di notebook coincidono con quelle del microbiologo (review §8 del 13-). Il taglio biolmol aggiunge:

1. **Bookmark di un evento molecolare**: "tick 2104, gene G7 nel lignaggio L19, codone 33: mutazione `:substitution` da `:tyr` a `:phe` → kcat passato da 8.2 a 12.4 s⁻¹". Salvare il bookmark con annotazione e poterlo richiamare.
2. **Export FASTA-like** delle sequenze di codoni: anche se non sono nucleotidi reali, esportabili come sequenze su alfabeto 20 con header `>lineage_id|gene_id|tick=N`. Permette analisi esterne (allineamento multiplo con tool standard adattati, distanze di Hamming, etc.).
3. **Export GFF-like** dell'annotazione genomica: posizioni di geni, domini, intergenic blocks su un cromosoma → consumabile in viewer come IGV-style.

---

## 9. Priorità G — Polish UX (livello molecolare)

1. **Unità ovunque sui parametri molecolari**: kcat in `s⁻¹`, Km in `mM`, binding_affinity in unità arbitrarie ma dichiarate. Oggi i numeri appaiono crudi.
2. **Tooltip chimico sui domini**: hover su `:catalytic_site(reaction_class: :hydrolysis)` → "Idrolasi: catalizza il taglio idrolitico di un substrato. In Arkea genera anche restrittasi e β-lattamasi a seconda del partner `:substrate_binding`."
3. **Distinzione visiva fra codoni del cromosoma vs del plasmide vs del profago** nel viewer del lignaggio. Oggi il `GenomeCanvas` distingue plasmide ma non profago; e il livello codone non esiste affatto.
4. **Indicatore di "stress molecolare"** del lignaggio: chip con `dna_damage_score`, stato SOS (binario o livello quando il sigma reale arriverà), tasso di mutazione effettivo dell'ultima finestra. Oggi sparso.

---

## 10. Bug / incoerenze critiche per credibilità molecolare

Più gravi della review microbiologo, perché toccano direttamente il livello su cui un biolmol giudica il sistema.

- **`promoter_block` e `regulatory_block` sono `nil` in Phase 1.** Il design li dichiara strutturali, l'implementazione li ha rimandati a Phase 3. Conseguenza: la regolazione promessa nel manuale (operoni con sigma + riboswitch) non esiste a runtime; la "regolazione" è uno scalare globale `0.5 + dna_binding_affinity`. Per un biolmol questa è la differenza fra "ha un modello" e "non ha un modello". Va o implementato Phase 3, o **dichiarato chiaramente nel manuale come limitazione v1**.
- **`:regulator_output` parsato ma non aggregato.** I parametri (mode, cooperativity) sono calcolati e poi ignorati. Un biolmol noterà subito che il dominio ha solo metà del suo lavoro fatto.
- **`Gene.operon_id` senza `Arkea.Genome.Operon`.** Campo dato senza logica runtime. Espressione coordinata di geni nello stesso operone non avviene. Il manuale dovrebbe dichiararlo.
- **`ribosome_like = 1.0` hardcoded** in `phenotype.ex`. Il principio dichiarato del Blocco 5 è "tutto è genoma": il ribosoma reale è un complesso ribozima-proteina che andrebbe espresso da geni dedicati (rRNA-like + r-protein-like). Per un biolmol, il fatto che il ribosoma sia una costante globale è inaccettabile dal punto di vista didattico — anche un placeholder derivato dal conteggio di domini specifici sarebbe meglio. Vedi anche commento in `phenotype.ex:521-523` che documenta il workaround.
- **Coniugazione: solo proxy `:transmembrane_anchor`**. Manca la triade `pili_like + relaxase_like + oriT_like` prescritta dal design. Il modello attuale è "se hai abbastanza domini transmembrana sei capace di coniugazione", che non distingue i pili sex dai canali generici. Conseguenze: niente plasmidi mobilizable (richiedono `relaxase` ma non `pili`), niente entry exclusion, niente compatibility groups veri.
- **Recognition sequence DNA assente nel sistema R-M.** `Defense.ex` lavora su `signal_key` opachi a 4 codoni, non c'è un modello esplicito di sequenza riconosciuta. Per un biolmol, R-M *è* riconoscimento di sequenza specifica + metilazione protettiva: non averlo modellato è una semplificazione sostanziale che merita una nota nel manuale.
- **Methylation come lista di chiavi senza per-nucleotide tracking.** Coerente con la scelta di non avere DNA reale, ma va dichiarato.
- **SOS threshold 0.20 modulo-level** anziché derivato da `:ligand_sensor` DNA-damage-like. Nessuna evoluzione della sensibilità SOS. LexA/RecA è uno dei sistemi regolatori più studiati in biologia molecolare; un biolmol noterà subito la rigidità.

**Raccomandazione complessiva**: in `04-CALIBRATION.md` o `USER-MANUAL.md` aggiungere una sezione **"Limitazioni del modello molecolare v1"** che dichiari onestamente: niente promotori/regulatory blocks parsati, σ scalar invece che cascata, operoni dato-only, ribosoma costante, coniugazione con proxy minimo, R-M senza sequenza DNA. Il pubblico target *preferisce* limitazioni dichiarate a meccanismi pubblicizzati che non funzionano.

---

## 11. Top 5 raccomandazioni (se si potesse fare solo questo)

In ordine di rapporto valore/sforzo per il pubblico biolmol:

1. **Codon-level viewer per un gene** (Priorità A.1) — sblocca tutto il livello molecolare didattico in un colpo solo.
2. **Aggregare `:regulator_output` in σ multi-componente + operoni runtime** (Priorità A + Bug §10) — chiude due gap di credibilità in una passata, perché operoni e σ sono coupled.
3. **In silico mutagenesi guidata sul lignaggio** (Priorità D.1) — l'intervento più richiesto per un biolmol; semantica già presente nel sistema (basta esporre `Mutation.Substitution.apply/2` come azione UI).
4. **Diff codonico fra due varianti dello stesso gene** (Priorità A.4) — vista a basso costo che cambia il workflow di analisi evolutiva.
5. **Sezione "Limitazioni del modello molecolare v1"** in `04-CALIBRATION.md` o `USER-MANUAL.md` — proteggere la credibilità preventivamente, dichiarando ciò che non c'è.

---

## 12. File di riferimento (non modificati in questa review)

- `arkea/lib/arkea/genome/gene.ex` — schema gene, `operon_id` senza runtime, `promoter_block`/`regulatory_block` nil
- `arkea/lib/arkea/genome/codon.ex` — alfabeto 20 hardcoded, `weighted_sum/1` kernel parametrico
- `arkea/lib/arkea/genome/mutation/` — substitution, indel, duplication, inversion, translocation
- `arkea/lib/arkea/sim/phenotype.ex` — `from_genome/1`, `:regulator_output` non aggregato (vedi commento `:521-523`), `ribosome_like = 1.0` hardcoded (`:291`)
- `arkea/lib/arkea/sim/signaling.ex` — QS con signature 4D, matching gaussiano (modello biolmol-corretto)
- `arkea/lib/arkea/sim/hgt/defense.ex` — R-M Arber-Dussoix con recognition opaco
- `arkea/lib/arkea/sim/hgt/channel/transformation.ex` — Phase 13, modello competence + uptake stocastico + R-M gate
- `arkea/lib/arkea/sim/hgt.ex` — coniugazione con proxy `:transmembrane_anchor`
- `arkea/lib/arkea_web/components/genome_canvas.ex` — viewer cromosoma circolare attuale (manca livello codone)
- `arkea/lib/arkea_web/components/help.ex` — glossario da estendere a termini molecolari
- `USER-MANUAL.md`, `devel-docs/04-CALIBRATION.md` — sede per "Limitazioni del modello molecolare v1"

---

## 13. Validazione del valore di queste raccomandazioni

Come per la review microbiologo, non c'è verifica software per una review di prodotto. Test d'uso reale:

1. **Test su 1-2 utenti biolmol non coinvolti nello sviluppo**: 30 minuti di esplorazione libera + 15 minuti di task ("descrivimi la struttura di un gene di un lignaggio a tua scelta", "trova un evento di mutazione che ha causato un flip di dominio"). Misurare: completamento, dove si bloccano, quali termini chiedono, quante volte aprono il manuale.
2. **Validazione che il codon viewer permetta di osservare almeno**: (a) un evento `:substitution` come differenza visibile fra parent e child del lignaggio; (b) un evento di flip dominio (rara) come cambio di colore della banda `type_tag`; (c) una duplicazione come ripetizione di codoni.
3. **Validazione narrativa**: aprire `01-DESIGN.md` Blocco 5 (sistema generativo dei domini), trovare la descrizione "gene = sequenza di codoni logici (50–200), alfabeto 20 simboli, struttura `[promoter_block] [regulatory_block opz.] domain_1 ... domain_N`", aprire l'app, dimostrare che ogni elemento di questa descrizione è osservabile in <10 minuti.
