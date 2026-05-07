# Revisione scientifica end-to-end del modello biologico Arkea (round 2)

**Reviewer**: biological-realism-reviewer (microbiologia / biologia molecolare)
**Data**: 2026-05-06
**Stato implementativo analizzato**: Fasi 0-20 consolidate, post `04-CALIBRATION.md`
**Documenti di riferimento**: `01-DESIGN.md`, `04-CALIBRATION.md`, `02-DESIGN_STRESS-TEST.md`, `05-BIOLOGICAL-MODEL-REVIEW.md` (round 1, piano)
**Documento parallelo**: `10-DESIGN-COHERENCE-REVIEW.md` (coerenza implementazione ↔ design)

---

## 1. Executive summary

Il modello Arkea, alla luce dei documenti di design e dello stato del codice in `arkea/lib/arkea/sim/*`, è **biologicamente difendibile end-to-end** per un pubblico di microbiologi *purché* l'utente entri sapendo che ha davanti un **individual-based evolutionary sandbox a livello di architettura cellulare + metabolismo pathway-level** (la framing di `04-CALIBRATION.md` è quella giusta). La maggior parte dei meccanismi è generative-only (composizione di domini), i loop chiusi principali (SOS → induction → arms-race; mutator → error catastrophe; cross-feeding → syntrophy) tengono qualitativamente, e le costanti recenti post-Phase-20 si avvicinano molto agli ordini di grandezza in vivo.

**Cosa è solido**: tassonomia degli 11 domini, architettura del genoma, framework R-M con bypass via metilazione (Arber-Dussoix corretto), error catastrophe come barriera Eigen, ciclo fagico chiuso (induction → burst → decay → infection → R-M → lytic/lysogenic), aerobic boost post-Phase-20, ROS-coupled DNA damage, derivazione del repressor_strength.

**Cosa è debole** (vedi findings 🟡): toxicity model O₂/H₂S/lattato è qualitativamente corretto ma misclassifica termodinamicamente la "detoxify reduction" su H₂S; alcuni vincoli stechiometrici di Block-18 cross-feeding non sono mass-balanced; il "detoxify gate" è binary (catalase = bypass totale) anziché un fattore continuo Vmax/Km della catalasi.

**Cosa è pericoloso (fa figura ma è sbagliato)** (findings 🔴):
- `:ribosome_like` pinned a `1.0` è un *flag implicito non derivato dal genoma* che viola Blocco 5;
- `derive_repressor_strength` fallback a `0.5` per cassette senza `:dna_binding` produce equilibrio non-biologico (un fago `cI−` dovrebbe essere obbligato litico, non lisogenico al 60%);
- la formula `Mutator.error_catastrophe_lethality` ha una shape funzionale che non aderisce strettamente al criterio Eigen quando `µ × L >> 1` (saturazione più rapida del reale).

**Verdetto Livello-3**: un microbiologo molecolare aprendo Arkea oggi riconoscerebbe immediatamente *operoni-like, σ-stress, induction profagica RecA-mediated, R-M con immune escape, β-lattamasi-driven RAS, AHL-like QS, Black-Queen via cross-feeding*. **Inarcherebbe il sopracciglio** su: (a) ribosome_like baseline, (b) detoxify enzyme come gate booleano vs Vmax kinetics, (c) transduction probability default 0.05 (3 ordini di magnitudine sopra Chen 2018), (d) struttura di repressor_strength (mean di binding_affinity dei dna_binding, non un cI/cro switch).

Voto qualitativo complessivo: **B+/A-**. Pronto a essere mostrato; le criticità 🔴 sono sistemabili in 1–2 sprint senza riscrivere architettura.

---

## 2. Findings per meccanismo

Severity legend:
- 🔴 **Critical** — errore biologico, viola un principio dichiarato del design o un fatto non controverso della letteratura.
- 🟡 **Moderate** — semplificazione discutibile da motivare in `04-CALIBRATION.md` o da raffinare.
- 🟢 **Minor** — refinement opportunistico, non urgente.

### 2.1 HGT — quattro canali

#### 🟢 Coniugazione (`hgt.ex`)

Il rate `0.005` baseline + `(1.0 + donor_bonus + recipient_bonus)` modulator + `n_donor × n_recip / n_total²` è la classica formulazione mass-action density-dependent. Cap `0.30` plausibile per F-plasmid in liquid culture ad alta densità (Levin et al., *Genetics* 1979; Smillie 2011 *Nature*). La `compatibility` deriva da entry-exclusion, qui semplificata a `inc_group` dell'incoming = inc_group del residente → *displacement*: corretto modello Novick 1987 (esistono >30 famiglie inc note in Enterobacteriaceae, Arkea ne usa 7 — semplificazione dichiarata in CALIBRATION).

**Plausibile**.

**🟡 Concerns**:
- `recipient_has_plasmid?/2` blocca la coniugazione se il ricevente ha già un plasmide dello *stesso* inc_group del donatore. Biologicamente questa è la semantica di "entry exclusion" (Sf via TraS/TraT), ma in vivo l'entry-exclusion non è inc-driven ma encoded da geni specifici sulle pili. Il modello **collassa due concetti distinti** (incompatibility ≠ entry exclusion). Per il pubblico target è OK in v1, ma meritava una nota in `04-CALIBRATION.md` (Novick 1987 specifica esplicitamente che incompatibility è solo replication-control, non un blocco di ingresso).

#### 🟡 Trasformazione (`hgt/channel/transformation.ex`)

