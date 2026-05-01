defmodule Arkea.Game.PrototypePlayer do
  @moduledoc """
  Fixed player profile used by the prototype UI before full auth arrives.
  """

  @player_id "11111111-1111-1111-1111-111111111111"
  @display_name "Anna"
  @email "anna@arkea.local"

  @spec id() :: binary()
  def id, do: @player_id

  @spec display_name() :: binary()
  def display_name, do: @display_name

  @spec email() :: binary()
  def email, do: @email

  @spec profile() :: %{id: binary(), email: binary(), display_name: binary()}
  def profile do
    %{id: id(), email: email(), display_name: display_name()}
  end
end
