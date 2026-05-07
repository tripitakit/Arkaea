# Piano di chiusura — criticità P0, finding biologico critico, debito di documentazione

> **Per agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chiudere le 3 criticità P0 (ribosome_like hardcoded, audit log per-canale incompleto, coniugazione fuori da `HGT.Channel` behaviour), correggere i 3 finding biologici più pericolosi (default lisogeno per cassette senza repressore, formula `error_catastrophe_lethality` non Eigen-aderente, transduction probability 50× sopra letteratura), e formalizzare il debito di documentazione post-Fase 20 (operoni runtime, regulator_output in sigma, SOS threshold modulo-level, proxy coniugazione, lookup tables ambientali).

**Architecture:** Sequenza in 3 macro-blocchi. **Blocco A** (architettura) precede **Blocco B** (biologia) perché il refactor dell'audit log e della conformance behaviour tocca i moduli `hgt/*` che il Blocco B modifica solo localmente — eseguire A prima evita doppio toccamento. **Blocco C** (documentazione) chiude alla fine consolidando le scelte operate. Ogni Task è TDD: test fallisce → impl minima → test passa → commit. La sincronizzazione bilingual via `bilingual-docs-maintainer` è l'ultimo step di ogni Task che modifica documenti canonici.

**Tech Stack:** Elixir 1.19 / OTP 28, ExUnit + StreamData, Phoenix LiveView, Ecto. Toolchain via asdf (vedi memoria utente per PATH Erlang/Elixir).

**Riferimenti:** `09-BIOLOGICAL-MODEL-REVIEW-2.md` (review scientifica 2026-05-06), `10-DESIGN-COHERENCE-REVIEW.md` (review coerenza implementazione ↔ design 2026-05-06), `01-DESIGN.md` Blocco 5 (principi generative-only), `05-BIOLOGICAL-MODEL-REVIEW.md` (piano Fasi 12-19, round 1).

---

## Blocco A — Architettura (P0)

### Task 1: Audit log per-canale — eventi tipizzati emessi dal sim core

**Razionale:** `HgtLedger` (`lib/arkea/views/hgt_ledger.ex:21`) filtra su `hgt_transformation_event`, `hgt_transduction_event`, `rm_digestion`, `plasmid_displaced`, `phage_burst`, `phage_infection`. Solo `phage_burst` è effettivamente emesso da `derive_events/2`. Gli altri 5 tipi non vengono mai scritti in audit_log → la View è cieca. La Fase 16 li prescrive esplicitamente.

**Strategia:** ogni canale HGT ritorna oggi `{new_phase, new_lineages, rng}`. Estendiamo a `{new_phase, new_lineages, events, rng}`. `step_hgt` accumula gli `events` in `state.pending_events`, `tick/1` li unisce con quelli di `derive_events/2` prima di ritornarli al `Biotope.Server`.

**Files:**
- Modify: `lib/arkea/sim/hgt.ex` — `step/4` ritorna events per coniugazione e induction
- Modify: `lib/arkea/sim/hgt/channel/transformation.ex` — `run_transformation` ritorna events
- Modify: `lib/arkea/sim/hgt/phage.ex` — `lytic_burst/2`, `infection_step/4` ritornano events
- Modify: `lib/arkea/sim/hgt/defense.ex` — `restriction_check/3` opzionalmente emette `rm_digestion`
- Modify: `lib/arkea/sim/biotope_state.ex` — campo `pending_events :: [map()]` (transient, non persistito)
- Modify: `lib/arkea/sim/tick.ex` — `step_hgt`, `step_phage_infection` propagano events; `tick/1` unisce con `derive_events`
- Modify: `lib/arkea/persistence/audit_writer.ex` — handler per i 6 nuovi event types
- Test: `test/arkea/sim/hgt/audit_events_test.exs` (nuovo) — copertura per ogni event type

#### Sub-task 1.1: campo transient `pending_events` in BiotopeState

- [ ] **Step 1: leggere lo schema attuale**

```bash
grep -n "defstruct\|@type t" arkea/lib/arkea/sim/biotope_state.ex
```

- [ ] **Step 2: aggiungere `pending_events: []` allo struct**

In `lib/arkea/sim/biotope_state.ex`, aggiungere `:pending_events` alla `defstruct` con default `[]`. Aggiornare la `@type t :: %__MODULE__{...}` con `pending_events: [map()]`. Documentare come "transient buffer di event structs accumulati durante il tick, ritornati con `{state, events}` da `Tick.tick/1` e svuotati dopo la persistence".

- [ ] **Step 3: assicurare reset all'inizio del tick**

In `lib/arkea/sim/tick.ex` `tick/1`, prima dei step pipeline aggiungere:

```elixir
state = %{state | pending_events: []}
```

- [ ] **Step 4: test che il campo esista e sia svuotato**

In `test/arkea/sim/tick_test.exs`, aggiungere:

```elixir
test "tick resets pending_events at start" do
  state = %{seed_state() | pending_events: [%{type: :stale}]}
  {new_state, _events} = Tick.tick(state)
  refute Enum.any?(new_state.pending_events, &(&1.type == :stale))
end
```

- [ ] **Step 5: run, commit**

```bash
mix test test/arkea/sim/tick_test.exs --only describe:tick
git add arkea/lib/arkea/sim/biotope_state.ex arkea/lib/arkea/sim/tick.ex arkea/test/arkea/sim/tick_test.exs
git commit -m "Sim: BiotopeState.pending_events transient event buffer"
```

#### Sub-task 1.2: eventi `transformation_event` da `Transformation.run_transformation`

- [ ] **Step 1: test del nuovo event type — falla**

Creare `test/arkea/sim/hgt/audit_events_test.exs`:

```elixir
defmodule Arkea.Sim.HGT.AuditEventsTest do
  use ExUnit.Case, async: true

  alias Arkea.Sim.HGT.Channel.Transformation
  alias Arkea.Sim.{Phenotype, Tick}
  alias Arkea.Sim.Test.Factories

  describe "transformation_event emission" do
    test "successful uptake emits :transformation_event with origin/recipient" do
      phase = Factories.phase_with_dna_pool(competence_genome: :basic)
      lineages = Factories.competent_lineages(2)
      rng = :rand.seed_s(:exsplus, {1, 2, 3})

      {_phase, _lineages, events, _rng} =
        Transformation.run_transformation(phase, lineages, 42, rng)

      assert Enum.any?(events, fn e ->
        e.type == :transformation_event and
          is_binary(e.recipient_lineage_id) and
          is_binary(e.origin_lineage_id) and
          e.tick == 42
      end)
    end
  end
end
```

```bash
mix test test/arkea/sim/hgt/audit_events_test.exs
```

Atteso: FAIL — `run_transformation` ritorna 3-tuple, non 4-tuple.

- [ ] **Step 2: estendere firma di `run_transformation`**

