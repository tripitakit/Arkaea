> 🇮🇹 Italiano (questa pagina) · [🇬🇧 English](12-COMPARATIVE-ANALYSIS.en.md)

# Analisi comparativa — Arkea vs. SLiM, Bacmeta, SimBac

**Data**: 2026-05-08
**Scope**: collocare Arkea rispetto ai tre simulatori più rappresentativi del panorama scientifico contemporaneo per evoluzione di popolazioni (SLiM, *de facto* standard di population genetics) e di popolazioni batteriche (Bacmeta, SimBac). L'obiettivo non è competizione: è chiarezza su *cosa fa Arkea che gli altri non fanno*, e — altrettanto importante — *cosa non fa* (e perché non sostituisce gli strumenti esistenti per i compiti per cui sono stati progettati).

---

## 1. Premessa metodologica

Le quattro simulazioni qui confrontate occupano *nicchie diverse* nel panorama scientifico:

- **SLiM** è un *framework generale di population genetics* — l'utente scrive il modello in Eidos.
- **Bacmeta** è un *simulatore di neutral evolution in metapopolazioni batteriche* — focalizzato su inferenza statistica.
- **SimBac** è un *simulatore coalescente di genomi batterici interi* — focalizzato sul benchmarking di metodi filogenetici.
- **Arkea** è un *sandbox evolutivo persistente di organismi proto-batterici* — focalizzato su osservazione interattiva e didattica.

Confrontarli su una scala unica sarebbe fuorviante. Quello che segue è un confronto *qualitativo per dimensioni significative*, non un benchmark performante.

---

## 2. SLiM — population genetics framework

**Riferimento primario**: Haller BC, Messer PW. *SLiM 3: Forward Genetic Simulations Beyond the Wright–Fisher Model*. Mol Biol Evol 2019. Versione corrente: SLiM 4 (Haller & Messer 2023, multispecies eco-evolutionary modeling).

**Modello**: forward-time, individual-based, non-overlapping o overlapping generations. L'utente specifica il genoma (chromosome map, mutazioni di tipo neutro/positivo/negativo con coefficienti di selezione e dominanza), la struttura demografica (popolazioni con K, m migration rates, K-bottleneck) e gli eventi (Eidos blocks attivati a tick specifici).

**Punti di forza**:

- **Estremamente generale**: con Eidos puoi modellare epistasi, selezione frequency-dependent, mate choice, struttura sociale, qualsiasi regime evolutivo descrivibile.
- **Performance**: ottimizzato per cromosomi interi e popolazioni grandi (10⁵–10⁷ individui).
- **Tree-sequence recording**: integrazione con `tskit` per ricostruzione genealogica esatta.
- **GUI scriptabile**: SLiMgui per debug interattivo.
- **Letteratura**: cento+ paper pubblicati con SLiM, ecosistema maturo.

**Granularità del modello biologico**: il genoma è una *sequenza neutra con loci selezionati*. Le mutazioni hanno fitness effects scalari. Non esiste un concetto di *funzione* del gene: la fitness emerge dai coefficienti che l'utente attribuisce.

**Limiti per il dominio batterico**:

- Niente HGT nativo. L'utente deve simulare conjugation/transformation/transduction come *eventi custom* via Eidos.
- Niente R-M defenses, niente phage cycle, niente quorum sensing, niente bacteriocine. Tutto ricodificabile, ma a carico dello scripting.
- Metabolismo non modellato. La fitness è uno scalar, non emerge da reazioni chimiche.
- Multi-cellulare/biofilm: richiede modeling spaziale custom.

---

## 3. Bacmeta — neutral metapopulation evolution

**Riferimento primario**: Sipola A, Marttinen P, Corander J. *Bacmeta: simulator for genomic evolution in bacterial metapopulations*. Bioinformatics 2018, 34(13):2308–2310.

**Modello**: forward-time, Wright–Fisher su una rete di popolazioni connesse, con genoma esplicito per ogni strain. Migrazione tra popolazioni con matrice di connettività liberamente specificata.

**Punti di forza**:

- **Pensato per likelihood-free inference**: output progettato per ABC (Approximate Bayesian Computation).
- **Genomic islands**: il genoma è composto da regioni indipendenti (proxy per chromosome + secondary chromosomes / plasmidi).
- **Cluster-friendly**: input testuale, produce DNA sequences + pairwise distances + event counts.
- **C++ performante**.

**Granularità del modello biologico**:

- Evoluzione **strettamente neutrale**: nessuna selezione, nessuna fitness differenziale.
- Mutazioni puntiformi su sequenza esplicita.
- HGT come scambio di genomic islands tra popolazioni connesse (una semplificazione di conjugation + lateral transfer).
- Niente fenotipo, niente metabolismo, niente difese, niente fagi.