Triade competence (`:channel_pore + :transmembrane_anchor + :ligand_sensor`) con threshold 0.10 è ben mappata sul circuito ComEC/ComEA + pseudopilus + ComX/cAMP-like (Johnston et al., *Nat Rev Microbiol* 2014). Naïve genomes a 0.0 = competence non default — corretto (Streptococcus, Bacillus, Haemophilus sono naturalmente competenti, E. coli K-12 *non lo è*).

**Concerns**:
- `@uptake_base = 0.0006` con la nota "calibrato per visibilità in canary" è 2–3 ordini di magnitudine **sopra** il rate biologico (10⁻⁵ a 10⁻⁷ per cell/gen, Johnston 2014). `04-CALIBRATION.md` lo dichiara onestamente. ✅ accettabile.
- **Ricombinazione strettamente posizionale** (gene a indice *i* del donor sostituisce gene a indice *i* del recipient): è un'ulteriore semplificazione, in vivo la ricombinazione è guidata da omologia di sequenza, non da posizione cromosomale. Per il livello di astrazione B+C va bene, ma ha una **conseguenza non desiderata**: il codice non distingue fra "donor e recipient hanno omologia all'indice i" e "donor e recipient hanno geni completamente diversi all'indice i ma comunque i ranges combaciano". In pratica ogni evento di trasformazione *certamente* sostituisce un gene con un altro che potrebbe non avere alcuna relazione filogenetica. Suggerimento: gating supplementare via codon-Hamming distance fra `donor[i]` e `recipient[i]` per evitare gene-replacement chimerici totali (riproduce minimum-MTF homology length ~30 bp di RecA-like recombinase).

#### 🔴 Trasduzione generalizzata (`phage.ex` + `@transduction_probability`)

Il default `0.05` (per burst!) è **3 ordini di magnitudine sopra il rate in vivo** (10⁻⁶–10⁻³ per phage particle, Chen et al. 2018 *Science*, lateral transduction). Lo store a `Application.compile_env` con override realistic `0.001` *a livello di config* è una buona scelta operativa, ma bisogna essere espliciti che il *default* in canary genera trasduzione 50× più frequente del reale. `CALIBRATION` lo dichiara.

**Suggerimento**: il default dovrebbe essere riportato a `0.005` (2 ordini di magnitudine sopra reale, non 3). 0.05 produce un canary in cui dopo qualche centinaio di tick metà delle lineage hanno scambiato qualcosa per trasduzione — biologicamente irrealistico anche per uno sandbox, e un microbiologo lo noterebbe analizzando il filogenetico. Reference: Chen et al., *Science* 2018, doi:10.1126/science.aat5867.

#### 🟢 Infezione fagica + R-M

Il flusso `infection_step → receptor_match? → restriction_check_virion → lytic/lysogenic decision` riproduce la pipeline canonica di entry. Il fix Phase-20 al `receptor_match?` (`:phage_receptor in surface_tags`) è **biologicamente corretto** — pre-Phase-20 la fallback era inversa. Buon catch.

**🟡 Concerns**:
- `derive_repressor_strength/1` defaulta a `0.5` per cassette senza dna_binding domains. Biologicamente, una cassette senza repressore CI **non può lisogenizzare** (il fago λ senza CI è obbligato litico). Default `0.5` significa che il 60% di virion senza repressore lisogenizzano comunque. Suggerimento: default `0.0` per cassette `dna_binding == []` → `p_lytic = 1.0` (always lytic), che è la fenomenologia λ`cI−` documentata.
- Il `@lytic_decision_base = 0.40` con la formula `min(1.0, 0.40 × (1 − repressor) × 2.0)` produce p_lytic=0.0 per repressor=1.0 e p_lytic=0.8 per repressor=0.0 — il valore massimo non raggiunge mai 1.0, contraddicendo la nota "alta repressione → lisogenia stabile, bassa repressione → lisi totale". Andrebbe almeno `min(1.0, 0.5 × (1-repressor) × 2.0)` per saturare a `p_lytic=1.0` quando repressor=0.

#### 🟢 Burst size e decay virion

`burst_size = capsid_copies × 6` con clamp [10, 500] è ben centrato sul range Wommack & Colwell 2000 (avg 185 marine phages, range 10–500).

`@base_decay = 0.20/tick + age_decay 0.05/tick` dà un'aspettativa ~3–5 tick di vita per virione, coerente con Suttle 1994 a tick≈ore. ✅

### 2.2 Ciclo fagico — coerenza del loop chiuso

#### 🟢 SOS ↔ induction loop

Il path `step_dna_damage → sos_active? (≥0.20) → induction_step → @sos_induction_amplifier × 3` è il cascading corretto: in vivo RecA* lega LexA *e simultaneamente* il repressore CI di λ → cleavage di entrambi → induzione + mutator (Cox 2000). Arkea modellizza il *risultato* di questa convergenza moltiplicando la probabilità di induzione per 3 quando SOS attiva, anziché simulare la dimerizzazione RecA*. **Per il livello di astrazione è perfetto**.

Reference primaria: Sassanfar & Roberts 1990, *MGG* — LexA cleavage detected within minutes after DNA damage.

#### 🟡 ROS → DNA damage → SOS (Phase 20)

`Mutator.ros_damage_increment(toxicity_factor) = 0.05 × (1 - toxicity_factor)` — quando un anaerobio-obbligato (no detoxify per O₂) sta in fase ossica, accumula damage anche in stationary phase. Imlay 2008 supporta questo: oxidative DNA damage (8-oxo-dG, Fpg lesions, DSBs) è *replication-independent* sotto stress ROS.

