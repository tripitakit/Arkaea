defmodule Arkea.Persistence.Serializer do
  @moduledoc """
  Binary serializer for persisted `Arkea.Sim.BiotopeState` snapshots and WAL rows.
  """

  alias Arkea.Sim.BiotopeState

  @doc "Serialize a `BiotopeState` into a compressed Erlang binary."
  @spec dump!(BiotopeState.t()) :: binary()
  def dump!(%BiotopeState{} = state) do
    :erlang.term_to_binary(state, [:compressed])
  end

  @doc """
  Safely deserialize a persisted biotope state.
  """
  @spec load(binary()) :: {:ok, BiotopeState.t()} | {:error, atom() | tuple()}
  def load(binary) when is_binary(binary) do
    case :erlang.binary_to_term(binary) do
      %BiotopeState{} = state -> {:ok, state}
      other -> {:error, {:unexpected_term, other}}
    end
  rescue
    ArgumentError -> {:error, :invalid_binary}
    error in [ErlangError] -> {:error, {:erlang_error, error}}
  end
end
