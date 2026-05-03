> 🇮🇹 Italiano (questa pagina) · [🇬🇧 English](BIOLOGICAL-MODEL-REVIEW.en.md)

# Revisione scientifica del modello biologico Arkea — Piano di intervento

## Context

Arkea è una simulazione persistente di evoluzione proto-batterica per un pubblico di biologi/microbiologi (target: accuratezza scientifica reale, non flavour). Le fasi 0–11 + UI Evolution sono completate: l'infrastruttura genetica (5 mutazioni, 11 domini funzionali, lineage tracking, delta encoding), il metabolismo Michaelis-Menten su 13 metaboliti, il quorum sensing 4D gaussiano, le fasi intra-biotopo, la migrazione inter-biotopo e una **prima implementazione di HGT** (coniugazione plasmidica + induzione profago da stress) sono operativi.

Una revisione scientifica approfondita ha identificato gap che impediscono al modello di esprimere il suo design pieno (DESIGN.md Blocchi 5, 7, 8, 13). I gap si raggruppano in tre famiglie:

1. **HGT incompleto**: trasformazione naturale e trasduzione completamente assenti; ciclo fagico solo a metà (induction sì, ma niente release di virioni liberi né infection chain); R-M codificabile come domini ma non integrato come gating sui canali HGT; plasmidi senza `inc_group` né `copy_number`; audit log a schema senza write path.
2. **Pressioni selettive deboli**: tossicità specifiche (O₂ su anaerobi, H₂S su citocromi, lattato) assenti; carenze elementari (P/N/Fe/S) non vincolanti; xenobiotici/antibiotici assenti — senza questi RAS non è osservabile end-to-end e le 11 strategie metaboliche di Blocco 6 non producono nicchie distinte.
3. **Meccanismi cellulari accoppiati mancanti**: biomassa continua (membrane/wall/dna progress) assente, error catastrophe non modellato, SOS response come trigger biologicamente corretto dell'induction non implementato, operoni non espliciti, bacteriocine assenti.

L'esito atteso del piano: chiudere tutti i gap mantenendo i principi di Blocco 5 (*tutto è metabolismo, tutto è codificato nel genoma, nessun special case*), in modo che il modello esibisca i fenomeni evolutivi descritti nel walk-through "Cronache di un estuario contestato": coniugazione + selezione → resistenza, mutator strains → speciazione, profagi liberi → arms race con loss-of-receptor, trasformazione → mobilità di plasmidi non-coniugativi, error catastrophe come upper bound naturale a µ.

**Scelte chiave confermate dall'utente**:
- Scope: full review (Fasi 12–18).
- SOS: trigger via DNA damage score realistico (non più solo ATP deficit).
- Operoni: refactor dopo HGT (Fase 17), non prima.

---

## Principi guida (vincolanti per ogni fase)

- **Sim core puro**: nessun I/O nei moduli `Arkea.Sim.*`. Persistence resta delegata al Server tramite event structs ritornati dal tick puro.
- **Generative-only**: ogni nuovo trait deriva dai codoni esistenti del genoma o da co-occorrenze di domini già definiti. Nessun flag esplicito non derivabile dal genome.
- **Property tests obbligatori**: per ogni meccanismo nuovo almeno (a) un *conservation test*, (b) un *monotonicity test*, (c) un *no-special-case test* (genoma random senza i domini chiave non triggera mai il meccanismo).
- **Validazione `biological-realism-reviewer`**: prima del consolidamento (squash su master) di ogni fase, ranges parametrici devono essere validati contro letteratura primaria; se un test passa solo grazie a magic number senza derivazione → stop sul merge.
- **Coerenza DESIGN.md**: ogni modifica all'architettura biologica deve essere annotata in DESIGN.md (e DESIGN.en.md via `bilingual-docs-maintainer`).

---

## Fase 12 — Difese R-M e ciclo fagico chiuso (P0, prerequisito bloccante)

**Obiettivo**: trasformare l'attuale induction stress-driven in un ciclo fagico completo (lytic burst → virion release → free phage decay/migration → infection di recipient compatibili → integrazione lisogenica vs lisi immediata) e cablare R-M come gating uniforme su tutti i canali HGT.

### Cambi al genoma e ai dati

- `Arkea.Genome` — refactor del campo `prophages` da `[[Gene.t()]]` a `[%{genes: [Gene.t()], state: :lysogenic | :induced, repressor_strength: float()}]`. Risolve TODO esplicito a `lib/arkea/genome.ex:27`.
- `Arkea.Ecology.Phase` — promozione di `phage_pool` da `%{binary => non_neg_integer}` a `%{phage_id => %{genome: thin_genome, abundance, decay_age, surface_tag_signature}}`; aggiunta del campo `dna_pool` (per Fase 13).

### Nuovi moduli puri