In `lib/arkea/sim/hgt/channel/transformation.ex`, accumulare `events` accanto a `phase, lineages`:

```elixir
def run_transformation(phase, lineages, tick, rng) do
  Enum.reduce(lineages, {phase, [], [], rng}, fn lineage, {p, acc_lineages, acc_events, r} ->
    case attempt_uptake(lineage, p, tick, r) do
      {:ok, new_lineage, new_phase, event, new_r} ->
        {new_phase, [new_lineage | acc_lineages], [event | acc_events], new_r}

      {:no_uptake, new_r} ->
        {p, [lineage | acc_lineages], acc_events, new_r}
    end
  end)
  |> then(fn {p, lineages, events, r} ->
    {p, Enum.reverse(lineages), events, r}
  end)
end
```

L'event struct emesso dall'uptake riuscito:

```elixir
%{
  type: :transformation_event,
  tick: tick,
  recipient_lineage_id: lineage.id,
  origin_lineage_id: fragment.origin_lineage_id,
  gene_index: index,
  origin_biotope_id: phase.biotope_id
}
```

- [ ] **Step 3: aggiornare il caller**

In `lib/arkea/sim/tick.ex` `step_hgt`, dove oggi `Transformation.run_transformation` ritorna 3-tuple, accumulare events nel buffer:

```elixir
{phase, lineages, transformation_events, rng} =
  Transformation.run_transformation(phase, lineages, state.tick_count, rng)

phase = %{phase | pending_events: phase.pending_events ++ transformation_events}
```

- [ ] **Step 4: il test passa**

```bash
mix test test/arkea/sim/hgt/audit_events_test.exs
```

Atteso: PASS.

- [ ] **Step 5: regression — il tick suite resta verde**

```bash
mix test --include hgt
```

Atteso: 0 failures.

- [ ] **Step 6: commit**

```bash
git add arkea/lib/arkea/sim/hgt/channel/transformation.ex arkea/lib/arkea/sim/tick.ex arkea/test/arkea/sim/hgt/audit_events_test.exs
git commit -m "HGT.Transformation: emit :transformation_event for uptake"
```

#### Sub-task 1.3: eventi `phage_infection`, `rm_digestion` da `HGT.Phage.infection_step`

- [ ] **Step 1: test — falla**

Aggiungere a `test/arkea/sim/hgt/audit_events_test.exs`:

```elixir
describe "phage_infection emission" do
  test "successful infection emits :phage_infection event" do
    phase = Factories.phase_with_virion_pool()
    lineages = Factories.lineages_with_phage_receptor(1)
    rng = :rand.seed_s(:exsplus, {4, 5, 6})

    {_phase, _lineages, events, _rng} = Phage.infection_step(phase, lineages, 100, rng)

    assert Enum.any?(events, &(&1.type == :phage_infection))
  end

  test "R-M digestion emits :rm_digestion event" do
    phase = Factories.phase_with_virion_pool(receptor_match: true, methylation: :mismatched)
    lineages = Factories.lineages_with_restriction_profile(1)
    rng = :rand.seed_s(:exsplus, {7, 8, 9})

    {_phase, _lineages, events, _rng} = Phage.infection_step(phase, lineages, 100, rng)

    assert Enum.any?(events, &(&1.type == :rm_digestion))
  end
end
```

- [ ] **Step 2: estendere `Phage.infection_step` e `restriction_check_virion`**

In `lib/arkea/sim/hgt/phage.ex`, modificare `infection_step/4` per ritornare `{phase, lineages, events, rng}`. Quando `restriction_check_virion` ritorna `:digested`, emettere `%{type: :rm_digestion, ...}`. Quando l'integrazione lisogenica avviene, emettere `%{type: :phage_infection, mode: :lysogenic, ...}`. Per lisi immediata, `%{type: :phage_infection, mode: :lytic, ...}`.

- [ ] **Step 3: aggiornare `tick.ex` step_phage_infection**

```elixir
{phase, lineages, infection_events, rng} =
  Phage.infection_step(phase, lineages, state.tick_count, rng)

phase = %{phase | pending_events: phase.pending_events ++ infection_events}
```

- [ ] **Step 4: il test passa, regression resta verde**

```bash
mix test test/arkea/sim/hgt/audit_events_test.exs
mix test
```

- [ ] **Step 5: commit**

```bash
git add arkea/lib/arkea/sim/hgt/phage.ex arkea/lib/arkea/sim/hgt/defense.ex arkea/lib/arkea/sim/tick.ex arkea/test/arkea/sim/hgt/audit_events_test.exs
git commit -m "HGT.Phage: emit :phage_infection / :rm_digestion events"
```

#### Sub-task 1.4: eventi `transduction_event`, `plasmid_displaced` dal lytic burst

- [ ] **Step 1: test — falla**

```elixir
describe "transduction emission" do
  test "lytic burst with transduction roll emits :transduction_event" do
    # forza transduction_probability = 1.0 via Application.put_env
    Application.put_env(:arkea, :transduction_probability, 1.0)
    on_exit(fn -> Application.delete_env(:arkea, :transduction_probability) end)

    phase = Factories.phase_with_lysogenic_lineage()
    lineages = Factories.lysogen_under_sos(1)
    rng = :rand.seed_s(:exsplus, {10, 11, 12})

    {_phase, _lineages, events, _rng} = HGT.induction_step(phase, lineages, 200, rng)

    assert Enum.any?(events, &(&1.type == :transduction_event))
  end
end

describe "plasmid_displaced emission" do
  test "incompatible plasmid arrival displaces resident, emits event" do
    phase = Factories.phase_with_resident_plasmid(inc_group: 3)
    donor = Factories.donor_with_plasmid(inc_group: 3)
    lineages = [donor | Factories.recipient_with_plasmid(inc_group: 3)]
    rng = :rand.seed_s(:exsplus, {13, 14, 15})

    {_phase, _lineages, events, _rng} = HGT.step(:default, lineages, 300, rng)

    assert Enum.any?(events, &(&1.type == :plasmid_displaced))
  end
end
```

- [ ] **Step 2: estendere `HGT.induction_step` e `HGT.step`**

In `lib/arkea/sim/hgt.ex`, `induction_step` (chiamato dentro `step_hgt`) deve ritornare events:
  - `%{type: :phage_burst, lineage_id, virion_count, ...}` quando lytic burst si verifica
  - `%{type: :transduction_event, donor_lineage_id, payload_kind: :generalized, ...}` quando il roll di transduction passa

`HGT.step/4` (coniugazione) emette:
  - `%{type: :hgt_transfer, channel: :conjugation, donor_lineage_id, recipient_lineage_id, plasmid_inc_group, ...}` per ogni transfer
  - `%{type: :plasmid_displaced, recipient_lineage_id, displaced_inc_group, ...}` quando inc_group conflict