**Caso d'uso tipico**: stimare parametri di una metapopolazione (mutation rate, migration rate, recombination rate) confrontando summary statistics simulate con dati reali.

---

## 4. SimBac — coalescent whole-genome bacterial simulator

**Riferimento primario**: Brown T, Didelot X, Wilson DJ, De Maio N. *SimBac: simulation of whole bacterial genomes with homologous recombination*. Microb Genom 2016, 2(1):e000044.

**Modello**: backward-time (coalescent) con grafo di ricombinazione ancestrale (ARG). Simula coalescenza clonale + gene conversion (ricombinazione omologa). Supporta sia la ricombinazione intra-specie sia inter-specie.

**Punti di forza**:

- **Velocità**: ~2 ordini di magnitudine più veloce dei predecessori.
- **Whole-genome**: scalabile a genomi batterici interi (Mb).
- **ARG output**: utile per metodi che inferiscono la storia di ricombinazione.
- **Benchmark standard** per metodi di inferenza filogenetica batterica.

**Granularità del modello biologico**:

- Coalescente neutrale + gene conversion (omologa).
- Niente HGT non-omologo (no transformation di geni nuovi, no transduction).
- Niente selezione, niente fenotipo, niente ecologia.
- Niente fagi, niente difese, niente comunicazione.

**Caso d'uso tipico**: generare dataset sintetici di genomi batterici con storia di ricombinazione nota, per validare phylogenetic reconstruction tools (ClonalFrame, ChromoPainter, fastGEAR, ecc.).

---

## 5. Arkea — persistent evolutionary sandbox

**Differenza fondamentale**: Arkea **non è un batch simulator**. Non produce un dump finale a fine simulazione; produce un *processo persistente* che gira 24/7, accessibile in tempo reale via web UI, con un audit log strutturato che registra ogni evento tipizzato (HGT per canale, lisi, error catastrophe, bacteriocin kill, ecc.).

**Modello**:

- Forward-time, individual-based, fenotipo emergente da composizione di **11 tipi di domini** (substrate-binding, catalytic, transmembrane, channel, energy-coupling, DNA-binding, regulator-output, ligand-sensor, structural-fold, surface-tag, repair-fidelity).
- Genoma codonico parsato in geni → domini → tratti.
- Metabolismo Michaelis–Menten su **13 metaboliti** con cicli C/N/S/Fe/H₂ chiusi.
- Quattro canali HGT distinti (coniugazione plasmidica, trasformazione naturale, trasduzione laterale, infezione fagica) con biologia-aderente: entry-exclusion via inc-group, triade competence ComEC/ComEA/ComX-like, R-M con bypass via metilazione (Arber–Dussoix).
- Ciclo fagico chiuso: SOS induction → lytic burst → virion decay → re-infection con switch cI/cro emergente.
- Quorum sensing 4D gaussiano (LuxR/AHL-like).
- Bacteriocine con kin-recognition warfare.
- Xenobiotici con RAS β-lactamase-driven feedback.
- Phase model intra-biotopo (surface/water column/sediment/biofilm) + mixing events Poissoniani.
- Migrazione inter-biotopo con world graph.

**Punti di forza** (vs. il trio sopra):

- **Multi-mechanism end-to-end**: nessun altro simulatore copre simultaneamente metabolism + HGT a 4 canali + phage cycle + R-M + QS + bacteriocins + xenobiotics + biomass continua.
- **Calibrazione tracciata**: ogni costante numerica del modello è ancorata a letteratura primaria con range biologico esplicito (vedi `04-CALIBRATION.md`). Il pubblico target sono microbiologi, e il documento di calibrazione esiste apposta per essere fact-checked.
- **Audit log tipizzato**: 15 tipi di eventi distinti (`:transformation_event`, `:rm_digestion`, `:phage_infection`, `:transduction_event`, `:plasmid_displaced`, `:bacteriocin_kill`, ecc.), persistiti in PostgreSQL con payload JSON tipizzato. Possibilità di forensic queries SQL / esportare CSV.
- **UI interattiva**: Phoenix LiveView server-authoritative, scena SVG live, phylogeny tree, time-series, HGT ledger Sankey-like, Chemistry heatmap. Bundle JS ≈ 50 KB.
- **Persistenza**: simulazione resilient cross-restart (snapshot + WAL su PostgreSQL). Multi-tenant: ogni player progetta il suo *Arkeon* seed, colonizza biotopi, osserva 24/7.
- **Disciplina**: tick puro-funzionale, deterministicamente riproducibile dal seed RNG. Property tests (133 properties, 601 test). Audit log dal giorno 1.