- `lib/arkea/sim/hgt/defense.ex` — `restriction_check(payload_genes, recipient_genome, rng) :: {:digested | :passed, rng}`. Riusa il `signal_key` (già presente come `String.t()` nei primi 4 codoni dei domini DNA-binding) come specificità di taglio. Methylase del payload (proteine ereditate dal donor) bypassano il check se il donor condivide il signal_key (riproduce host modification di Arber-Dussoix).
- `lib/arkea/sim/hgt/phage.ex` — `lytic_burst/2` (produce virioni nel `phage_pool` + frammenti nel `dna_pool`), `infection_step/3`, `decay_step/2`. Burst size emergente dal numero di `Structural fold (multimerization_n)` del cassette.

### Integrazione tick

- Modifica a `lib/arkea/sim/hgt.ex`: `induction_step` chiama `HGT.Phage.lytic_burst` invece di `apply_lytic_burst`.
- Nuovo step `step_phage_infection/1` in `lib/arkea/sim/tick.ex`, posizionato tra `step_hgt` e `step_environment`. Per ogni virione: matching surface_tag/sub-tag con recipient → R-M check → integrazione lisogenica (prob da `repressor_strength` del cassette) o lisi immediata.
- Estensione di `step_environment` con decay del `phage_pool` (half-life ~ pochi tick, da validare con realism reviewer) e del `dna_pool`.

### Riferimenti agli existing utilities

- `Arkea.Sim.Intergenic` — i bias `oriT_site` / `integration_hotspot` esistono già; estendere con un bias `phage_attachment_site` analogo per l'infection.
- `Arkea.Sim.Phenotype.from_genome` — aggiungere campo `restriction_profile :: [signal_key]` (cache pre-calcolata per evitare O(M×N) durante il check).

### Property tests (in `test/arkea/sim/hgt/`)

- `phage_test.exs`: induzione stress-driven preserva `Σabundance + Σvirions` (massa di "informazione" conservata modulo decay rate quantificato).
- `phage_test.exs`: lineage con loss-of-receptor (Surface tag mutato fuori dal matching range) ha probabilità di infection ≈ 0; converge in fenotipo dopo N tick di pressione fagica.
- `defense_test.exs`: payload con methylase dello stesso signal_key bypassa R-M con prob ≥ 0.95; payload senza methylase è digerito con prob ≥ 0.7 quando recipient ha restriction enzyme.
- `defense_test.exs` (StreamData): genoma senza `Catalytic(hydrolysis)` adiacente a `Substrate-binding(DNA-like)` non blocca alcun payload.

### Validazione realism

- Burst size in range [10, 500] virioni/lisi (biologicamente plausibile).
- Free phage decay rate < dilution rate del biotope (i virioni persistono qualche tick).
- Probabilità di lysogeny ~ 0.1–0.4 a stress baseline, → ~0.9 lytic sotto stress alto.

### File critici toccati

- `lib/arkea/genome.ex`, `lib/arkea/ecology/phase.ex`, `lib/arkea/sim/hgt.ex`, `lib/arkea/sim/tick.ex`, `lib/arkea/sim/phenotype.ex`.
- Nuovi: `lib/arkea/sim/hgt/defense.ex`, `lib/arkea/sim/hgt/phage.ex`.

---

## Fase 13 — Trasformazione naturale (P0)

**Obiettivo**: introdurre il canale di uptake DNA libero, gated da R-M (Fase 12).

### Definizione di competenza

Trait emergente: un lineage è competente se ha co-occorrenza di `:channel_pore (selettività DNA)` + `:transmembrane_anchor` + `:ligand_sensor` su un signal_key dedicato (proxy "cAMP-like"). `Phenotype.from_genome` aggrega questi in `competence_score :: float()`.

### Nuovo modulo puro

- `lib/arkea/sim/hgt/channel/transformation.ex` — implementa il behaviour `Arkea.Sim.HGT.Channel` (vedi Fase 16 per la formalizzazione). Logica: rate ∝ competence × `phase.dna_pool[origin].abundance`. Recombination homology-directed semplificata: stesso `gene_id` nel chromosome del recipient → allelic replacement; nessuna omologia → respinto (eccetto plasmidi che si re-integrano come plasmid). R-M check prima dell'integrazione.

### Integrazione tick

- `step_hgt` orchestra in ordine: conjugation → transformation → (transduction in Fase 16) → phage_infection.
- Source del `dna_pool`: lisi fagica (Fase 12), lisi cell-wall-deficiency (Fase 14), dilution di routine (frazione ad ogni morte non-selettiva).

### Property tests

- `transformation_test.exs`: lineage con competence > soglia e dna_pool pieno acquisisce ≥ 1 evento per N tick (in media).
- Conservation: ogni transformation event consuma 1 unit di abundance dal `dna_pool`.
- R-M gating: recipient con restriction senza match → 0 acquisizioni, indipendentemente dal dna_pool size.

### Validazione realism

- Tassi di trasformazione attesi solo per genomi che mimano famiglie naturalmente competenti (Streptococcus/Bacillus/Haemophilus-like). Threshold di competenza non banalmente raggiunto da seed default.
- Rate ordine 10⁻⁵–10⁻⁷ per cell per generazione.

---

