> 🇮🇹 [Italiano](12-COMPARATIVE-ANALYSIS.md) · 🇬🇧 English (this page)

# Comparative analysis — Arkea vs. SLiM, Bacmeta, SimBac

**Date**: 2026-05-08
**Scope**: position Arkea relative to the three most representative simulators in the contemporary scientific landscape for population evolution (SLiM, the *de facto* population-genetics standard) and bacterial population evolution (Bacmeta, SimBac). The goal is not competition: it is clarity on *what Arkea does that the others do not*, and — equally important — *what it does not do* (and why it does not replace the existing tools for the tasks they were designed for).

---

## 1. Methodological premise

The four simulators compared here occupy *different niches* in the scientific landscape:

- **SLiM** is a *general population-genetics framework* — the user writes the model in Eidos.
- **Bacmeta** is a *neutral-evolution simulator for bacterial metapopulations* — focused on statistical inference.
- **SimBac** is a *coalescent simulator of whole bacterial genomes* — focused on benchmarking phylogenetic methods.
- **Arkea** is a *persistent evolutionary sandbox of proto-bacterial organisms* — focused on interactive observation and teaching.

Comparing them on a single scale would be misleading. What follows is a *qualitative comparison along significant dimensions*, not a performance benchmark.

---

## 2. SLiM — population genetics framework

**Primary reference**: Haller BC, Messer PW. *SLiM 3: Forward Genetic Simulations Beyond the Wright–Fisher Model*. Mol Biol Evol 2019. Current version: SLiM 4 (Haller & Messer 2023, multispecies eco-evolutionary modelling).

**Model**: forward-time, individual-based, with non-overlapping or overlapping generations. The user specifies the genome (chromosome map, mutations of neutral / positive / negative type with selection coefficients and dominance), the demographic structure (populations with K, m migration rates, K-bottlenecks) and the events (Eidos blocks fired at specific ticks).

**Strengths**:

- **Extremely general**: with Eidos you can model epistasis, frequency-dependent selection, mate choice, social structure, any evolutionary regime that can be described.
- **Performance**: optimised for whole chromosomes and large populations (10⁵–10⁷ individuals).
- **Tree-sequence recording**: integration with `tskit` for exact genealogical reconstruction.
- **Scriptable GUI**: SLiMgui for interactive debugging.
- **Literature**: hundreds of papers published with SLiM, mature ecosystem.

**Granularity of the biological model**: the genome is a *neutral sequence with selected loci*. Mutations have scalar fitness effects. There is no concept of *gene function*: fitness emerges from the coefficients the user assigns.

**Limits for the bacterial domain**:

- No native HGT. The user must simulate conjugation/transformation/transduction as *custom events* via Eidos.
- No R-M defences, no phage cycle, no quorum sensing, no bacteriocins. All re-encodable, but at the cost of scripting.
- Metabolism not modelled. Fitness is a scalar, not emergent from chemistry.
- Multi-cellular / biofilm: requires custom spatial modelling.

---

## 3. Bacmeta — neutral metapopulation evolution

**Primary reference**: Sipola A, Marttinen P, Corander J. *Bacmeta: simulator for genomic evolution in bacterial metapopulations*. Bioinformatics 2018, 34(13):2308–2310.

**Model**: forward-time, Wright–Fisher on a network of connected populations, with explicit genome per strain. Migration between populations with a freely specified connectivity matrix.

**Strengths**:

- **Designed for likelihood-free inference**: output engineered for ABC (Approximate Bayesian Computation).
- **Genomic islands**: the genome is composed of independent regions (proxy for chromosome + secondary chromosomes / plasmids).
- **Cluster-friendly**: textual input, produces DNA sequences + pairwise distances + event counts.
- **Performant C++ implementation**.

**Granularity of the biological model**:

- Strictly **neutral evolution**: no selection, no fitness differential.
- Point mutations on an explicit sequence.
- HGT modelled as exchange of genomic islands between connected populations (a simplification of conjugation + lateral transfer).
- No phenotype, no metabolism, no defences, no phages.

**Typical use case**: estimate the parameters of a metapopulation (mutation rate, migration rate, recombination rate) by comparing simulated summary statistics with real data.