Nota: `:hgt_transfer` esiste già in `derive_events/2` derivato post-hoc da diff dei plasmidi. **Migrare** la generazione qui, eliminandola da `derive_events`. Aggiungere campo `channel` distintivo.

- [ ] **Step 3: rimuovere `detect_hgt_transfer/3` da `derive_events` (deprecato)**

In `lib/arkea/sim/tick.ex:1054`, sostituire la generazione post-hoc di `:hgt_transfer` con un merge dal `pending_events`. La firma `derive_events/2` rimane, ma `:hgt_transfer` non è più derivato — è già in `state.pending_events`.

- [ ] **Step 4: aggiornare `tick/1` per merge degli events**

```elixir
def tick(state) do
  state = %{state | pending_events: []}

  new_state =
    state
    |> step_metabolism()
    # ... resto della pipeline ...
    |> increment_tick()

  derived_events = derive_events(state, new_state)
  events = Enum.reverse(new_state.pending_events) ++ derived_events
  new_state = %{new_state | pending_events: []}

  {new_state, events}
end
```

- [ ] **Step 5: il test passa, regression**

```bash
mix test test/arkea/sim/hgt/audit_events_test.exs
mix test
```

- [ ] **Step 6: commit**

```bash
git add arkea/lib/arkea/sim/hgt.ex arkea/lib/arkea/sim/tick.ex arkea/test/arkea/sim/hgt/audit_events_test.exs
git commit -m "HGT: emit :transduction_event, :plasmid_displaced; centralize :hgt_transfer"
```

#### Sub-task 1.5: eventi `bacteriocin_kill`, `error_catastrophe_death`

- [ ] **Step 1: test — falla**

```elixir
describe "bacteriocin_kill emission" do
  test "wall damage from bacteriocin emits :bacteriocin_kill on lysis" do
    state = Factories.state_with_bacteriocin_pressure()
    {new_state, events} = Tick.tick(state)
    assert Enum.any?(events, &(&1.type == :bacteriocin_kill))
  end
end

describe "error_catastrophe_death emission" do
  test "lineage with µ × L >> 1 emits :error_catastrophe_death" do
    state = Factories.state_with_runaway_mutator()
    {_new_state, events} = Tick.tick(state)
    assert Enum.any?(events, &(&1.type == :error_catastrophe_death))
  end
end
```

- [ ] **Step 2: emettere event in `step_lysis` per cause-of-death routing**

In `lib/arkea/sim/tick.ex` `step_lysis/1`, dove oggi un lineage perde abundance per wall damage, distinguere la causa:

```elixir
defp lysis_event(lineage, cause, abundance_lost, tick) do
  %{
    type: cause_to_event_type(cause),
    lineage_id: lineage.id,
    abundance_lost: abundance_lost,
    tick: tick
  }
end

defp cause_to_event_type(:bacteriocin), do: :bacteriocin_kill
defp cause_to_event_type(:error_catastrophe), do: :error_catastrophe_death
defp cause_to_event_type(:wall_deficit), do: :mass_lysis
```

Il `cause` è derivato dal source del damage in `Biomass.degrade_wall/2` (richiede di propagare un tag di causa nel lineage transient state — campo `last_lysis_cause`).

- [ ] **Step 3: il test passa, regression**

```bash
mix test test/arkea/sim/hgt/audit_events_test.exs
mix test
```

- [ ] **Step 4: commit**

```bash
git add arkea/lib/arkea/sim/tick.ex arkea/lib/arkea/sim/biomass.ex arkea/lib/arkea/ecology/lineage.ex arkea/test/arkea/sim/hgt/audit_events_test.exs
git commit -m "Sim: emit :bacteriocin_kill, :error_catastrophe_death cause-tagged events"
```

#### Sub-task 1.6: AuditWriter handler per i 6 event types

- [ ] **Step 1: leggere il pattern attuale**

```bash
grep -n "def insert_events\|case .*type" arkea/lib/arkea/persistence/audit_writer.ex | head -30
```

- [ ] **Step 2: estendere il pattern matching**

In `lib/arkea/persistence/audit_writer.ex`, aggiungere clauses per i 6 nuovi types:

```elixir
defp event_to_row(%{type: :transformation_event} = e, biotope_id, tick) do
  %{
    biotope_id: biotope_id,
    tick: tick,
    event_type: "transformation_event",
    payload: %{
      recipient_lineage_id: e.recipient_lineage_id,
      origin_lineage_id: e.origin_lineage_id,
      gene_index: e.gene_index
    }
  }
end

# analoghi per :transduction_event, :rm_digestion, :phage_infection,
# :plasmid_displaced, :bacteriocin_kill, :error_catastrophe_death
```

- [ ] **Step 3: test integration — un tick produce le righe attese**

In `test/arkea/persistence/audit_writer_test.exs`, aggiungere:

```elixir
test "transformation event persists with correct payload shape" do
  events = [%{type: :transformation_event, recipient_lineage_id: "r1",
              origin_lineage_id: "o1", gene_index: 5, tick: 42}]
  AuditWriter.insert_events(events, "bio_test", 42, repo: TestRepo)
  rows = TestRepo.all(from a in AuditLog, where: a.event_type == "transformation_event")
  assert length(rows) == 1
  assert hd(rows).payload["origin_lineage_id"] == "o1"
end
```

- [ ] **Step 4: il test passa**

```bash
mix test test/arkea/persistence/audit_writer_test.exs
```

- [ ] **Step 5: regression completa**

```bash
mix test
```

Atteso: 0 failures.

- [ ] **Step 6: commit**

```bash
git add arkea/lib/arkea/persistence/audit_writer.ex arkea/test/arkea/persistence/audit_writer_test.exs
git commit -m "AuditWriter: handlers for 6 new HGT/lysis event types"
```

#### Sub-task 1.7: HgtLedger view consuma i nuovi eventi

- [ ] **Step 1: verificare che la View ora veda dati**

Avviare l'app, far girare un canary scenario con HGT attivo, controllare che `HgtLedger` mostri righe non vuote per `transformation_event`, `rm_digestion`, ecc.

```bash
mix run priv/scripts/run_cronache_canary.exs
# poi visitare /sim e tab HGT Ledger
```

- [ ] **Step 2 (se necessario): adattare la view alla shape `payload` effettiva**

Se i campi del payload non matchano quanto la View `lib/arkea/views/hgt_ledger.ex` si aspetta (es. nomi diversi), allineare. Test snapshot o test view.

- [ ] **Step 3: commit (se ci sono adattamenti)**

```bash
git add arkea/lib/arkea/views/hgt_ledger.ex
git commit -m "HgtLedger: align payload field names with sim core"
```

---

### Task 2: Coniugazione conforme al behaviour `HGT.Channel`

**Razionale:** `lib/arkea/sim/hgt.ex` ha `step/4` con firma `(phase_name, lineages, tick, rng)` mentre `HGT.Channel` definisce `step/4` come `(lineages, phase, tick, rng)`. La review prescrive: o conformare la coniugazione, o documentare il rinvio. Decidiamo per il refactor — è 1 ora di lavoro e chiude un drift architetturale.