## Fase 14 — Tossicità specifiche, carenze elementari, biomassa continua (P0/P1)

**Obiettivo**: dare profondità alle pressioni selettive metaboliche e introdurre il bilancio biomassa continuo (prerequisito di error catastrophe in Fase 17).

### Cambi a moduli esistenti

- `lib/arkea/sim/metabolism.ex`: nuove funzioni pure `toxicity_factor(metabolite_pool, phenotype)` e `elemental_constraints(metabolite_pool, phenotype)`. Ogni metabolita ha `(toxicity_threshold, toxicity_target)` codificato. Effetto: kcat globale del lineage moltiplicato per `1 - max(0, [met] - threshold)/scale` se il lineage non possiede un detoxify enzyme dedicato (es. catalasi-like = `Catalytic(reduction, target=O₂)`).
- Vincoli elementari (P, N, Fe, S): floor uptake necessario per la produzione di biomassa. Sotto floor per N tick → blocco di growth (no fission).

### Nuovo modulo

- `lib/arkea/sim/biomass.ex` — pure functions per `progress(membrane | wall | dna, phenotype, metabolites)`. Difetti accumulano probabilità di lisi alla divisione.

### Cambi a Lineage

- `lib/arkea/ecology/lineage.ex` — campo `biomass :: %{membrane: 0..1, wall: 0..1, dna: 0..1}`.

### Integrazione tick

- `step_expression` consulta `biomass` per gate fission.
- Nuovo `step_lysis/1` applica lisi alla divisione (probabilità da deficit di wall/membrane/dna progress).
- `step_metabolism` applica `toxicity_factor` e `elemental_constraints` al delta di expression.

### Property tests

- `toxicity_test.exs`: lineage anaerobio (no detoxify O₂) in fase con [O₂] > 0.5 ha kcat effettivo che decresce monotonicamente con [O₂].
- `biomass_test.exs`: lineage senza PBP-like sotto pressione osmotica accumula deficit `wall` → lisi con probabilità crescente.
- `elemental_test.exs`: in fase P-limited, lineage senza trasportatore P efficiente non cresce; mutazione che riduce Km(P) ripristina la crescita.

### Validazione realism

- Costanti di tossicità entro ordini di grandezza biologici (O₂ tossico per anaerobi obbligati a > 1 µM equivalente; H₂S su citocromi conforme a letteratura).
- Calibrare con seed_scenario rivisto; canary test "seed survives 1000 ticks under default conditions".

---

## Fase 15 — Xenobiotici e RAS (P0)

**Obiettivo**: chiudere il loop "selezione → resistenza emergente". Senza questo il modello non è validabile end-to-end.

### Cambi a moduli esistenti

- `lib/arkea/ecology/phase.ex` — pool xenobiotici parallelo (canonical IDs > 12 per non rompere lookup esistenti) o `xenobiotic_pool` separato.
- `lib/arkea/sim/phenotype.ex` — campo `target_classes :: %{atom() => float()}` (abundance del target nel proteome derivata da composizione domini).

### Nuovo modulo

- `lib/arkea/sim/xenobiotic.ex` — pure module: `target_class` (`:pbp_like | :ribosome_like | :dna_polymerase_like | :membrane | :efflux_target`), `affinity (Kd)`, `mode (:cidal | :static | :mutagen)`. Effetto in expression: `[drug] × [target] / Kd` riduce funzionalità sui target. Mode `:mutagen` alza µ del lineage (DinB-like emergente).

### Resistenze emergenti

- β-lattamasi-like: `[Substrate-binding(target=xenobiotic_id)][Catalytic(hydrolysis)]` → degrada xenobiotico nel pool.
- Efflux pump: `[Substrate-binding(broad)][Channel/pore][Energy-coupling][Transmembrane]` riduce concentrazione intracellulare effettiva (campo `intracellular_xeno_factor` in phenotype).

### Integrazione tick

- Sub-step di `xenobiotic_binding/effect` dopo `step_metabolism`, prima di `step_expression`.
- `lib/arkea/sim/intervention.ex` — applica xenobiotici da player intervention.

### Property tests

- `xenobiotic_test.exs`: applicato β-lattam-like, lineage senza β-lattamasi e con PBP-like target perde fitness; con β-lattamasi guadagna selective boost.
- StreamData: dopo N tick di pressione costante, mutazioni che ripristinano fitness (Km basso su PBP, presenza β-lattamasi, alta espressione efflux) si fissano nelle survival population.
- End-to-end RAS: scenario seed con un singolo β-lattamase ancestor → fixation in < N tick sotto pressione (valore N validato vs Lenski-style timeframe).

### Validazione realism

- Tempi di emergence vs MIC vs frequenza mutazionale conformi a letteratura primaria.

---

## Fase 16 — Plasmid traits e trasduzione (P1)

**Obiettivo**: completare l'HGT con (a) refactor avanzato dei plasmidi, (b) trasduzione generalized + specialized appoggiate al ciclo fagico (Fase 12), (c) audit log write path.

### Plasmidi avanzati