**Limiti deliberati** (vs. il trio sopra):

- **Genome scale**: Arkea modella un genoma RNA-virus-scale (L ≈ 50 geni), non un genoma batterico realistico (E. coli L ≈ 4.6 × 10⁶ bp). Scelta di design per compute compactness, esplicita in `04-CALIBRATION.md`. Conseguenza: il critical µ di Eigen è raggiungibile, *in linea di principio*, con mutator strain estremi — anche se in pratica `mu_per_cell ≤ 0.04` lascia il sistema lontano dalla soglia.
- **No nucleotide sequence**: il genoma è codonico ma le sequenze non sono mappate a basi A/C/G/T. Non puoi eseguire phylogenetic reconstruction su FASTA reali. **Per benchmarking di tool filogenetici, usa SimBac**.
- **No ABC inference**: Arkea non è progettato come motore di simulazione per stima parametrica likelihood-free. **Per quello, usa Bacmeta**.
- **No selezione scriptabile generale**: la selezione emerge dal modello biologico fissato (metabolismo, predazione, warfare). Non puoi configurare "questo locus ha s = 0.1 e h = 0.5" come fai in SLiM. **Per scenario evolutivi astratti general-purpose, usa SLiM**.
- **No eco-evo tra specie diverse**: Arkea simula un dominio fissato (proto-batteri). Niente predator–prey con organismi multicellulari, niente speciazione macro-evolutiva. **Per quello, SLiM 4 multispecies**.

---

## 6. Tabella comparativa

| Dimensione | SLiM | Bacmeta | SimBac | Arkea |
|---|---|---|---|---|
| **Direzione del tempo** | Forward | Forward | Backward (coalescent) | Forward (persistente) |
| **Granularità** | Individuo + locus | Wright-Fisher + sequenza | Genealogia + ARG | Individuo + dominio fenotipico |
| **Selezione** | Scriptabile, generale | Neutrale | Neutrale | Emergente da biologia fissa |
| **Genoma rappresentato come** | Cromosoma neutro + loci selezionati | Sequenza esplicita + isole | Sequenza intera | Codoni → 11 domini funzionali |
| **HGT** | Custom Eidos | Migrazione di isole | Ricombinazione omologa | 4 canali biologici espliciti |
| **R-M defenses** | No | No | No | Sì (con metilazione Arber–Dussoix) |
| **Ciclo fagico** | No | No | No | Sì (lytic/lysogeny + cI/cro) |
| **Quorum sensing** | No | No | No | Sì (4D Gaussian receptor matching) |
| **Bacteriocine** | No | No | No | Sì (kin-recognition warfare) |
| **Metabolismo** | No (fitness scalare) | No | No | Michaelis–Menten 13 metaboliti |
| **Cicli biogeochimici** | No | No | No | C/N/S/Fe/H₂ chiusi |
| **Xenobiotici / RAS** | No (scriptabile) | No | No | Sì (β-lattamasi feedback) |
| **Spazio / phase model** | Scriptabile | Rete metapopulazione | No | Surface/water/sediment/biofilm + migration graph |
| **Output** | File (VCF, tree-seq, custom) | DNA + distance + summaries | FASTA + ARG | Audit log persistente + LiveView |
| **Modalità d'uso** | Batch script | Batch CLI | Batch CLI | Interattivo 24/7 |
| **UI** | SLiMgui (debug) | Nessuna | Nessuna | Phoenix LiveView (web) |
| **Linguaggio scripting** | Eidos (R-like) | Input file | Input file | Nessuno (modello fissato) |
| **Performance scale** | 10⁵–10⁷ individui | Cluster-scale metapops | Whole genome × 10³ samples | 10²–10⁴ cellule × 10⁰–10² biotopi 24/7 |
| **Calibrazione su letteratura** | A carico utente | Implicita (modello neutro) | Implicita | Esplicita in `04-CALIBRATION.md` |
| **Pubblico target** | Pop-gen researcher | ABC inference researcher | Bacterial-phylo benchmarker | Microbiologo / studente / curioso esperto |
| **Licenza** | GPL-3.0 | BSD-3 | GPL | GPL-3.0 |

---

## 7. Quando scegliere quale strumento

**Scegli SLiM se**:
- Devi modellare uno scenario evolutivo astratto (selezione di un allele, sweep, balancing, struttura demografica complessa).
- Vuoi un genoma con coefficienti di selezione espliciti.
- Hai bisogno di tree-sequence recording per analisi successive in `tskit` / `pyslim`.
- Devi simulare popolazioni grandi (10⁵+) per molti tick.