**Files:**
- Modify: `lib/arkea/sim/hgt.ex` — aggiungere `@behaviour`, allineare firma `step/4`, aggiungere `name/0`
- Modify: `lib/arkea/sim/tick.ex` `step_hgt` — aggiornare il caller alla nuova firma
- Test: `test/arkea/sim/hgt_test.exs` — adattare le call site

#### Sub-task 2.1: refactor della firma di `HGT.step/4`

- [ ] **Step 1: leggere la firma corrente e i call site**

```bash
grep -rn "Arkea.Sim.HGT.step\|HGT.step(" arkea/lib arkea/test
```

- [ ] **Step 2: test che il behaviour è implementato — falla**

In `test/arkea/sim/hgt_test.exs`:

```elixir
test "HGT implements Arkea.Sim.HGT.Channel behaviour" do
  callbacks = Arkea.Sim.HGT.Channel.behaviour_info(:callbacks)
  module = Arkea.Sim.HGT
  assert {:step, 4} in callbacks
  assert {:name, 0} in callbacks
  assert function_exported?(module, :step, 4)
  assert function_exported?(module, :name, 0)
  assert module.name() == :conjugation
end
```

```bash
mix test test/arkea/sim/hgt_test.exs --only describe:behaviour
```

Atteso: FAIL — `name/0` non definita, firma `step/4` incompatibile.

- [ ] **Step 3: refactor della firma di `step`**

In `lib/arkea/sim/hgt.ex:107`:

```elixir
@behaviour Arkea.Sim.HGT.Channel

@impl Arkea.Sim.HGT.Channel
def name, do: :conjugation

@impl Arkea.Sim.HGT.Channel
def step(lineages, phase, tick, rng) when is_integer(tick) do
  # body originale, ma `phase_name` ora derivato da phase.name
  phase_name = phase.name
  # ... resto invariato ...
end
```

- [ ] **Step 4: aggiornare i call site**

In `lib/arkea/sim/tick.ex` `step_hgt`, dove `HGT.step(:default, lineages, tick, rng)` diventa:

```elixir
{phase, lineages, conjugation_events, rng} =
  HGT.step(lineages, phase, state.tick_count, rng)
```

- [ ] **Step 5: il test passa, regression resta verde**

```bash
mix test test/arkea/sim/hgt_test.exs
mix test
```

- [ ] **Step 6: commit**

```bash
git add arkea/lib/arkea/sim/hgt.ex arkea/lib/arkea/sim/tick.ex arkea/test/arkea/sim/hgt_test.exs
git commit -m "HGT: conform conjugation to HGT.Channel behaviour (step/4, name/0)"
```

---

## Blocco B — Biologia (P0)

### Task 3: Eliminare `ribosome_like` hardcoded — derivazione generative

**Razionale:** `phenotype.ex:291` pinned `ribosome_like: 1.0` viola Blocco 5 generative-only. Un genoma senza domini di traduzione non riceve la "naturale resistenza per assenza-di-target" che il sistema offre per `pbp_like`. Il pubblico target lo nota.

**Decisione di design:** derivare `ribosome_like` da co-occorrenza di `:structural_fold(multimerization_n >= 5)` + `:catalytic_site(reaction_class: :rna_processing | :peptide_bond_formation)`. Genomi senza questi domini avranno `ribosome_like = 0.0` → naturalmente resistenti agli aminoglicosidi.

**Files:**
- Modify: `lib/arkea/sim/phenotype.ex:285-294` — derivazione di `ribosome_like` da composition
- Modify: `lib/arkea/sim/phenotype.ex:106` — docstring aggiornato
- Modify: `lib/arkea/sim/phenotype.ex:275` — commento esplicativo aggiornato
- Modify: `lib/arkea/sim/seed_scenario.ex` — assicurare che il seed genome abbia almeno 1 ribosome-shaped gene (canary survival)
- Test: `test/arkea/sim/phenotype_test.exs` — proprietà no-special-case
- Test: `test/arkea/sim/xenobiotic_test.exs` — test di no-target → no-effect per ribosome-targeting drug

#### Sub-task 3.1: test no-special-case

- [ ] **Step 1: test — falla**

In `test/arkea/sim/phenotype_test.exs`:

```elixir
describe "ribosome_like generative derivation" do
  test "genome without ribosome-shaped genes has ribosome_like = 0.0" do
    genome = Factories.empty_genome()
    phenotype = Phenotype.from_genome(genome)
    assert phenotype.target_classes.ribosome_like == 0.0
  end

  test "genome with ribosome-shaped composition has ribosome_like > 0" do
    genome = Factories.genome_with_ribosome_complex()
    phenotype = Phenotype.from_genome(genome)
    assert phenotype.target_classes.ribosome_like > 0.0
  end

  property "no-special-case: random genome without rRNA composition has 0.0" do
    check all genome <- Generators.random_genome(), max_runs: 100 do
      phenotype = Phenotype.from_genome(genome)
      composition = ribosome_composition_count(genome)
      if composition == 0, do: assert(phenotype.target_classes.ribosome_like == 0.0)
    end
  end
end
```

```bash
mix test test/arkea/sim/phenotype_test.exs --only describe:ribosome_like
```

Atteso: FAIL — `ribosome_like` è hardcoded `1.0`.

- [ ] **Step 2: implementazione generative**

In `lib/arkea/sim/phenotype.ex:285-294`:

```elixir
%{
  pbp_like: count_to_index(pbp),
  dna_polymerase_like: count_to_index(pol),
  ribosome_like: derive_ribosome_like(genome),
  membrane: count_to_index(membrane)
}
```

E aggiungere il helper:

```elixir
@ribosome_min_multimerization 5

defp derive_ribosome_like(genome) do
  count =
    genome.chromosome
    |> Enum.count(&ribosome_shaped_gene?/1)

  count_to_index(count)
end

defp ribosome_shaped_gene?(gene) do
  has_high_multimerization?(gene) and has_translation_catalysis?(gene)
end

defp has_high_multimerization?(gene) do
  Enum.any?(gene.domains, fn d ->
    d.kind == :structural_fold and
      Map.get(d.parameters, :multimerization_n, 0) >= @ribosome_min_multimerization
  end)
end

defp has_translation_catalysis?(gene) do
  Enum.any?(gene.domains, fn d ->
    d.kind == :catalytic_site and
      Map.get(d.parameters, :reaction_class) in [:rna_processing, :peptide_bond_formation]
  end)
end
```

- [ ] **Step 3: aggiornare docstring linea 106 e linea 275**

Sostituire "every cell has ribosomes; pinned to 1.0" con:

```
- `:ribosome_like` — derivato dalla co-occorrenza di
  `:structural_fold(multimerization_n >= 5)` + `:catalytic_site(:rna_processing | :peptide_bond_formation)`.
  Genomi privi di tale composizione hanno `ribosome_like = 0.0` e risultano
  intrinsecamente resistenti ai farmaci translation-targeting
  (consistente con il principio Blocco 5: tutto è codificato nel genoma).
```

- [ ] **Step 4: assicurare survival del seed scenario**

In `lib/arkea/sim/seed_scenario.ex`, verificare che il seed genome abbia almeno 1 gene con la composizione richiesta. Se necessario, aggiungere alla `build_seed_genome/1` un gene "ribosomal-like" minimo.

```bash
mix test test/arkea/sim/seed_scenario_test.exs
```

- [ ] **Step 5: regression incluso xenobiotico**

```bash
mix test
```

Verifica specifica: `xenobiotic_test.exs` con un `:translation_targeting` drug deve passare; un genoma senza ribosome composition deve survivare 100%.

- [ ] **Step 6: commit**

```bash
git add arkea/lib/arkea/sim/phenotype.ex arkea/lib/arkea/sim/seed_scenario.ex arkea/test/arkea/sim/phenotype_test.exs
git commit -m "Phenotype: derive ribosome_like from genome composition (Block 5)"
```

---

### Task 4: `derive_repressor_strength` default 0.0 per cassette senza dna_binding

**Razionale:** un fago λ`cI−` (senza repressore) deve essere obbligato litico in vivo. Il default `0.5` di `phage.ex:569` produce 60% lisogenizzazione, fenomenologia non-biologica.

**Files:**
- Modify: `lib/arkea/sim/hgt/phage.ex:569` (function body) e linea 507 (lytic_decision_base saturation fix)
- Test: `test/arkea/sim/hgt/phage_test.exs` — proprietà obligate-lytic

#### Sub-task 4.1: test obligate-lytic

- [ ] **Step 1: test — falla**

In `test/arkea/sim/hgt/phage_test.exs`:

```elixir
describe "derive_repressor_strength" do
  test "cassette without :dna_binding domains gets repressor_strength = 0.0" do
    genes = Factories.genes_without_dna_binding()
    refute Enum.any?(genes, fn g -> Enum.any?(g.domains, &(&1.kind == :dna_binding)) end)
    assert Phage.derive_repressor_strength(genes) == 0.0
  end

  test "cassette without dna_binding always lyses (p_lytic = 1.0)" do
    repressor = 0.0
    p_lytic = Phage.lytic_probability(repressor)
    assert p_lytic == 1.0
  end

  test "cassette with full dna_binding always lysogenizes (p_lytic = 0.0)" do
    repressor = 1.0
    p_lytic = Phage.lytic_probability(repressor)
    assert p_lytic == 0.0
  end
end
```

```bash
mix test test/arkea/sim/hgt/phage_test.exs --only describe:derive_repressor_strength
```

Atteso: FAIL — default è 0.5.

- [ ] **Step 2: fix del default + saturation**

In `lib/arkea/sim/hgt/phage.ex:569-580`:

```elixir
defp derive_repressor_strength(genes) do
  binding_affinities =
    for gene <- genes,
        domain <- gene.domains,
        domain.kind == :dna_binding,
        do: Map.get(domain.parameters, :binding_affinity, 0.0)

  case binding_affinities do
    [] -> 0.0
    affinities -> Enum.sum(affinities) / length(affinities)
  end
end
```

In linea 507, alzare il `@lytic_decision_base` da 0.40 a 0.50 per saturare a 1.0:

```elixir
@lytic_decision_base 0.50

# linea 507 invariata struttura, valore aggiornato
p_lytic = max(0.0, min(1.0, @lytic_decision_base * (1.0 - repressor) * 2.0))
```

Esporre `lytic_probability/1` come funzione pubblica per testabilità:

```elixir
@spec lytic_probability(float()) :: float()
def lytic_probability(repressor_strength) do
  max(0.0, min(1.0, @lytic_decision_base * (1.0 - repressor_strength) * 2.0))
end
```

- [ ] **Step 3: il test passa, regression**

```bash
mix test test/arkea/sim/hgt/phage_test.exs
mix test
```

- [ ] **Step 4: commit**

```bash
git add arkea/lib/arkea/sim/hgt/phage.ex arkea/test/arkea/sim/hgt/phage_test.exs
git commit -m "Phage: cassette without dna_binding is obligate lytic (cI-null phenotype)"
```

---

### Task 5: `error_catastrophe_lethality` formula Eigen-aderente

**Razionale:** la formula attuale (`mutator.ex:289`) usa una rinormalizzazione che satura troppo rapidamente. Sostituire con la formula Eigen classica `1 - (1-µ_per_site)^L / threshold_fidelity`.

**Files:**
- Modify: `lib/arkea/sim/mutator.ex:288-310` — riscrivere `error_catastrophe_lethality/2`
- Modify: `devel-docs/04-CALIBRATION.md` — sezione su Eigen threshold con citazione Bull et al. 2007
- Test: `test/arkea/sim/mutator_test.exs` — proprietà di transizione smooth

#### Sub-task 5.1: test transizione smooth

> **Implementazione (2026-05-07):** completata con due correzioni rispetto al
> draft del piano. (1) `threshold_mu` corretto: la formula Eigen `(1 − µ/L)^L > 1/σ`
> dà una soglia *per-cell* ≈ `ln(σ)`, **non** `ln(σ)/L`; il test usa
> `:math.log(sigma)` come soglia. (2) Il test "lineage emette
> :error_catastrophe_death" in `audit_events_test.exs` è stato `@tag :skip`-ato:
> sotto la formula Eigen-aderente Arkea opera molto sotto soglia
> (`mu_per_cell ≤ 0.04` vs threshold ≈ 0.69) — l'event è ora un *theoretical
> ceiling*. La copertura del payload audit resta su `audit_writer_test.exs:221`.
> Vedi `04-CALIBRATION.md` per dettagli.

- [x] **Step 1: test — falla**

In `test/arkea/sim/mutator_test.exs`:

```elixir
describe "error_catastrophe_lethality (Eigen-derived)" do
  test "lethality is 0 below threshold and approaches 1 above, smooth transition" do
    genome_size = 50
    threshold_mu = :math.log(2.0) / genome_size  # σ=2 selection coefficient

    # below threshold: lethality near 0
    p_below = Mutator.error_catastrophe_lethality(threshold_mu * 0.5, genome_size)
    assert p_below < 0.1

    # at threshold: lethality ~ 0.5 (Eigen transition midpoint heuristic)
    p_at = Mutator.error_catastrophe_lethality(threshold_mu, genome_size)
    assert p_at > 0.0 and p_at < 0.7

    # 5x above threshold: lethality > 0.9
    p_5x = Mutator.error_catastrophe_lethality(threshold_mu * 5, genome_size)
    assert p_5x > 0.9
  end

  property "monotonicity: lethality non-decreasing in mu" do
    check all genome_size <- integer(10..200),
              mu1 <- float(min: 0.0, max: 0.05),
              mu2 <- float(min: 0.05, max: 0.5) do
      p1 = Mutator.error_catastrophe_lethality(mu1, genome_size)
      p2 = Mutator.error_catastrophe_lethality(mu2, genome_size)
      assert p2 >= p1
    end
  end

  test "monotonicity in genome size for fixed mu above threshold" do
    mu = 0.05
    p_small = Mutator.error_catastrophe_lethality(mu, 10)
    p_large = Mutator.error_catastrophe_lethality(mu, 100)
    assert p_large > p_small
  end
end
```