**Concerns**: il modello attuale fa coupling direttamente con il `toxicity_factor` complessivo, non solo con la frazione attribuibile ad O₂. Se H₂S è il dominante non-detoxified, il damage incrementale viene comunque attribuito a "ROS". H₂S in vivo non è ROS-driven (è binding inibitorio sul citocromo, non Fenton). Suggerimento: factor il damage per metabolita (`ros_damage_increment(o2_factor) + cytochrome_inhibition_increment(h2s_factor)`) anche se il numerical effect resta lo stesso, almeno per un microbiologo che legga il codice non c'è merge spurio.

### 2.3 Metabolismo (`metabolism.ex`)

#### 🟢 Michaelis-Menten + 13 metaboliti

L'enumerazione esatta dei 13 metaboliti del Blocco 6 è rispettata, gli ATP coefficient sono qualitativamente corretti (glucose=2.0 fermentation baseline, h2=1.0 chemiolitotrofia, h2s=0.6 sulfide oxidation, iron=0.3 acidofili). Il refactor Phase-20 con `aerobic_boost_factor` 1+7×oxygen_share porta glucose a effettivamente ~16 ATP a piena ossigenazione, vs textbook 32. La nota "conservativo (8× max effective vs 16× textbook)" è ragionevole (in vivo l'efficienza P/O ratio è ~2.5, non 3, e la respirazione perde ~30% in proton leak).

**🟢 Plausibile**.

#### 🟡 Cross-feeding closure (`@byproducts`)

```
glucose → 0.5 acetate + 0.3 co2 + 0.2 h2     (Σ = 1.0 in mass-eq)
acetate → 0.8 co2                            (Σ = 0.8)
lactate → 0.4 acetate + 0.4 co2 + 0.2 h2     (Σ = 1.0)
ch4 → 0.9 co2                                (Σ = 0.9)
co2 → 0.1 ch4                                (Σ = 0.1)
so4 → 0.7 h2s
h2s → 0.7 so4
nh3 → 0.7 no3
no3 → 0.5 nh3 + 0.3 co2                      (Σ = 0.8)
```

**Concerns**:
- Il glucosio mixed-acid fermentation in *E. coli* (la baseline che Arkea sembra simulare con questi coefficienti) produce in realtà una distribuzione più variabile: 0.4 acetate, 0.06 lactate (!), 0.3 succinate, 0.5 ethanol, 1.5 formate (poi disproporzionato in CO₂ + H₂). I coefficienti scelti sono **una semplificazione plausibile** ma il rapporto acetate:CO₂:H₂ = 5:3:2 per glucosio rappresenta più una respirazione partial che una vera mixed-acid. Per il livello B+C è comunque accettabile.
- `no3 → 0.5 nh3 + 0.3 co2`: il prodotto è denitrificazione+ammonificazione, ma la stechiometria è ambigua. La denitrificazione canonica è NO₃⁻ → NO₂⁻ → NO → N₂O → N₂ (con N₂ gassoso). DNRA (dissimilatory nitrate reduction to ammonium) è un'altra via che effettivamente produce NH₃. Avere entrambe collassate in un unico coefficient produce una "denitrificazione" che paradossalmente ricicla N nello stesso biotopo invece di rimuoverlo come N₂.
  - **Suggerimento**: aggiungere atom `:n2` a 14ª posizione del catalogo, o esplicitare che nh3 è un "cycle proxy" che include sia il flux DNRA che il pool atmosferico.
- `co2 → 0.1 ch4` rappresenta autotrophic methanogenesis senza H₂ (irrealistico — CO₂ + 4H₂ → CH₄ + 2H₂O è la reazione). Il coefficient così com'è permette una metanogenesi de-novo senza H₂ uptake parallelo, che selezionerebbe metanogeni autosufficienti senza obbligo di H₂ partner. Il pubblico esperto noterebbe.

#### 🔴 Toxicity model — "detoxify reduction" non termodinamico

Il `detoxify_targets` richiede `:catalytic_site(reaction_class: :reduction)` co-locato con un `:substrate_binding` su un metabolita tossico. Ma:
- **O₂ via catalasi**: 2 H₂O₂ → 2 H₂O + O₂. Catalase "reduce" il perossido, non riduce O₂ direttamente. SOD invece dismuta O₂⁻. Per Arkea dichiarare `:reduction` come reaction_class che *protegge* da O₂ è un compresso accettabile (la risultante è che la cellula sta meglio in ossico), ma terminologicamente confuso.
- **H₂S via SQR**: sulfide è *ossidato* (donatore di elettroni) a S⁰ o SO₃²⁻. Arkea pretende che la stessa `reduction` reaction_class protegga da H₂S. Lo dichiari nel commento di `detoxify_targets/1` ("Real enzymology is more nuanced... Arkea collapses both donor- and acceptor-side enzymatic detoxification into one categorical pattern") — ma è un compresso significativo per un pubblico esperto.
- **Lattato**: il commento lo paragona a lactate dehydrogenase (NAD-driven, qualifica come :oxidation di lattato → piruvato in vivo). Anche qui il `reaction_class :reduction` non è la chimica reale.

**Suggerimento per v2** (non bloccante): generalizzare a `reaction_class :detoxification` come categoria propria (è un *terzo* tipo di catalytic site oltre reduction/oxidation/hydrolysis/etc.), oppure permettere a *qualsiasi* `reaction_class` di matchare quando substrate_binding ha target tossico. Il livello di astrazione lo permette; la nomenclatura attuale è didatticamente fuorviante.

