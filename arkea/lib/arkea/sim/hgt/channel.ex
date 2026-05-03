defmodule Arkea.Sim.HGT.Channel do
  @moduledoc """
  Behaviour shared by every horizontal gene transfer channel (Phase 16
  formalisation — DESIGN.md Block 8).

  Each channel implements the same per-phase pipeline contract: take
  the current lineage list and a single phase, advance the channel's
  stochasticity by one tick, and return the updated lineages, the
  updated phase, the new transformant / transconjugant / lysogen
  children, and the consumed RNG state.

  ## Channel taxonomy

  | Channel | Module | Module status (Phase 16) |
  |---|---|---|
  | Conjugation | `Arkea.Sim.HGT` (`step/4`) | Phase 6 — keeps its
    legacy 4-arg signature for backward compatibility; opt-in
    behaviour conformance is the Phase 17 refactor target. |
  | Transformation | `Arkea.Sim.HGT.Channel.Transformation` | Phase 13
    — already conforms to this behaviour. |
  | Phage infection (incl. generalised transduction) | `Arkea.Sim.HGT.Phage`
    (`infection_step/4`) | Phase 12 + Phase 16. |

  The behaviour exists primarily as a documentation contract and a
  static target for `mix dialyzer`; the runtime pipeline still wires
  channels by explicit call sites in `Arkea.Sim.Tick`.
  """

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase

  @typedoc "Canonical channel-step result tuple."
  @type result :: {
          updated_lineages :: [Lineage.t()],
          updated_phase :: Phase.t(),
          new_children :: [Lineage.t()],
          rng :: :rand.state()
        }

  @doc """
  Run one tick of the channel against a single phase.

  Pure: no I/O, no message sends; all stochasticity comes from `rng`.
  """
  @callback step(
              lineages :: [Lineage.t()],
              phase :: Phase.t(),
              tick :: non_neg_integer(),
              rng :: :rand.state()
            ) :: result()

  @doc """
  Channel identifier — used by audit-log writers and by tests that
  want to assert which channel produced a given event.
  """
  @callback name() :: atom()
end