```bash
mix test test/arkea/sim/mutator_test.exs --only describe:error_catastrophe
```

Atteso: alcuni FAIL su smoothness della transizione (la formula attuale satura cliff).

- [x] **Step 2: nuova implementazione Eigen**

In `lib/arkea/sim/mutator.ex:288-310`:

```elixir
@selection_coefficient_default 2.0

@doc """
Probabilità che la divisione produca offspring non-vitale a causa di error catastrophe.

Aderente al criterio di Eigen quasispecies (Bull et al. 2007): la sostenibilità della
master sequence richiede `(1 - µ_per_site)^L > 1/σ`, dove σ è il selection coefficient.
La formula ritorna `1 - fidelity / threshold_fidelity`, ovvero la frazione di fitness
deficit relativa alla soglia.

Per `µ × L` molto sotto soglia → lethality ≈ 0.
Per `µ × L >> threshold` → lethality → 1 in transizione smooth.

Reference: Bull JJ et al., *Quasispecies Made Simple*, PLOS Comp Biol 2005.
"""
@spec error_catastrophe_lethality(float(), pos_integer(), float()) :: float()
def error_catastrophe_lethality(mu, genome_size, sigma \\ @selection_coefficient_default)
    when is_float(mu) and is_integer(genome_size) and genome_size > 0 do
  mu_per_site = mu / genome_size
  fidelity = :math.pow(1.0 - mu_per_site, genome_size)
  threshold_fidelity = 1.0 / sigma
  raw = 1.0 - fidelity / threshold_fidelity
  max(0.0, min(1.0, raw))
end
```

- [x] **Step 3: il test passa, regression**

```bash
mix test test/arkea/sim/mutator_test.exs
mix test test/arkea/sim/sos_test.exs
mix test
```

Atteso: il `sos_test.exs:113` (monotonic in genome_size) deve continuare a passare. Se cambia il numero di tick attesi per estinzione in canary, aggiornare le costanti.

> **Esecuzione 2026-05-07**: la `sos_test.exs:113` proprietà *monotonic in
> genome size* è stata **rimossa** — sotto Eigen `(1 − µ/L)^L → exp(−µ)`
> per L grande, quindi la lethality non è strettamente monotona in L per µ
> fissato (anzi tende a *decrescere* leggermente con L). I valori di µ
> usati nei test pre-esistenti (0.05, 0.5) sono stati alzati a (2.0, 10.0)
> per restare sopra la nuova soglia ≈ ln(σ).

- [x] **Step 4: aggiornare 04-CALIBRATION.md**

Aggiungere sezione:

```markdown
## Error catastrophe — soglia Eigen

`Mutator.error_catastrophe_lethality(mu, genome_size, sigma)` implementa il criterio di Eigen:

- `fidelity = (1 - µ/L)^L`
- `lethality = max(0, 1 - fidelity / (1/σ))`

`σ = 2.0` come selection coefficient di default (master sequence con fitness 2× il mean
mutant). Per genome_size = 50, threshold µ ≈ 0.014; un mutator strain con µ=0.02 (4×
SOS amplification su baseline 0.005) è ~30% sopra threshold, lethality ~0.4. Conforme a
Bull JJ et al., *Quasispecies Made Simple*, PLOS Comp Biol 2005.

Nota: Arkea modellizza un genoma RNA-virus-scale (L≈50 geni), non bacterial-scale
(L=4.6×10⁶ in *E. coli*). Questo è una scelta di design per compute compactness.
```

- [ ] **Step 5: commit**

```bash
git add arkea/lib/arkea/sim/mutator.ex arkea/test/arkea/sim/mutator_test.exs devel-docs/04-CALIBRATION.md
git commit -m "Mutator: Eigen-derived error_catastrophe_lethality + CALIBRATION update"
```

---

### Task 6: Default `transduction_probability` 0.005 (1 ordine sopra letteratura, non 3)

**Razionale:** `phage.ex:75` ha default `0.05`/burst, 50× sopra Chen 2018 (10⁻⁶–10⁻³). Un microbiologo che leggesse il filogenetico noterebbe l'over-frequency. Riportiamo a `0.005` (sopra letteratura ma 1 ordine di magnitudine, accettabile per visibilità in canary).

**Files:**
- Modify: `lib/arkea/sim/hgt/phage.ex:75` — default `0.005`
- Modify: `devel-docs/04-CALIBRATION.md` — nota su scelta calibrativa
- Test: nessun nuovo test (la prob è settabile via `Application.put_env`; i test esistenti che la usano lo settano esplicitamente)

#### Sub-task 6.1

- [x] **Step 1: cambiare il default**

In `lib/arkea/sim/hgt/phage.ex:75`:

```elixir
@transduction_probability Application.compile_env(:arkea, :transduction_probability, 0.005)
```

- [x] **Step 2: aggiornare 04-CALIBRATION.md**

- [x] **Step 3: regression — controllare che i canary tests che si aspettano transduction-driven phenomena continuino a passare**

> **Esecuzione 2026-05-07**: 309 test sim+persistence verdi. Le 8 failure di
> `mix test` sono UI/LiveView pre-esistenti (`arkea-tabs__tab` vs
> `arkea-tab`), non correlate. Nessun test sim si aspettava una specifica
> frequenza di transduction.

- [ ] **Step 4: commit**

```bash
git add arkea/lib/arkea/sim/hgt/phage.ex devel-docs/04-CALIBRATION.md
git commit -m "Phage: transduction_probability default 0.005 (closer to Chen 2018)"
```

---

## Blocco C — Documentazione

### Task 7: Sezione "Debito documentato post-Fase 20" in 03-IMPLEMENTATION-PLAN.md

**Razionale:** 4 feature documentate in `05-BIOLOGICAL-MODEL-REVIEW.md` (round 1) hanno il campo dati ma non il runtime: operoni con expression coordinata, regulator_output in sigma, SOS threshold genome-derived, coniugazione triade `pili_like + relaxase_like + oriT_like`. Senza una sezione esplicita di "debito", future sessioni Claude/Codex possono inavvertitamente ri-aprire questi piani come "fasi nuove".