- `lib/arkea/genome.ex` — refactor di `plasmids` da `[[Gene.t()]]` a `[%{genes: [Gene.t()], inc_group: integer(), copy_number: pos_integer(), oriT_present: boolean()}]` (TODO esplicito Blocco 4:21-22).
- `inc_group` derivato dai codoni di un dominio "rep_like" via hash modulo K. Plasmidi con stesso inc_group competono → solo uno sopravvive (dilution-driven displacement).
- `copy_number` derivato dal `regulatory_block` del rep_like (alta repressor binding affinity → low copy). Costo replication ∝ copy_number × gene_count, beneficio gene-dosage ∝ copy_number nell'expression.

### Trasduzione

- `lib/arkea/sim/hgt/channel/transduction.ex` — generalized: durante packaging del lytic burst, frazione (~0.3%) dei capsidi confeziona DNA cromosomiale random invece del genome virale; specialized: durante eccissione errata del profago in induction (probabilità da `:repair_class` dei domini repair del lisato), virione confeziona profago + geni adiacenti.
- Entrambe usano lo stesso flusso `phage_infection` con un payload type tag che cambia il comportamento di integrazione.

### Behaviour HGT.Channel formalizzato

- Nuovo behaviour `Arkea.Sim.HGT.Channel` con callback comuni (`donor_pool/2`, `transfer_rate/3`, `integrate/3`).
- Implementazioni: `Conjugation` (refactor dell'attuale `HGT`), `Transformation` (Fase 13), `Transduction` (questa fase), `PhageInfection` (Fase 12).

### Audit log write path

- `lib/arkea/persistence/audit_writer.ex` — handler per nuovi event: `:transformation_event`, `:transduction_event`, `:phage_infection`, `:plasmid_displaced`, `:rm_digestion`, `:bacteriocin_kill`, `:error_catastrophe_death`.
- Sim core puro emette event structs nel return del tick; `Arkea.Sim.Biotope.Server` chiama `AuditWriter.persist_async/1`. Aggregazione/batch per evitare DB explosion (HGT events possono essere migliaia/tick); campionamento adattivo se rate > soglia.

### Property tests

- `plasmid_test.exs`: due plasmidi stesso inc_group nello stesso lineage → uno solo sopravvive entro N tick.
- `plasmid_test.exs`: copy_number alto produce gene-dosage benefit ma burden ATP > soglia → trade-off osservabile (curva a campana di fitness vs copy_number).
- `transduction_test.exs`: cromosoma fragment trasdotto a recipient resistente ma compatibile per omologia produce allelic replacement con probabilità > 0.

### Validazione realism

- Tassi di transduction in range 10⁻⁶–10⁻⁸ per phage particle.

---

## Fase 17 — SOS, error catastrophe, operoni, bacteriocine (P1)

**Obiettivo**: chiudere il loop mutator strain ↔ DNA damage ↔ induction profago, introdurre l'upper bound naturale a µ (error catastrophe), refactor a operoni, introdurre bacteriocine come arms race surface_tag.

### SOS response

- `lib/arkea/sim/mutator.ex` — nuova `dna_damage_score :: float()` per lineage: `µ_attuale × N_replication × (1 - repair_efficiency)`. Accumulato come state in `Lineage`.
- SOS attiva quando dna_damage > threshold codificato in un `:ligand_sensor` "DNA-damage-like" del lineage. Effetti: (a) alza µ via DinB-like attivazione, (b) degrada repressor del profago → induction.
- **Sostituisce** il trigger ATP-deficit-only di Fase 12 con un trigger biologicamente corretto. `µ_attuale` può autoamplificarsi (mutator runaway) ma la repair efficiency selezionata blocca l'amplification.

### Error catastrophe

- `lib/arkea/sim/mutator.ex` — `error_catastrophe_check`: ogni divisione con `µ_attuale > critical_threshold` produce con probabilità `1 - (1-p_lethal)^genome_size` un offspring non-vitale. Soglia conforme a Eigen quasispecies (genome_size × error_rate ≈ 1).

### Operoni

- `lib/arkea/genome/gene.ex` — campo `operon_id :: binary | nil`.
- Nuovo modulo `lib/arkea/genome/operon.ex` con concetto di operone: geni con stesso operon_id condividono un singolo `regulatory_block` (presente solo sul primo). Espressione coordinata: kcat di tutti i geni dell'operone moltiplicato per lo stesso sigma effettivo.
- I sistemi nuovi (R-M, profago, conjugation, plasmid traits di Fase 12-16) progettati operon-ready: la migrazione a operoni espliciti è additiva e non rompe l'esistente.

### Bacteriocine

- `lib/arkea/sim/bacteriocin.ex` — composition `[Substrate-binding(target=surface_tag_class)][Catalytic(membrane_disruption=hydrolysis)]` + flag derivato `:secreted` dal `n_passes` del Transmembrane-anchor (n_passes > soglia → secreted).
- In `step_expression`: lineage con bacteriocin produce nel `phase.toxin_pool`. Effetto: lineage target con surface_tag matching subiscono `wall_progress` damage proporzionale.
- `lib/arkea/ecology/phase.ex` — nuovo `toxin_pool`.

### Property tests

- `sos_test.exs`: lineage con repair_efficiency basso e in growth attivo accumula dna_damage → induce profago con prob crescente.
- `error_catastrophe_test.exs`: lineage con µ artificialmente alzato collassa entro N tick (nessuna fixation possibile).
- `bacteriocin_test.exs`: due lineage co-residenti, uno bacteriocin-producer che target il surface_tag dell'altro → estinzione dell'altro entro N tick; mutazione del surface_tag → recovery.

### Validazione realism

- Pendenza µ vs error catastrophe vs Eigen's quasispecies threshold.
- Bacteriocin selectivity: target match deve essere stretto, non broad-spectrum.

---

## Fase 18 — Polish: cross-feeding closure, biofilm, regulator runtime, mixing (P2)

**Obiettivo**: validare osservativamente la chiusura dei cicli C/N/S/Fe; cablare i regulator_output a runtime; biofilm come switch QS-driven; mixing event Poisson.

### Cross-feeding closure

- Test integrativi: scenario con riduttori SO₄²⁻ + ossidatori H₂S nello stesso biotope produce ciclo S chiuso emergente; analoghi per C (acetato/lattato/CO₂/CH₄/H₂), N (NH₃/NO₃⁻), Fe (Fe²⁺/Fe³⁺).
- Nessun nuovo codice se i pool e flussi attuali sono sufficienti; eventuale tuning di stoichiometric coefficients in `metabolism.ex`.

### Biofilm

- Surface_tag con sub-tag derivato dal signal_key → atomi `:adhesin/:matrix/:biofilm` realmente prodotti (oggi cercati in UI ma mai generati).
- QS-driven switch: ricevitore con threshold raggiunta → matrix-secretion regulator attivato (collegato a Fase 17 regulator_output).
- Aggregazione = riduzione locale di dilution_rate per biofilm members.

### Regulator runtime

- I `:regulator_output` (oggi definiti ma non utilizzati nell'expression) finalmente partecipano al sigma del gene/operon target. Match additivo a sigma via DNA-binding adiacente che cerca operoni il cui regulatory_block matcha.

### Mixing event

- `lib/arkea/sim/migration.ex` — eventi Poisson rari (~10⁻⁴/tick) di trasferimento massivo inter-fase. Player-triggered intervention disponibile come "mixing intervention" a costo di intervention_budget.

---

## Fase 19 — Community Mode (modalità avanzata)

**Obiettivo**: estendere il *Seed Lab* in una modalità in cui il player progetta e inocula simultaneamente più Arkeon distinti nello stesso biotopo, abilitando ecologia comunitaria emergente — niche partitioning, syntrophy, cross-feeding chiuso, esclusione competitiva, Black Queen Hypothesis. Questa fase non è parte del piano core di chiusura dei gap (Fasi 12–18) ma un *unlock progressivo* costruito sopra il modello completato. Prerequisito hard: **Fase 18** (cross-feeding closure è la meccanica che rende le co-cultures non triviali — senza cicli C/N/S/Fe chiusi un singolo specialista vince per nicchia).

### Razionale biologico

In natura la stragrande maggioranza dei processi microbici interessanti (decomposizione anaerobica, nitrificazione, riduzione di solfato in catena con ossidazione di solfuri, metanogenesi syntrofica, biofilm dentale) è realizzata da *consorzi* di specie differenti. Single-species evolution riproduce drift e adaptive sweep, ma non l'ecologia microbica reale. Community Mode trasforma il player da *biologo evolutivo* in *consortium designer + evolutivo*, in linea con il target di pubblico (microbiologi/biologi molecolari).

### Cambi al data model

- `Arkea.Game.SeedLibrary` (nuovo modulo) — store player-side delle progettazioni di seed. Ogni entry: `{name, genome :: Genome.t(), description, created_at}`. Persistenza via nuova tabella Ecto `player_seeds` (player_id, name, genome_blob, description, inserted_at). Cap configurabile (default 12 seed per player).
- `Arkea.Ecology.Lineage` — aggiunta del campo `original_seed_id :: binary() | nil` propagato ai discendenti. Permette analytics cladistico ("questa lineage discende da Seed-A o Seed-B?") senza dover risalire all'albero filogenetico. `nil` per i wild residenti pre-seed.

### Multi-seed provisioning

- `lib/arkea/game/seed_lab.ex` esteso con `provision_community/3(player, biotope_id, seed_ids)`. Ogni seed crea una founder lineage indipendente (`new_founder/3`) con clade_ref_id distinto. Numero massimo di seed simultanei: `@max_community_seeds = 3` (configurabile).
- Quando il player attiva Community Mode, il selettore del seed lab passa da single-radio a multi-checkbox; UI mostra una preview comparativa dei tratti emergenti dei seed scelti (target_classes, detoxify_targets, hydrolase_capacity, competence_score, n_transmembrane → invariante per cellula).

### Gating progressivo (anti-deck-building)

Community Mode non è disponibile day-1. Si sblocca quando il player ha completato almeno *uno* dei milestone:

- **A. Endurance**: ha mantenuto un single-seed colony oltre 500 tick reali.
- **B. Mutator emergence**: in un suo biotopo, è apparso un lignaggio con `repair_efficiency < 0.2` per ≥ 10 tick (mutator strain sopravvissuto).
- **C. Successful HGT**: ha ricevuto almeno 1 evento `:hgt_transfer` o `:transformation_event` nel suo biotopo home.

I milestone sono tracciati via `player_progression` (nuovo schema: `player_id`, `endurance_unlocked_at`, `mutator_unlocked_at`, `hgt_unlocked_at`). Quando uno è soddisfatto, sblocca il "Community Designer" tab del Seed Lab. **Why**: previene che neoplayer importino diversità preconfezionata bypassando l'esperienza evolutiva. Mantiene il framing pedagogico di Arkea (l'evoluzione *deve* essere sentita prima di poter essere "ingegnerizzata" come community).

### Cambi all'UI viewport

- Color palette per founder: ogni clade_ref_id ottiene un colore stabile dall'`original_seed_id` → hash (consistent across tick). Glyph differenziato (cerchio/quadrato/triangolo) per riconoscere visivamente i 3 founder.
- Lineage board: nuovo filtro "Per founder" che raggruppa i lineage per `original_seed_id`. Mostra contributo di ogni founder alla popolazione totale del biotopo (heatmap temporale).
- Phylogenetic compact view: alberi paralleli per founder (3 alberi piccoli invece di 1 grande), evidenzia eventi HGT cross-clade come archi tratteggiati.

### Carrying capacity e lineage cap

Il cap `@lineage_cap = 100` resta. Con 3 founder, ognuno parte con 1 lineage; mutazione e HGT producono nuovi lineage che competono per gli slot. Pruning per abundance (Fase 4) gestisce naturalmente la pressione: i tre founder competono via metabolismo + cross-feeding, e *la community che vince* è quella ecologicamente robusta. Questo è il segnale di game design: **non vince chi inocula più seed, vince chi ha scelto seed complementari**.

### Audit log esteso

- Nuovo event `:community_provisioned` emesso quando un biotopo riceve > 1 seed simultaneamente. Payload: `[seed_id_1, seed_id_2, seed_id_3]`, `tick_count`.
- Nuovo event `:cross_clade_hgt` quando un evento HGT (qualsiasi canale) trasferisce materiale tra lineage con `original_seed_id` distinti. Permette analytics ops per misurare *connectedness* della community (community sane → alta connessione HGT).

### Integrazione con Fase 18

Phase 18 deve aver chiuso almeno questi due punti per Community Mode di emergere correttamente:

- **Cross-feeding stoichiometry**: scenario integrale con SO₄²⁻-riduttore + H₂S-ossidatore mostra ciclo S chiuso. Senza questo, due specialisti non si potenziano vicendevolmente.
- **Biofilm switch QS-driven**: senza biofilm, le specie sedentary non possono coesistere stabilmente in fasi a basso turnover.

I `regulator_output` runtime e mixing events di Fase 18 non sono blockers ma rifiniscono la dinamica.

### Property tests

- `community_test.exs` (nuovo): inoculo 2-seed dove seed-A produce H₂S e seed-B lo consuma → dopo N tick entrambi i founder hanno abundance > soglia (cross-feeding emergente). Senza Fase 18 questo test fallisce — è anche un canary per validare la chiusura.
- `community_test.exs`: inoculo 2-seed con phenotype identico → uno dei due viene escluso entro N tick (selezione neutra → lock-in stocastico). Verifica che multi-seed *non* trivializza la competizione.
- `seed_library_test.exs`: persistenza seed library tra restart, cap rispettato, cancellazione cascata.
- `seed_lab_test.exs` (esteso): `provision_community/3` con 3 seed crea 3 founder con clade_ref_id distinti e `original_seed_id` correttamente propagato.
- StreamData property: per ogni multi-seed inoculo, `Σ(abundance per founder)` ≤ `lineage_cap × max_abundance_per_lineage` (no inflation artificiosa di popolazione).

### Validazione realism

- **Cross-feeding rates**: scenario inoculo 2-seed (sulfato-riduttore + sulfo-ossidatore) deve raggiungere uno stato stazionario in ~10²–10³ tick, conforme ai tempi osservati per syntrophic consortia in chemostat (Stams & Plugge 2009). Il `biological-realism-reviewer` deve validare che il flusso H₂S → SO₄²⁻ è quantitativamente nel range stechiometrico.
- **Anti-monoculture invariant**: in 100 inocoli random multi-seed, almeno il 30% deve produrre community persistenti (≥ 2 founder sopravvivono ≥ 100 tick). Ratio inferiore = tuning di carrying capacity necessario.
- **HGT cross-clade rate**: con 3 founder distinti dovrebbe emergere almeno 1 evento `:cross_clade_hgt` per 50 tick in media (community non-isolate). Conforme a Smillie et al. 2011 per microbiomi naturali.

### File critici toccati

- `lib/arkea/game/seed_library.ex` (nuovo)
- `lib/arkea/game/seed_lab.ex` — `provision_community/3`
- `lib/arkea/game/player_progression.ex` (nuovo) — milestone tracking
- `lib/arkea/persistence/player_seed.ex` (nuovo schema Ecto)
- `lib/arkea/persistence/player_progression.ex` (nuovo schema Ecto)
- `lib/arkea/ecology/lineage.ex` — campo `original_seed_id`
- `lib/arkea_web/live/seed_lab_live.ex` — Community Designer tab
- `lib/arkea_web/live/sim_live.ex` — color/glyph per founder, founder filter sul lineage board
- `lib/arkea/persistence/audit_writer.ex` — handler per `:community_provisioned`, `:cross_clade_hgt`

### Migrazioni Ecto

- `player_seeds` (player_id, name, genome_blob bytea, description, inserted_at). Indice unique `(player_id, name)`.
- `player_progression` (player_id PRIMARY KEY, endurance_unlocked_at, mutator_unlocked_at, hgt_unlocked_at).
- `lineages` ALTER aggiunge `original_seed_id text NULL` con backfill `NULL` per residenti wild esistenti.

### Stima tempo

- 2 settimane di dev (UI nuova + schema + multi-seed provisioning) + 1 settimana di tests/balance/realism reviewer = ~3 settimane totali.

### Rischi specifici

- **Game-balance**: con 3 founder forti il player può creare biotopi "OP" che dominano il network. Mitigazione: il limite di intervention budget non scala con n_seeds; il throughput totale della community è limitato dal carrying capacity del biotopo.
- **Onboarding regression**: nuovi player potrebbero confondere Community Mode con la modalità standard. Mitigazione: il Community Designer è un tab *separato*, accessibile solo dopo unlock; il flusso default rimane single-seed.
- **Visualizzazione cluttered**: 3 cladi nel viewport possono diventare illeggibili. Mitigazione: density-based clustering nella scena PixiJS (cellule visualmente clusterate per founder come bande di colore separate, non particolato misto).

---

## Sequenza di esecuzione e dipendenze

```
Fase 12 (R-M + ciclo fagico) ──┬──→ Fase 13 (Trasformazione)──┐
                               └──→ Fase 16 (Plasmid+Trasd.)──┤
Fase 14 (Tossicità+biomassa) ─────→ Fase 15 (Xeno/RAS)────────┤
                                                              ├──→ Fase 17 (SOS, error cat., operoni, bact.)
                                                              │
                                                              └──→ Fase 18 (polish + chiusura cicli) ──→ Fase 19 (Community Mode)
```

- Fase 12 bloccante per 13 e 16 (Fase 13 usa il `dna_pool`; Fase 16 usa il `phage_pool` e il packaging).
- Fase 14 bloccante per 15 (xeno usano biomass per "target abundance") e 17 (error catastrophe usa biomass).
- Fase 17 dipende da 12 (SOS-induction) e 14 (error catastrophe).
- **Fase 19 dipende da Fase 18** (cross-feeding closure è prerequisito per ecologia comunitaria; senza, i tradeoff multi-seed degenerano in winner-takes-all).

Tempo stimato: 1 settimana di dev + property tests + 1 round biological-realism-reviewer per fase 12–18 = ~7 settimane. Fase 19 aggiunge ~3 settimane (UI + schema + balance) per un totale di ~10 settimane se eseguita in serie.

---

## File critici toccati (sintesi)

- `lib/arkea/genome.ex` — refactor `prophages` (Fase 12), `plasmids` (Fase 16); aggiunta `operon_id` su Gene (Fase 17).
- `lib/arkea/ecology/phase.ex` — refactor `phage_pool`, nuovi `dna_pool` (Fase 12), `xenobiotic_pool` (Fase 15), `toxin_pool` (Fase 17).
- `lib/arkea/ecology/lineage.ex` — campo `biomass`, `dna_damage_score` (Fasi 14, 17).
- `lib/arkea/sim/hgt.ex` — orchestrazione canali HGT (rifattorizzato in tutte le fasi).
- `lib/arkea/sim/tick.ex` — nuovi step `step_phage_infection`, `step_lysis`, sub-step xenobiotic.
- `lib/arkea/sim/phenotype.ex` — campi `competence_score`, `target_classes`, `restriction_profile`, `intracellular_xeno_factor`.
- `lib/arkea/sim/metabolism.ex` — `toxicity_factor`, `elemental_constraints`.
- `lib/arkea/sim/mutator.ex` — `dna_damage_score`, `error_catastrophe_check`.
- `lib/arkea/sim/migration.ex` — Poisson mixing events.
- `lib/arkea/persistence/audit_writer.ex` — handler per i nuovi event types; collegamento al sim core via Server.

### Nuovi moduli puri

- `lib/arkea/sim/hgt/defense.ex`, `lib/arkea/sim/hgt/phage.ex`, `lib/arkea/sim/hgt/channel/transformation.ex`, `lib/arkea/sim/hgt/channel/transduction.ex`, `lib/arkea/sim/hgt/channel.ex` (behaviour), `lib/arkea/sim/hgt/plasmid.ex`.
- `lib/arkea/sim/biomass.ex`, `lib/arkea/sim/xenobiotic.ex`, `lib/arkea/sim/bacteriocin.ex`.
- `lib/arkea/genome/operon.ex`.
- **Fase 19**: `lib/arkea/game/seed_library.ex`, `lib/arkea/game/player_progression.ex`, `lib/arkea/persistence/player_seed.ex`, `lib/arkea/persistence/player_progression.ex`.

---

## Verifica end-to-end

Per ogni fase:

1. **Unit + property tests passano**: `mix test` deve restare verde dopo ogni fase. Property tests StreamData con almeno 100 runs per invariante.
2. **Benchmark**: per ogni fase un test `bench_*.exs` (escluso da CI rapida) esegue 1000 tick con N=50 lineages e verifica:
   - Tempo medio per tick < 5x baseline pre-fase.
   - Memory non cresce (no leak).
   - Eventi attesi del nuovo meccanismo > 0 e < N (no zero, no spam).
3. **Canary scenario**: rieseguire lo scenario "Cronache di un estuario contestato" (DESIGN_STRESS-TEST.md) e verificare che i fenomeni narrativi attesi siano osservabili con la nuova implementazione (mutator strain, induction profago + difese RM/loss-of-receptor, anti-griefing dilution di plasmidi burdened, chimera per traslocazione).
4. **Validazione realism**: invocazione manuale del `biological-realism-reviewer` agent sul diff della fase, prima del consolidamento. Stop sul merge se: (a) un meccanismo è osservativamente "speciale" e non emerge dal genoma, (b) ranges parametrici fuori da ordini di grandezza biologicamente noti, (c) un test passa solo grazie a magic number senza derivazione.
5. **Documentazione**: aggiornare DESIGN.md con l'evoluzione del modello biologico; sincronizzare DESIGN.en.md via `bilingual-docs-maintainer` agent.
6. **Audit log integrity**: dopo Fase 16, verificare via query Postgres che ogni HGT event di un canale produca esattamente una riga `mobile_elements` con `origin_lineage_id`, `origin_biotope_id`, `created_at_tick` valorizzati.

---

## Rischi e mitigazioni

- **Combinatorial blow-up dei test**: 4 canali HGT × M tipi di defense × K stati di lineage. Mitigare con factory `HGTSituation.build/1` che istanzi scenari riproducibili.
- **`phage_pool` come stato persistente con genome**: cresce in size; mitigare con cap `@phage_pool_cap` (es. 50/fase) e prune per abundance.
- **Audit log explosion**: HGT events possono essere migliaia/tick; aggregazione batch + campionamento adattivo.
- **Performance del restriction_check**: O(M×N) per payload × recipient. Pre-calcolare `restriction_profile` per lineage come parte del `Phenotype`, cache hit-set lookup.
- **Regressioni di balance**: tossicità e carenze possono rendere il default seed troppo rigoroso → sterilità in 10 tick. Calibrare con `seed_scenario.ex` rivisto e canary test "seed survives 1000 ticks under default conditions" già menzionato sopra.

---

## Output finali attesi a piano completo

- 4 canali HGT operativi e R-M-gated, scritti uniformemente sopra `HGT.Channel` behaviour.
- Free phage persistenti con dinamica completa (decay, infection, lysogeny, induction da SOS).
- 11 strategie metaboliche differenziate da tossicità e carenze elementari.
- Xenobiotici come metaboliti speciali; RAS osservabile end-to-end.
- Operoni come unità di espressione coerenti.
- Bacteriocine e arms race surface_tag.
- Biomassa continua → lisi alla divisione → error catastrophe come upper bound naturale a µ.
- SOS response come trait emergente da DNA damage.
- Inc-group e copy_number che permettono coesistenza/displacement plasmidica.
- Audit log popolato per ogni HGT event, con origin tracking completo.
- Coerenza piena con DESIGN.md Blocchi 5, 7, 8, 13.

### Output aggiuntivo Fase 19 (Community Mode)

- Seed Library player-side persistente (cap 12 seed/player, Ecto-backed).
- Multi-seed provisioning (fino a 3 seed simultanei nello stesso biotopo).
- Gating progressivo: Community Mode si sblocca via endurance / mutator emergence / successful HGT.
- `Lineage.original_seed_id` propagato in tutta la genealogia → analytics cladistico per founder.
- UI viewport con palette colore/glyph per founder + filtro lineage board "Per founder".
- Eventi audit `:community_provisioned` e `:cross_clade_hgt`.
- Property test scenario syntrofico (sulfato-riduttore + sulfo-ossidatore) come canary di Fase 18 + 19 insieme.