### 2.4 Mutazione e error catastrophe (`mutator.ex`)

#### 🟢 Mutation type weights

70% sub / 15% indel / 8% dup / 5% inv / 2% transl rispetta gli ordini di magnitudine biologici (Foster 2007 *Crit Rev Biochem Mol Biol*), con la nota giusta che il 2% di traslocazioni è il "motore principale dell'innovazione vera" (Blocco 7) e che il duplication weight è dinamico via `Intergenic.duplication_bonus` (intergenic repeat_array → bias che si autoamplifica con riarrangiamenti, biologicamente plausibile per *insertion sequences*).

#### 🔴 Error catastrophe lethality formula

```elixir
def error_catastrophe_lethality(mu, genome_size) do
  product = mu * genome_size
  if product <= 1.0, do: 0.0, else: ...
    share = (product - 1.0) / genome_size
    raw = 1.0 - :math.pow(1.0 - share, genome_size)
end
```

Il criterio di Eigen è: fitness sostenibile richiede `(1 - µ_per_site)^L > 1/σ`, dove σ è il selection coefficient della master sequence. Il "soft boundary" di Arkea calcola `share = (µL − 1)/L` (la *frazione di mutazioni in eccesso* sopra la critical threshold) e poi calcola `1 - (1 - share)^L`.

**Problema**: questa formula non è la lethality probability di Eigen. È una rinormalizzazione che produce una saturazione **molto più rapida** del reale. Esempio: `µ = 0.30`, `L = 50` (50 geni di un genoma Arkea ipotetico):
- `product = 15.0`, `share = 0.28`, `raw = 1 − (0.72)^50 ≈ 1.0` → quasi totale lethality
- Eigen vero: con selection coefficient s=2 per master, sostenibilità richiede `µ_eff < ln(s)/L ≈ 0.014`, quindi a µ=0.30 il sistema è sopra threshold per 20×, OK lethality vicina a 1, ma la *velocità* di transizione attorno alla threshold è diversa.

Il problema operativo è: per µ leggermente sopra threshold (`product = 1.5`, `share = 0.5/L`) la formula dà p_lethal ≈ 1 - (1 - 0.5/L)^L ≈ 1 - e^(-0.5) ≈ 0.39. **Plausibile in quel regime**, ma per `product = 5` la formula satura a >0.99 invece del transition più graduale di Eigen.

**Suggerimento**: usare la formula classica di Eigen quasispecies (Bull et al. 2007 *PLOS Comp Bio*):
```
µ_per_site = mu / L
fidelity = (1 - µ_per_site)^L
p_lethal = max(0, 1 - fidelity / threshold_fidelity)
```
con `threshold_fidelity = 1/σ` (σ ~2 per reasonable selection). Più aderente alla letteratura, e mostra la transizione smooth invece della saturation cliff.

Reference: Eigen 1971, *Naturwissenschaften*; RNA viruses replicate at L≈10⁴ near the error threshold.

#### 🟡 Mutator strain emergence

La struttura `µ = base_rate × (1 − repair_efficiency) × sos_mult` con sos_mult=4 fornisce un mutator-fold ~20× rispetto al wild-type a SOS attiva (4× SOS amplification × ~5× difference in repair_efficiency 0.5 → 0.1). In vivo il fold change DinB/Pol IV è 10–10⁴ × in stress-induced mutation (Galhardo et al. 2009, McKenzie 2000). **Fold conservativo** è OK per livello B+C, ma andrebbe esplicitato che mutator strains tipo *mutS/mutL* knockouts producono 100× di rate baseline anche *senza* SOS — il modello collassa SOS-induced + constitutive mutators in un unico path.

Reference: Galhardo et al. 2009 *J Bacteriol* — Pol IV is upregulated 10-fold by SOS, 2-fold by RpoS.

### 2.5 Xenobiotici e RAS (`xenobiotic.ex`, `phenotype.ex`)

#### 🔴 `:ribosome_like` pinned a 1.0

In `target_classes/1`:
```elixir
%{
  pbp_like: count_to_index(pbp),
  dna_polymerase_like: count_to_index(pol),
  ribosome_like: 1.0,             # ← magic constant
  membrane: count_to_index(membrane)
}
```

Il commento dice "every cell has ribosomes; pinned to 1.0 as a baseline to model intrinsic susceptibility to translation-targeting drugs". **Questo viola il principio Blocco 5 "tutto è codificato nel genoma, nessuno special case"**. È hardcoded; un microbiologo molecolare aprendo il codice noterebbe immediatamente che il "ribosome target" non è derivable né evolvibile.

**Conseguenza biologica**: un genoma con zero genes correlati a traduzione non riceve mai la "naturale resistenza per assenza-di-target" che invece il sistema offre per pbp_like. Uno xenobiotico aminoglicosidico avrebbe sempre effetto a piena severity.

**Suggerimento**: derivare `ribosome_like` da composizione di domini (es. count of `:structural_fold` con `multimerization_n` alto → proxy di rRNA + proteine ribosomali; oppure pinna a 0.0 e accetta che senza un "ribosome gene" categoria nuova non ci sono ribosomi modellizzati). In ogni caso non hardcode il valore.

#### 🟢 β-lattamasi e RAS chiusura

La triade `target_classes(:pbp_like) → bound_fraction Hill-like → mode_severity` + `hydrolase_capacity` × β-lattam pool degradation è il **canonical RAS feedback loop**. Test end-to-end (`xenobiotic_test.exs`) verifica che hydrolase-bearing strain detoxifica progressivamente il pool. **Plausibile**.