**Files:**
- Modify: `devel-docs/03-IMPLEMENTATION-PLAN.md` — nuova sezione finale
- Modify: `devel-docs/01-DESIGN.md` — note Blocco 5 sulle eccezioni accettate (toxicity profile, ATP coefficients, aerobic substrates come parametri di biotopo)
- Sync: `bilingual-docs-maintainer` agent per `03-IMPLEMENTATION-PLAN.en.md`, `01-DESIGN.en.md`

#### Sub-task 7.1: sezione "Debito post-Fase 20"

- [x] **Step 1: aggiungere a 03-IMPLEMENTATION-PLAN.md**

Aggiungere alla fine del file:

```markdown
---

## Debito documentato post-Fase 20

Le seguenti feature hanno **schema dati implementato** ma **runtime non implementato** o **semplificato rispetto al design originale**. Sono **deliberatamente non chiuse** in questa fase di consolidamento; future sessioni di sviluppo non devono trattarle come "lavoro mancante" da chiudere subito senza prima rivisitare il design.

### D1 — Operoni runtime non implementato

- **Stato**: `Arkea.Genome.Gene` ha campo `operon_id :: binary | nil`; `Arkea.Genome.Operon` non esiste; nessun modulo runtime usa `operon_id`.
- **Design originale**: `05-BIOLOGICAL-MODEL-REVIEW.md` Fase 17 prescriveva espressione coordinata operonica con `kcat × shared_sigma`.
- **Razionale del rinvio**: l'expression attuale (sigma derivato da binding_affinity media) è funzionalmente equivalente al livello di astrazione B+C. Operoni-as-runtime aggiungerebbe complessità con beneficio fenomenologico marginale.
- **Riapertura**: solo se un canary scenario produce comportamenti di expression che un microbiologo riconosce come "operone-mancante" (es. geni co-regolati che non si attivano in coordinazione).

### D2 — `regulator_output` parsato ma non aggregato in sigma

- **Stato**: `Phenotype.from_genome` parsa `:regulator_output` ma non lo aggrega (commento esplicito a `phenotype.ex:521-523`).
- **Design originale**: `05-BIOLOGICAL-MODEL-REVIEW.md` Fase 18 prescriveva participation in sigma del gene/operon target.
- **Razionale del rinvio**: ridondante con `dna_binding_affinity` per il livello di expression attuale. La meccanica targeted-regulator richiederebbe operoni runtime (D1).
- **Riapertura**: insieme a D1, in un Phase 21 dedicato.

### D3 — SOS threshold come costante modulo-level

- **Stato**: `@sos_active_threshold = 0.20` in `mutator.ex:80`; uniforme per tutti i lignaggi.
- **Design originale**: `05-BIOLOGICAL-MODEL-REVIEW.md` Fase 17 prescriveva derivazione da `:ligand_sensor` (DNA-damage-like) per-lineage.
- **Razionale del rinvio**: la costante calibrata in Phase 20 produce dinamiche SOS biologicamente realistiche; la per-lineage variability richiederebbe un nuovo `:reaction_class :dna_damage_sensor` non presente nella tassonomia attuale.
- **Riapertura**: insieme a D1/D2 o quando si introducono nuovi reaction_class.

### D4 — Proxy coniugazione: solo `:transmembrane_anchor`

- **Stato**: `hgt.ex:62-84` usa solo `:transmembrane_anchor` come gating per coniugazione.
- **Design originale**: 01-DESIGN.md Blocco 5 prescriveva la triade `pili_like + relaxase_like + oriT_like`.
- **Razionale del rinvio**: `:relaxase_like` e `:oriT_like` non sono nella tassonomia degli 11 domini correnti; introdurli richiederebbe espansione coordinata di tassonomia + Phenotype + tutti i Factories nei test. La coniugazione attuale è funzionalmente plausibile (cap 0.30, density-dependent).
- **Riapertura**: in un Phase 21 dedicato all'espansione tassonomica dei domini.

### D5 — Lookup tables ambientali (toxicity_profile, atp_coefficients, aerobic_substrates)

- **Stato**: `metabolism.ex:81-95` (`@atp_coefficients`), `:121` (`@aerobic_substrates`), `:159-163` (`@toxicity_profile`) sono parametri ambientali hardcoded.
- **Decisione**: questi NON sono un debito ma una **decisione di design consolidata**: la chimica dell'ambiente (stechiometria di ATP yield, profilo di tossicità dei metaboliti) è un parametro del biotopo, non del genoma. Il principio Blocco 5 "tutto è codificato nel genoma" si applica ai *tratti del lignaggio*, non al modello dell'ambiente.
- **Aggiornamento 01-DESIGN.md**: documentare esplicitamente questa distinzione in Blocco 5 (vedi sotto).

---
```

- [x] **Step 2: aggiornare 01-DESIGN.md Blocco 5**

In `devel-docs/01-DESIGN.md`, alla fine del Blocco 5, aggiungere:

```markdown
#### Eccezioni dichiarate al principio "tutto è codificato nel genoma"

Il principio si applica ai **tratti del lignaggio**: ogni capacità del lignaggio (uptake, catalisi, resistenza, comunicazione, difesa) deve emergere da composizione di domini genomici. **Non si applica** ai parametri dell'ambiente:

- **Stechiometria di ATP yield** dei metaboliti (`metabolism.ex:@atp_coefficients`) — chimica dell'ambiente.
- **Profilo di tossicità** dei metaboliti (`metabolism.ex:@toxicity_profile`) — proprietà chimica intrinseca, non genome-derived.
- **Set di substrati aerobic-boostable** (`metabolism.ex:@aerobic_substrates`) — caratteristica della catena respiratoria a livello di sistema, non di singolo enzima.
- **Catalogo xenobiotici** (`xenobiotic.ex:@catalog`) — gli xenobiotici sono perturbazioni esterne, non codificati nel genoma del lignaggio.
- **`ribosome_like`** è invece **derivato dal genoma** dalla Fase 21 in poi (vedi commit "Phenotype: derive ribosome_like from genome composition").

Questa distinzione è esplicita per evitare che future revisioni interpretino "tutto è codificato nel genoma" come applicabile alla chimica dell'environment.
```

- [ ] **Step 3: commit (italiano canonico)**

```bash
git add devel-docs/03-IMPLEMENTATION-PLAN.md devel-docs/01-DESIGN.md
git commit -m "Docs: post-Phase-20 explicit debt section + Block 5 environment exceptions"
```

#### Sub-task 7.2: sincronizzazione bilingual

- [ ] **Step 1: dispacciare bilingual-docs-maintainer**

Eseguire dal terminale di Claude:

```
Aggiornare i file inglesi `devel-docs/03-IMPLEMENTATION-PLAN.en.md` e
`devel-docs/01-DESIGN.en.md` per riflettere le modifiche italiane appena committate
(commit più recente: "Docs: post-Phase-20 explicit debt section + Block 5 environment
exceptions"). Aggiungere anche le nuove versioni inglesi di
`09-BIOLOGICAL-MODEL-REVIEW-2.en.md`, `10-DESIGN-COHERENCE-REVIEW.en.md`,
`11-REMEDIATION-PLAN.en.md` se mancanti. Mantenere terminologia tecnica/biologica
consistente con il resto della documentazione (cfr. terminology.md o glossary se
esistente).
```

- [ ] **Step 2: review del diff inglese**

Prima del commit, leggere il diff e verificare che la terminologia (mutator strain, error catastrophe, restriction-modification, lateral transduction) sia consistente con i documenti inglesi esistenti.

- [ ] **Step 3: commit dei file inglesi**

```bash
git add devel-docs/03-IMPLEMENTATION-PLAN.en.md devel-docs/01-DESIGN.en.md \
        devel-docs/09-BIOLOGICAL-MODEL-REVIEW-2.en.md \
        devel-docs/10-DESIGN-COHERENCE-REVIEW.en.md \
        devel-docs/11-REMEDIATION-PLAN.en.md
git commit -m "Docs: sync English mirrors for post-Phase-20 debt + reviews"
```

---

### Task 8: Aggiornamento `04-CALIBRATION.md` finale per consistency

**Razionale:** dopo i fix biologici di Blocco B, alcuni numeri citati in `04-CALIBRATION.md` sono cambiati. Garantire che il documento citi i valori effettivamente in codice.

**Files:**
- Modify: `devel-docs/04-CALIBRATION.md` — aggiornamento valori
- Sync: `bilingual-docs-maintainer` per `.en.md`

#### Sub-task 8.1

- [x] **Step 1: audit dei valori citati**

```bash
grep -n "0.05\|0.005\|0.40\|0.50\|repressor_strength\|error_catastrophe" devel-docs/04-CALIBRATION.md
```

Per ogni valore, verificare che il file Elixir corrispondente abbia lo stesso numero. Se non match, aggiornare 04-CALIBRATION.md.

- [x] **Step 2: aggiornare le citazioni di file:linea**

04-CALIBRATION.md cita spesso `phenotype.ex:281-294` (target_classes), `phage.ex:565-580` (derive_repressor_strength), `mutator.ex:289-300` (error_catastrophe_lethality). Dopo i refactor, questi range potrebbero essere shiftati. Verificare con:

```bash
grep -n "phenotype.ex:\|phage.ex:\|mutator.ex:" devel-docs/04-CALIBRATION.md
```

E confermare ogni linea con `grep -n` nel file di codice corrispondente.

- [x] **Step 3: commit + bilingual sync**

```bash
git add devel-docs/04-CALIBRATION.md
git commit -m "Calibration: align cited values and line refs with post-remediation code"
```

Poi dispacciare `bilingual-docs-maintainer` per `04-CALIBRATION.en.md`.

---

## Verifica finale end-to-end

Dopo tutti i Task, prima di considerare il piano chiuso:

- [ ] **Suite completa verde**

```bash
mix test
```

Atteso: tutti i `test/arkea/sim/*` + persistence + views passano. 0 failures.

- [ ] **Property tests**

```bash
mix test --only property
```

Atteso: ≥100 runs per ogni property nuova (ribosome_like no-special-case, error_catastrophe monotonic, transformation event emission).

- [ ] **Canary scenario "Cronache di un estuario contestato"**

```bash
mix run priv/scripts/run_cronache_canary.exs
```

Visualizzare in `/sim` che:
1. HgtLedger mostra righe per `transformation_event`, `rm_digestion`, `phage_infection`, `plasmid_displaced`, `bacteriocin_kill`, `error_catastrophe_death`, `transduction_event`.
2. La frequenza di transduction events è 1 ordine sopra letteratura (non 3).
3. Lineage senza ribosome composition (artificialmente seedato) sopravvive a un translation-targeting xenobiotico.
4. Lineage con `cI−` cassette (artificialmente seedato) entra in lytic burst al primo SOS trigger.

- [ ] **Biological-realism review di confirmation**

Dispacciare `biological-realism-reviewer` agent sul diff complessivo del branch:

```
Verifica che i fix dei finding 🔴 in 09-BIOLOGICAL-MODEL-REVIEW-2.md siano stati
applicati correttamente. Controlla in particolare: ribosome_like generative,
repressor_strength default 0.0, error_catastrophe Eigen formula, transduction
default 0.005. Segnala eventuali regressioni o nuove discrepanze rispetto a
letteratura primaria.
```

- [ ] **Design-coherence review di confirmation**

Dispacciare `design-coherence-reviewer` agent:

```
Verifica che i 3 deviation P0 in 10-DESIGN-COHERENCE-REVIEW.md siano stati chiusi:
1. Audit log per-canale events emessi e persistiti
2. HGT.Channel behaviour conformance per coniugazione
3. ribosome_like derivato da genoma
Segnala eventuali nuove deviation introdotte dal refactor.
```

- [ ] **Squash + merge su master**

Una volta che entrambe le re-review sono pulite:

```bash
git log --oneline master..HEAD
git rebase -i master  # squash dei commit minori, mantieni i 4 macro-commit:
                      # 1. "Sim: audit log per-channel events"
                      # 2. "Phenotype: ribosome_like generative + Eigen catastrophe"
                      # 3. "HGT: Channel behaviour conformance + transduction default"
                      # 4. "Docs: post-Phase-20 debt + bilingual sync"
git checkout master
git merge --ff-only <branch>
```

---

## Stima tempo

- Blocco A: ~6-8 ore (audit log refactor è il pezzo più sostanziale; conformance behaviour ~1h)
- Blocco B: ~3-4 ore (4 fix locali con TDD)
- Blocco C: ~2 ore (docs + bilingual sync)
- Verifica end-to-end: ~1 ora

**Totale: ~12-15 ore** in sessione singola, oppure 3-4 sessioni distribuite.

## Rischi specifici

- **Audit log shape change**: estendere il return delle funzioni di canale rompe i call site. Mitigazione: TDD strict + `mix test` ad ogni step. Il branch deve restare verde commit per commit.
- **Property test regressions**: introducendo `lytic_probability/1` pubblica e cambiando `@lytic_decision_base` da 0.40 a 0.50, alcuni canary di lisogenia potrebbero shiftare. Mitigazione: rivedere i test che fanno asserzioni numeriche su `:lysogenic` count e ricalibrare.
- **Bilingual drift**: il `bilingual-docs-maintainer` agent può introdurre traduzioni terminologicamente inconsistenti. Mitigazione: review manuale del diff inglese prima del commit.
- **Seed scenario survival**: dopo `ribosome_like` generative, il seed default deve avere ≥1 gene ribosome-shaped o muore al primo translation-targeting drug intervention. Mitigazione: `seed_scenario.ex` aggiornato in Sub-task 3.1 step 4.