---

## 4. SimBac — coalescent whole-genome bacterial simulator

**Primary reference**: Brown T, Didelot X, Wilson DJ, De Maio N. *SimBac: simulation of whole bacterial genomes with homologous recombination*. Microb Genom 2016, 2(1):e000044.

**Model**: backward-time (coalescent) with ancestral recombination graph (ARG). Simulates clonal coalescence + gene conversion (homologous recombination). Supports both within-species and between-species recombination.

**Strengths**:

- **Speed**: ~2 orders of magnitude faster than predecessors.
- **Whole-genome**: scales to entire bacterial genomes (Mb).
- **ARG output**: useful for methods that infer recombination history.
- **Standard benchmark** for bacterial-phylogeny inference methods.

**Granularity of the biological model**:

- Neutral coalescent + gene conversion (homologous).
- No non-homologous HGT (no transformation of new genes, no transduction).
- No selection, no phenotype, no ecology.
- No phages, no defences, no communication.

**Typical use case**: generate synthetic bacterial-genome datasets with known recombination history, to validate phylogenetic reconstruction tools (ClonalFrame, ChromoPainter, fastGEAR, etc.).

---

## 5. Arkea — persistent evolutionary sandbox

**Fundamental difference**: Arkea **is not a batch simulator**. It does not produce an end-of-run dump; it produces a *persistent process* that runs 24/7, accessible in real time via a web UI, with a structured audit log that records every typed event (HGT per channel, lysis, error catastrophe, bacteriocin kill, etc.).

**Model**:

- Forward-time, individual-based, phenotype emergent from composition of **11 domain types** (substrate-binding, catalytic, transmembrane, channel, energy-coupling, DNA-binding, regulator-output, ligand-sensor, structural-fold, surface-tag, repair-fidelity).
- Codon-based genome parsed into genes → domains → traits.
- Michaelis–Menten metabolism over **13 metabolites** with closed C/N/S/Fe/H₂ cycles.
- Four distinct HGT channels (plasmid conjugation, natural transformation, lateral transduction, phage infection) with biology-faithful gating: inc-group entry exclusion, ComEC/ComEA/ComX-like competence triad, R-M with bypass via host methylation (Arber–Dussoix).
- Closed phage cycle: SOS induction → lytic burst → virion decay → re-infection with emergent cI/cro switch.
- 4D Gaussian quorum sensing (LuxR/AHL-like).
- Bacteriocins with kin-recognition warfare.
- Xenobiotics with β-lactamase-driven RAS feedback.
- Intra-biotope phase model (surface / water column / sediment / biofilm) + Poissonian mixing events.
- Inter-biotope migration via world graph.

**Strengths** (vs. the trio above):

- **Multi-mechanism end-to-end**: no other simulator covers metabolism + 4-channel HGT + phage cycle + R-M + QS + bacteriocins + xenobiotics + continuous biomass simultaneously.
- **Tracked calibration**: every numeric constant in the model is anchored to primary literature with an explicit biological range (see `04-CALIBRATION.en.md`). The target audience are microbiologists, and the calibration document exists precisely so it can be fact-checked.
- **Typed audit log**: 15 distinct event types (`:transformation_event`, `:rm_digestion`, `:phage_infection`, `:transduction_event`, `:plasmid_displaced`, `:bacteriocin_kill`, etc.), persisted to PostgreSQL with typed JSON payloads. Forensic SQL queries / CSV export.
- **Interactive UI**: server-authoritative Phoenix LiveView, live SVG scene, phylogeny tree, time-series, HGT ledger, Chemistry heatmap. JS bundle ≈ 50 KB.
- **Persistence**: simulation resilient across restarts (snapshot + WAL on PostgreSQL). Multi-tenant: each player designs their *Arkeon* seed, colonises biotopes, observes 24/7.
- **Discipline**: pure-functional tick, deterministically reproducible from the RNG seed. Property tests (133 properties, 601 tests). Audit log from day one.

**Deliberate limits** (vs. the trio above):