**🟡 Concerns**:
- `Kd = 10.0` per β-lattam in scala dimensionless: senza riferimento biologico esplicito (ampicillin Kd vs PBP3 di *E. coli* è ~0.1 µM, quindi nella scala Arkea 10.0 = 100 µM se 1 unit = 10 µM). `CALIBRATION` non lo specifica. Suggerimento: nota che la Kd è scelta per produrre MIC nell'ordine 100 unit nel pool, comparable a 100 mg/L di ampicillin in chemostato.
- `@k_degradation = 1.0e-5`: con 10⁴ cellule e hydrolase_capacity=1.0, `degradation = 10⁻⁵ × conc × 1 × 10⁴ = 0.1 × conc/tick`. Il pool si dimezza in ~7 tick. **Conservativo e plausibile** per β-lattamasi a kcat~10³ s⁻¹.

### 2.6 Bacteriocine (`bacteriocin.ex`)

#### 🟢 Producer requirement (toxin gene + immunity tag)

Il **due-prong requirement** (gene bacteriocin-shaped *e* almeno un `:surface_tag` come immunity marker) è esattamente il pattern reale: colicin E2 è always co-trascritto con cea (toxin) + cei (immunity) + cel (lysis) come unità (Cascales 2007 *MMBR*). Senza immunity, il producer si auto-distrugge in una generazione → non può fissarsi. Il modello cattura questa "kin-recognition selection" in modo elegante.

#### 🟡 Damage path through wall

`damage = conc × @damage_rate × abundance` (capped @max_damage_per_pool=0.05 per pool) applicato a `biomass.wall`, non direttamente ad abundance, è la scelta giusta per routing della morte attraverso `step_lysis`. **Consistente con il design**.

**Concerns**:
- **Time scale**: `@damage_rate = 0.005`/tick per unit conc → kill in 50–100 tick = giorni a tick≈1h. Il commento nota che colicin in vivo uccide in 30–60 min, e il design dichiara *deliberatamente lento* per "warfare cronica > acuta" (`CALIBRATION`). Va bene per il game design (un kill in un singolo tick non sarebbe gameplay), ma in un microbiologist's eye è 50× più lento del reale.
- **Specificity**: la matching è cross-immunity *qualitativa* (qualsiasi shared `:surface_tag` confer immunity). In vivo l'immunity protein è specifica per il binding domain del toxin; due colicins (E2, E3) con surface tags diversi ma immunità sovrapposte non condividono cross-protezione. Per Arkea level B+C accettabile.

### 2.7 Quorum sensing 4D (`signaling.ex`)

#### 🟢 Gaussian receptor matching

`binding_affinity = exp(-d²/(2σ²))` con `σ=4.0` in spazio 4D `[0..19]^4` produce affinity 1.0 per match perfetto, ~0.028 per max-distance. È esattamente la LuxR-AHL match curve qualitativamente: i diversi acyl chain length AHL (C4-C18) sono segnali differenti nello stesso spazio chimico, con cross-talk fra AHL adiacenti (Hawver et al. 2016 *FEMS*). La 4D signature mappa bene alle dimensioni reali dei segnali (chain length, hydroxyl/oxo modifications, side group).

#### 🟢 Density-dependence emergente

`signal pool / threshold` produce activation density-dependente *senza* threshold codificato come quorum-trigger (è il match continuum sopra threshold + decay che produce il switch). È esattamente come funziona LuxR in vivo: non c'è un "quorum threshold gene", c'è solo concentration × affinity vs cooperative binding di LuxR.

**Plausibile e ben fatto**. Il modello "comunicazione privata con σ stretto vs eavesdropping con σ largo" è una rappresentazione corretta della divergenza synthase/recettore osservata in *V. fischeri* vs *V. harveyi* dialect.

### 2.8 Cross-feeding e syntrophy (Phase 18)

#### 🟢 Closure C/N/S/Fe/H₂

I cicli stechiometrici producono syntrophy emergente come dichiarato: SO₄²⁻ riduzione → H₂S, H₂S oxidation → SO₄²⁻ riconnette i due gruppi metabolici (Stams & Plugge 2009 *Nat Rev Microbiol*). Glucose → acetate → CO₂ è la chain heterotrofo aerobio + acetate-respiratore syntrophic. Schemi corretti.

#### 🟡 `compute_byproducts` aggiunti DOPO consumo

`Tick.process_phase` aggiunge by-products *dopo* il consumo: il donor non può ri-uptake il proprio waste. Plausibile (donor è specialista che fa fermentation, partner è specialista che fa respirazione). Ma in vivo *un singolo* aerobic facoltativo *può* respirare il proprio acetate quando glucosio finisce (diauxic shift). Modellizzato? Indirettamente sì, perché al tick successivo il pool acetato è disponibile. **Va bene**.

### 2.9 Community Mode + Black Queen (Phase 19)

#### 🟢 Multi-seed provisioning

`CommunityLab.provision_community/3` con cap=3 seed simultanei è il setup per niche partitioning. La propagazione `original_seed_id` attraverso `new_child/4` permette analytics filogenetiche cross-seed senza traversare l'albero.

**Plausibile come framework**.