**Scegli Bacmeta se**:
- Hai dati di sequenze reali e vuoi inferire parametri di metapopolazione (mutation rate, migration rate) via ABC.
- Ti basta neutral evolution con genomic islands (proxy per chromosome + accessory).
- Hai accesso a un cluster e vuoi parallelizzare migliaia di run.

**Scegli SimBac se**:
- Stai validando un metodo di inferenza filogenetica batterica e ti servono genomi simulati con ricombinazione omologa nota.
- Ti serve un ARG esplicito per benchmarking di metodi che ricostruiscono storie di ricombinazione.
- Lavori a scala whole-genome (Mb).

**Scegli Arkea se**:
- Vuoi *osservare* l'evoluzione microbica come fenomeno emergente, in tempo reale, senza setup di scripting.
- Ti interessa la coevoluzione tra HGT, predazione fagica, R-M, warfare bacteriocinico, quorum sensing — *insieme*, non isolati.
- Sei un microbiologo / docente / studente che vuole un sandbox per generare hypothesis qualitative o per insegnamento.
- Vuoi un audit log forensico di ogni evento HGT, ogni lisi, ogni mutazione notabile, da interrogare via SQL o LiveView.

I quattro tool sono **complementari, non competitivi**. Un workflow tipico realistic in un laboratorio computazionale potrebbe essere: usare Arkea per esplorare qualitativamente uno scenario e generare hypothesis → riprodurre il dynamic critico in SLiM con coefficienti di selezione precisi → simulare dataset di genomi reali in SimBac → validare phylogenetic reconstruction → inferire parametri reali in Bacmeta.

---

## 8. Quadro più ampio (oltre i tre tool target)

Per completezza, il panorama include anche:

- **Avida** (Adami, Ofria) — *digital organisms* in cui le istruzioni di un linguaggio assembly-like sono il "genoma". Estremamente astratto, focus su evolution di programmi auto-replicanti. Distante da Arkea per granularità biologica.
- **Aevol** (Knibbe, Beslon, Liard) — genoma astratto con strutture funzionali emergenti, modello eco-evolutivo. Parente più vicino di Arkea concettualmente, ma senza HGT esplicito multi-canale e senza UI interattiva.
- **Karr et al. whole-cell *Mycoplasma genitalium*** — modellizzazione bottom-up di una singola cellula con tutte le sue 525 ORF. Non è una sandbox evolutiva ma il riferimento high-water-mark per realismo intra-cellulare.
- **CARsim**, **AvidaED**, **EvoLudo** — strumenti didattici di evolution, più semplici e meno espressivi del trio target.

Arkea si colloca nello spazio *Aevol-adjacent* in termini di granularità (genoma generativo, fenotipo emergente da composizione) ma estende sostanzialmente verso il dominio batterico realistico: HGT a 4 canali, ciclo fagico chiuso, R-M, QS 4D, metabolismo Michaelis–Menten su 13 metaboliti chiusi, phase model. È inoltre l'unico, in questo panorama, ad essere *persistente con UI live-interactive* su stack Elixir/Phoenix.

---

## 9. Riferimenti primari

- **Haller BC, Messer PW**. *SLiM 3: Forward Genetic Simulations Beyond the Wright–Fisher Model*. Mol Biol Evol 2019, 36(3):632–637. doi:10.1093/molbev/msy228
- **Haller BC, Messer PW**. *SLiM 4: Multispecies Eco-Evolutionary Modeling*. Am Nat 2023, 201(5):E127–E139.
- **Sipola A, Marttinen P, Corander J**. *Bacmeta: simulator for genomic evolution in bacterial metapopulations*. Bioinformatics 2018, 34(13):2308–2310. doi:10.1093/bioinformatics/bty093
- **Brown T, Didelot X, Wilson DJ, De Maio N**. *SimBac: simulation of whole bacterial genomes with homologous recombination*. Microb Genom 2016, 2(1):e000044. doi:10.1099/mgen.0.000044
- **De Maio N, Wilson DJ**. *The Bacterial Sequential Markov Coalescent*. Genetics 2017, 206(1):333–343.
- **Knibbe C, Beslon G, Liard V** (Aevol). *Aevol: a digital evolution platform*. Articoli vari, 2007+.
- **Karr JR et al.** *A whole-cell computational model predicts phenotype from genotype*. Cell 2012, 150(2):389–401.

Per la calibrazione di Arkea contro letteratura primaria di microbiologia (Wommack & Colwell, Cox, Imlay, Eigen, Bull, Hawver, Stams, Tock & Dryden, Chen, Cascales, Novick, Johnston, Cooper & Brown, ecc.), vedi [`04-CALIBRATION.md`](04-CALIBRATION.md).