- **Genome scale**: Arkea models an RNA-virus-scale genome (L ≈ 50 genes), not a realistic bacterial genome (E. coli L ≈ 4.6 × 10⁶ bp). A design choice for compute compactness, made explicit in `04-CALIBRATION.en.md`. Consequence: the Eigen critical µ is reachable, *in principle*, with extreme mutator strains — although in practice `mu_per_cell ≤ 0.04` keeps the system far below the threshold.
- **No nucleotide sequence**: the genome is codon-based but the sequences do not map to A/C/G/T bases. You cannot run phylogenetic reconstruction on real FASTA. **For benchmarking phylogenetic tools, use SimBac**.
- **No ABC inference**: Arkea is not designed as a simulation engine for likelihood-free parameter estimation. **For that, use Bacmeta**.
- **No general scriptable selection**: selection emerges from the fixed biological model (metabolism, predation, warfare). You cannot configure "this locus has s = 0.1 and h = 0.5" the way you do in SLiM. **For abstract general-purpose evolutionary scenarios, use SLiM**.
- **No multi-species eco-evo**: Arkea simulates a fixed domain (proto-bacteria). No predator–prey with multicellular organisms, no macro-evolutionary speciation. **For that, SLiM 4 multispecies**.

---

## 6. Comparative table

| Dimension | SLiM | Bacmeta | SimBac | Arkea |
|---|---|---|---|---|
| **Time direction** | Forward | Forward | Backward (coalescent) | Forward (persistent) |
| **Granularity** | Individual + locus | Wright-Fisher + sequence | Genealogy + ARG | Individual + phenotype domain |
| **Selection** | Scriptable, general | Neutral | Neutral | Emergent from fixed biology |
| **Genome representation** | Neutral chromosome + selected loci | Explicit sequence + islands | Whole sequence | Codons → 11 functional domains |
| **HGT** | Custom Eidos | Island migration | Homologous recombination | 4 explicit biological channels |
| **R-M defences** | No | No | No | Yes (with Arber–Dussoix methylation) |
| **Phage cycle** | No | No | No | Yes (lytic/lysogeny + cI/cro) |
| **Quorum sensing** | No | No | No | Yes (4D Gaussian receptor matching) |
| **Bacteriocins** | No | No | No | Yes (kin-recognition warfare) |
| **Metabolism** | No (scalar fitness) | No | No | Michaelis–Menten over 13 metabolites |
| **Biogeochemical cycles** | No | No | No | Closed C/N/S/Fe/H₂ |
| **Xenobiotics / RAS** | No (scriptable) | No | No | Yes (β-lactamase feedback) |
| **Space / phase model** | Scriptable | Metapopulation network | No | Surface/water/sediment/biofilm + migration graph |
| **Output** | Files (VCF, tree-seq, custom) | DNA + distance + summaries | FASTA + ARG | Persistent audit log + LiveView |
| **Usage mode** | Batch script | Batch CLI | Batch CLI | Interactive 24/7 |
| **UI** | SLiMgui (debug) | None | None | Phoenix LiveView (web) |
| **Scripting language** | Eidos (R-like) | Input file | Input file | None (model fixed) |
| **Performance scale** | 10⁵–10⁷ individuals | Cluster-scale metapops | Whole genome × 10³ samples | 10²–10⁴ cells × 10⁰–10² biotopes 24/7 |
| **Calibration on literature** | User's responsibility | Implicit (neutral model) | Implicit | Explicit in `04-CALIBRATION.en.md` |
| **Target audience** | Pop-gen researcher | ABC inference researcher | Bacterial-phylo benchmarker | Microbiologist / student / expert hobbyist |
| **Licence** | GPL-3.0 | BSD-3 | GPL | GPL-3.0 |

---

## 7. When to choose which tool

**Choose SLiM if**:
- You need to model an abstract evolutionary scenario (allele selection, sweep, balancing, complex demographic structure).
- You want a genome with explicit selection coefficients.
- You need tree-sequence recording for downstream `tskit` / `pyslim` analysis.
- You need to simulate large populations (10⁵+) for many ticks.