**🟡 Concerns**: il design del Black Queen Hypothesis (Morris et al. 2012 *mBio*) richiede che geni *costosi* siano persi da specie *non-keystone* perché altri produttori li compensano nell'environment. Arkea oggi non ha esplicito un "loss-of-function" nel mutation set se non come byproduct di indel/inversion. La syntrophy emerge ma il "leak-into-community" non è enforced (un sulfato-riduttore non perde mai i geni di sulfate-reduction perché non c'è selezione contro-mantenerli). Per testare BQH in canary serve un pulse di pressione che renda costoso un specifico gene e validare che venga perso preferenzialmente in lineage che hanno un partner producer.

### 2.10 Biomass continuo (`biomass.ex`)

#### 🟡 `wall_capability` proxy via n_transmembrane

Il `wall_capability(phenotype)` conta `n_transmembrane / 5.0` come proxy per PBP-like. Ma `n_transmembrane` è il **conteggio totale di domini :transmembrane_anchor** in tutto il proteoma — include porine, transporters, flagella, sensori chemiotattici. Conflato con PBP-specifico è impreciso: una cellula motile (alti TM da flagellum) avrebbe `wall_capability` inflato.

**Suggerimento**: il calcolo già fatto in `Phenotype.target_classes(:pbp_like)` (gene con co-occurrence `:transmembrane_anchor + :catalytic_site`) sarebbe il proxy giusto. Esporre `pbp_count` direttamente in phenotype e usarlo in `wall_capability`.

#### 🟢 `osmotic_target = 300 mOsm/L`, `tolerance = 280`

Il commento spiega il widening della tolerance band per evitare collassi di founder colonies in lake/marine layers. La banda 20–580 mOsm/L è ampia (E. coli K-12 sopravvive 100–700 mOsm/L sotto stress osmotico, ma non a piena fitness). **Trade-off di calibrazione documentato**, OK per playable simulation; un microbiologo potrebbe chiedere di disambiguare un osmotolerant generale (banda 280) da specialisti alofili (Halomonas) o oligotrofi.

### 2.11 Phase model (Block 12)

#### 🟢 Phase preferences emergent

Il `step_environment` con biofilm-relief, e `step_mixing_event` Poisson 10⁻⁴/tick (storm/turnover), modellizza l'eterogeneità intra-biotopo senza spazializzazione. Il modello è coerente.

**Plausibile**.

---

## 3. Cross-mechanism coherence — i loop chiusi

### 3.1 SOS ↔ DNA damage ↔ profago induction ↔ error catastrophe ↔ mutator strain

**Loop chiuso**: ✅ con riserva.

```
replication × (1 - repair_eff)        →  damage accumulates
toxicity_factor < 1.0                  →  ROS damage accumulates (Phase 20)
damage ≥ 0.20                          →  SOS active
SOS                                    →  µ × 4 (mutator)
SOS                                    →  induction × 3 (RecA-mediated cI cleavage)
SOS + µ↑                               →  error catastrophe risk
mutator → high µ                       →  more damage (compound)
```

**Concerns**:
- **Senza un "damage repair gene"** specifico, l'unica via di decay è `@dna_damage_decay = 0.10/tick` (constant). In vivo RecA-mediated repair è proporzionale all'expression di RecA stesso e dei mismatch repair (mutS, mutL). Arkea collassa repair_efficiency in *un singolo scalar* derivato dai `:repair_fidelity` domains. Va bene B+C, ma il loop "selezione PER repair sotto stress mutator" non è rigorosamente chiuso: la `decay_damage` non dipende da repair_efficiency. Un mutator strain selezionato per repair_efficiency basso *non* accumula danno più velocemente di un wild-type con basso replication rate, perché il decay è universale.
  - **Suggerimento**: `decay_damage(damage, repair_efficiency) = damage - 0.05 - 0.10 × repair_efficiency`. Una cellula `repair=0` decade a 0.05/tick (slow), `repair=1` decade a 0.15/tick (fast).

### 3.2 Mutator ↔ error catastrophe upper bound

**Loop**: ✅ presente. SOS → µ × 4 → error_catastrophe_lethality kicks in se µ × genome_size > 1. La barriera Eigen agisce come ceiling naturale.

**Numerical sanity**: con baseline `µ = 0.01 × (1 − 0.5) = 0.005`, sotto SOS `µ = 0.02`. Per genome_size = 50 geni, `µ × L = 1.0`, esattamente sopra threshold. Significa che un mutator strain medio (repair_eff=0.5) sotto SOS è **già al limite di Eigen**. Plausibile? In vivo per RNA viruses (L=10⁴, µ_per_site~10⁻⁴) → product=1, near threshold; per *E. coli* (L=4.6×10⁶, µ_per_site~10⁻¹⁰) → product=4.6×10⁻⁴, very far from threshold. **Arkea modellizza un genoma RNA-virus-scale**, non un genoma batterico tipico. È una scelta di design (genome compresso per compute), ma andrebbe esplicitata meglio in `CALIBRATION`.

### 3.3 Syntrophy ↔ cross-feeding ↔ Black Queen

**Loop**: ⚠️ parziale.

Cross-feeding emerge da `byproducts/1` table. Syntrophy fra sulfato-riduttori e sulfo-ossidatori funziona perché entrambi i loro substrati/prodotti compaiono nei pool. **Senza meccanismo esplicito di gene loss penalization**, però, BQH non è rigorosamente testabile.

### 3.4 Loss-of-receptor ↔ phage arms race

**Loop**: ✅ con il fix Phase-20 al `receptor_match?`. Lineage che mutano `:phage_receptor` → fuori da match → escape infection. **Plausibile e correttamente chiuso**.

---

## 4. Cosa NON è ancora modellato che dovrebbe esserlo per il pubblico target

