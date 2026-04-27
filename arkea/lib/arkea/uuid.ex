defmodule Arkea.UUID do
  @moduledoc """
  Single point of indirection for UUID generation across the domain.

  Domain modules call `Arkea.UUID.v4/0` and stay decoupled from any specific
  UUID library. Currently delegates to `Ecto.UUID` (already a transitive
  dependency via `phoenix_ecto`); swap here if a different generator is
  needed.
  """

  @doc "Generate a random v4 UUID as a 36-character string."
  @spec v4() :: binary()
  defdelegate v4(), to: Ecto.UUID, as: :generate
end