**Choose Bacmeta if**:
- You have real sequence data and want to infer metapopulation parameters (mutation rate, migration rate) via ABC.
- Neutral evolution with genomic islands (proxy for chromosome + accessory) is enough for you.
- You have cluster access and want to parallelise thousands of runs.

**Choose SimBac if**:
- You are validating a bacterial-phylogeny inference method and need simulated genomes with known homologous recombination.
- You need an explicit ARG for benchmarking methods that reconstruct recombination history.
- You work at whole-genome scale (Mb).

**Choose Arkea if**:
- You want to *observe* microbial evolution as an emergent phenomenon, in real time, without scripting setup.
- You are interested in coevolution among HGT, phage predation, R-M, bacteriocin warfare, quorum sensing — *together*, not in isolation.
- You are a microbiologist / lecturer / student who wants a sandbox to generate qualitative hypotheses or for teaching.
- You want a forensic audit log of every HGT event, every lysis, every notable mutation, queryable via SQL or LiveView.

The four tools are **complementary, not competing**. A realistic workflow in a computational lab might be: use Arkea to qualitatively explore a scenario and generate hypotheses → reproduce the critical dynamic in SLiM with precise selection coefficients → simulate real-genome datasets in SimBac → validate phylogenetic reconstruction → infer real parameters in Bacmeta.

---

## 8. The wider landscape (beyond the three target tools)

For completeness, the landscape also includes:

- **Avida** (Adami, Ofria) — *digital organisms* in which the instructions of an assembly-like language are the "genome". Extremely abstract, focus on the evolution of self-replicating programs. Distant from Arkea in biological granularity.
- **Aevol** (Knibbe, Beslon, Liard) — abstract genome with emergent functional structures, eco-evolutionary model. The closest conceptual relative of Arkea, but without explicit multi-channel HGT and without an interactive UI.
- **Karr et al. whole-cell *Mycoplasma genitalium*** — bottom-up modelling of a single cell with all its 525 ORFs. Not an evolutionary sandbox but the high-water-mark reference for intracellular realism.
- **CARsim**, **AvidaED**, **EvoLudo** — teaching-oriented evolution tools, simpler and less expressive than the target trio.

Arkea sits in the *Aevol-adjacent* space in terms of granularity (generative genome, phenotype emergent from composition) but extends substantially toward the realistic bacterial domain: 4-channel HGT, closed phage cycle, R-M, 4D QS, Michaelis–Menten metabolism over 13 closed metabolites, phase model. It is also the only tool in this landscape that is *persistent with a live-interactive UI* on an Elixir/Phoenix stack.

---

## 9. Primary references

- **Haller BC, Messer PW**. *SLiM 3: Forward Genetic Simulations Beyond the Wright–Fisher Model*. Mol Biol Evol 2019, 36(3):632–637. doi:10.1093/molbev/msy228
- **Haller BC, Messer PW**. *SLiM 4: Multispecies Eco-Evolutionary Modeling*. Am Nat 2023, 201(5):E127–E139.
- **Sipola A, Marttinen P, Corander J**. *Bacmeta: simulator for genomic evolution in bacterial metapopulations*. Bioinformatics 2018, 34(13):2308–2310. doi:10.1093/bioinformatics/bty093
- **Brown T, Didelot X, Wilson DJ, De Maio N**. *SimBac: simulation of whole bacterial genomes with homologous recombination*. Microb Genom 2016, 2(1):e000044. doi:10.1099/mgen.0.000044
- **De Maio N, Wilson DJ**. *The Bacterial Sequential Markov Coalescent*. Genetics 2017, 206(1):333–343.
- **Knibbe C, Beslon G, Liard V** (Aevol). *Aevol: a digital evolution platform*. Various papers, 2007+.
- **Karr JR et al.** *A whole-cell computational model predicts phenotype from genotype*. Cell 2012, 150(2):389–401.

For Arkea's calibration against primary microbiology literature (Wommack & Colwell, Cox, Imlay, Eigen, Bull, Hawver, Stams, Tock & Dryden, Chen, Cascales, Novick, Johnston, Cooper & Brown, etc.), see [`04-CALIBRATION.en.md`](04-CALIBRATION.en.md).