(Esclusi gli items esplicitamente deferred a v2: CRISPR, free amino acids, organic cofactors)

### 4.1 🟡 Recombination homology gating

Trasformazione + trasduzione fanno positional replacement senza checkare che `donor[i]` e `recipient[i]` siano almeno *vagamente* simili in codoni. In vivo RecA richiede ~30 bp di omologia minima. Suggerimento concreto: in `pick_homologous_pair`, gating sulla Hamming distance fra `donor_gene.codons` e `recipient.chromosome[i].codons` < soglia (es. < 50% diversity).

### 4.2 🟡 Fitness cost del plasmide (gene-dosage trade-off)

`compute_growth_deltas_v5` applica `plasmid_burden = Σ length × copy_number × 0.3`. Ma il *beneficio* gene-dosage (più copie → più espressione di un gene resistente, es. β-lattamasi) è cablato direttamente nel survival? Andando a leggere `Phenotype.from_genome`, il `hydrolase_capacity` è `count(genes)/1.0` — non scala col copy_number. Quindi un plasmide ad alto copy_number paga il burden moltiplicato ma non trae beneficio amplificato in resistance. **Trade-off mancante**.

### 4.3 🟢 σ-factor cascade espliciti

Il design parla di "σ-factor di stress" e "programmi trascrizionali globali". Implementativamente, `dna_binding_affinity` come "σ scalar" è un proxy aggregato (mean delle binding_affinity di tutti i :dna_binding domains). Non c'è distinzione fra σ70 (housekeeping), σ32 (heat shock), σS (stationary). Un microbiologo che cerca "σS-driven response in stationary" non lo troverà come tale ma come *side-effect* di `Mutator.ros_damage_increment` quando il toxicity factor è basso.

**Suggerimento per v3**: introdurre `regulator_output` con `mode: :sigma_factor_70 | :sigma_factor_S | :sigma_factor_E | :sigma_factor_H` come tag, in modo che l'espressione condizionale a stress (es. `step_expression` consulta toxicity per gate σS-controlled genes). Per ora il σ-factor è collapsed in un singolo scalar — noted as B+C abstraction.

### 4.4 🟢 Quorum quenching enzimi

Il design prevede esplicitamente `[Substrate-binding(signature)] [Catalytic(hydrolysis)]` su segnali altrui (lactonases, AHL-acylases). Implementato? Cerco in `signaling.ex`: solo `qs_sigma_boost` lettura, nessun degrader esplicito di segnale. La `Phase.dilute/1` decade tutti i `signal_pool` uniformemente — non c'è un *enzima* che attacca uno specifico signal_key altrui. Per il livello B+C è leggera lacuna; un microbiologo vorrebbe vedere AiiA-like quorum quenching come strategia evolvibile.

### 4.5 🟡 Mismatch repair vs proofreading distinto

Il `:repair_fidelity` ha sub-tag `repair_class :: :mismatch | :proofreading | :error_prone`. `Phenotype` aggrega tutto in singolo `repair_efficiency = mean(efficiency)`. Mismatch repair (mutS/L) e proofreading (DnaQ/ε-subunit) hanno effetti diversi: mutS knock-out aumenta sostituzioni 100×, dnaQ knock-out aumenta indels 1000×. Collassati. Il design B+C giustifica, ma il mutator-fold per repair=0 sarebbe più realistico se distinto.

---

## 5. Verdetto Livello-3 — il microbiologo molecolare

### Cosa riconoscerebbe immediatamente come "reale"

1. **Operoni-style coordination** via `regulatory_block` con multi-binding sites → leggibile.
2. **σ-factor cascade come boost agli expression deltas via `dna_binding_affinity`** → riconoscibile come transcriptional regulation, anche se collassato.
3. **R-M con bypass via methylation profile** → Arber-Dussoix host-modification *correctly modeled*. Un microbiologo applauderebbe il fatto che il `methylation_profile` del donor protegga il payload nel recipient.
4. **SOS-induction-RecA-mediated cI cleavage** come amplifier 3× su induction probability quando dna_damage > threshold → **molto ben fatto**.
5. **Eigen quasispecies error catastrophe come ceiling a µ** → riconoscibile (anche se la formula numerica è stretchata, vedi 🔴 sopra).
6. **β-lattamasi-driven RAS** con hydrolysis su pool comune → canonical evolutionary scenario, **plausibile**.
7. **AHL-like 4D QS con receptor matching gaussiano** → solid; il "drift comunicativo" come meccanismo di speciazione è ben modellato.
8. **Cross-feeding closure C/N/S/Fe** → syntrophy emergente, riconoscibile come Stams & Plugge.
9. **Phage burst size 10–500 con decay 3–5 tick** → Wommack-Colwell range.
10. **Mutator strain emergence sotto SOS via DinB-amplifier 4×** → DinB-fold conservativo ma coerente.
11. **Loss-of-receptor evasion + arms race con plasmide** → Phase 20 fix corretto.

### Cosa lo farebbe inarcare il sopracciglio

1. 🔴 **`:ribosome_like = 1.0` hardcoded** — viola Blocco 5; va derivato da composizione domini o pinnato a 0 con disclaimer.
2. 🔴 **`derive_repressor_strength` defaulta 0.5 senza dna_binding** — un fago λ`cI−` dovrebbe essere obbligato litico, qui è 60% lisogenico.
3. 🔴 **Error catastrophe formula non-Eigen-aderente** — sostituire con `1 - (1 - µ_per_site)^L / threshold_fidelity`.
4. 🟡 **Detoxify reaction_class `:reduction` per H₂S/lattato** — terminologicamente fuorviante (SQR ossida sulfide, LDH ossida lattato). Generalize a `:detoxification` or accept any reaction_class on toxic substrate_binding.
5. 🟡 **Transduction probability default 0.05 per burst** — 50× il rate biologico Chen 2018; sensibile al fact-checking; default 0.005 sarebbe meno controverso.
6. 🟡 **Plasmid copy_number burden ma no gene-dosage benefit** — selection trade-off mancante per resistance amplification via copy_number alto.
7. 🟡 **Genoma N=50 geni con µ=0.02 mette il sistema sempre a Eigen threshold** — andrebbe documentato in `04-CALIBRATION.md` come "Arkea modellizza genome RNA-virus-scale, non bacterial-scale".
8. 🟢 **`wall_capability = n_transmembrane / 5`** non distingue PBP da porine — usare il `pbp_count` già calcolato.
9. 🟢 **DNA damage decay non dipende da repair_efficiency** — repair gene selection sotto SOS non opera realmente.
10. 🟢 **σ-factor cascade collapsed in unico scalar** — B+C OK ma σS-specific stress response non distinguibile da σ70 housekeeping.

### Verdetto qualitativo

**Per un microbiologo target Arkea oggi è: scientificamente onesto, dichiaratamente astratto, internamente coerente nei loop chiusi principali, con 3 errori P0 fixabili rapidamente e 7 semplificazioni P1 che meritano nota in `04-CALIBRATION.md`.** È un sandbox didatticamente difensibile per ricerca qualitativa e formazione, non un pretesto biologico per gameplay. Il fatto che ci sia un `04-CALIBRATION.md` con citazioni primarie è una scelta che lo distingue positivamente dal panorama (Avida, Aevol, Karr) e che un revisor accademico apprezzerebbe.

Stato implementativo: **A−**. Letteratura citata accuratamente.

---

## 6. Top-5 priorities (action items concreti)

| # | Severity | Modulo | Action |
|---|---|---|---|
| 1 | 🔴 P0 | `phenotype.ex:281-294` | Derivare `ribosome_like` da composizione domini (o pin a 0). Eliminare l'hardcoded `1.0`. |
| 2 | 🔴 P0 | `phage.ex:565-580` | `derive_repressor_strength` default `0.0` per cassette senza `:dna_binding` (forced lytic). |
| 3 | 🔴 P0 | `mutator.ex:289-300` | Sostituire `error_catastrophe_lethality` con la formula classica Eigen `1 - (1 - µ/L)^L / threshold_fidelity`. |
| 4 | 🟡 P1 | `phage.ex:75` | Default `@transduction_probability = 0.005` (anziché 0.05) → sopra Chen 2018 ma 1 ordine, non 3. |
| 5 | 🟡 P1 | `mutator.ex:271` | `decay_damage(damage, repair_efficiency)` — selezione PER repair sotto SOS chiusa. |

---

## 7. References primarie consultate

- Wommack KE, Colwell RR. *Virioplankton: Viruses in Aquatic Ecosystems*. MMBR 2000 — burst size 10–50 moderate, 100–500 large; avg 185 marine.
- Galhardo RS et al. *Pol IV upregulation in stress-induced mutation*. J Bacteriol 2010 — DinB ~10× SOS induction, ~2× RpoS.
- Eigen M. *Self-organization of matter and the evolution of biological macromolecules*. Naturwissenschaften 1971 — quasispecies error threshold criterion.
- Sassanfar M, Roberts JW. *Nature of the SOS-inducing signal*. JMB 1990 — LexA cleavage detected within minutes.
- Tock MR, Dryden DTF. *The biology of restriction and anti-restriction*. Curr Opin Microbiol 2005 — R-M efficiency.
- Chen J et al. *Genome hypermobility by lateral transduction*. Science 2018 — transduction rate 10⁻⁶–10⁻³.
- Cox MM. *The importance of repairing stalled replication forks*. Nature 2000 — SOS kinetics.
- Imlay JA. *Cellular defences against superoxide and H₂O₂*. Annu Rev Biochem 2008 — ROS-coupled DNA damage.
- Cascales E et al. *Colicin biology*. MMBR 2007 — colicin kill kinetics 30–60 min.
- Stams AJM, Plugge CM. *Electron transfer in syntrophic communities*. Nat Rev Microbiol 2009 — sulfate reducers, methanogens, syntrophy.
- Hawver LA et al. *Specificity and complexity in bacterial quorum-sensing*. FEMS 2016 — AHL dialect, eavesdropping, QS divergence.
- Wielgoss S et al. *Mutation rate inferred from synonymous substitutions in Lenski LTEE*. G3 2011 — *E. coli* 8.9×10⁻¹¹ per bp/gen.
- Novick RP. *Plasmid incompatibility*. Microbiol Rev 1987 — >30 inc groups in Enterobacteriaceae.
- Johnston C et al. *Bacterial transformation*. Nat Rev Microbiol 2014 — natural competence, ComEC/ComEA/ComX.
- Bull JJ et al. *Quasispecies Made Simple*. PLOS Comp Biol 2005 — accessible Eigen treatment.
- Riley MA, Wertz JE. *Bacteriocins: evolution, ecology, and application*. Annu Rev Microbiol 2002 — kin recognition warfare.
- Morris JJ et al. *The Black Queen Hypothesis*. mBio 2012 — gene loss in syntropic communities.
