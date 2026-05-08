defmodule Arkea.Notebook do
  @moduledoc """
  Lab notebook context (Phase 24).

  Owns the player-facing API for biotope annotations (6.1) and, in
  later sub-phases, time-anchored permalinks (6.2), bookmarks (6.3)
  and replay scrubbing (6.4). Today only the annotation API is
  exposed; the rest is delivered incrementally on the same context.

  Authorisation rule for v1: a player can read every annotation on
  any biotope they can already access; a player can create / delete
  *only their own* annotations. Cross-player annotation deletion is
  rejected with `{:error, :unauthorized}`.
  """

  import Ecto.Query

  alias Arkea.Persistence.BiotopeAnnotation
  alias Arkea.Repo

  @doc """
  List the annotations of a biotope ordered by tick ascending, then
  by `inserted_at` ascending (so multiple notes at the same tick keep
  the order in which the player wrote them).
  """
  @spec list_for_biotope(binary()) :: [BiotopeAnnotation.t()]
  def list_for_biotope(biotope_id) when is_binary(biotope_id) do
    Repo.all(
      from a in BiotopeAnnotation,
        where: a.biotope_id == ^biotope_id,
        order_by: [asc: a.tick, asc: a.inserted_at]
    )
  end

  @doc """
  Create an annotation. The author's `player_id` is required and is
  authoritative — clients cannot impersonate another player at this
  layer (the LiveView passes `socket.assigns.current_player.id`).
  """
  @spec create(binary(), binary(), non_neg_integer(), String.t(), keyword()) ::
          {:ok, BiotopeAnnotation.t()} | {:error, Ecto.Changeset.t()}
  def create(biotope_id, player_id, tick, body, opts \\ [])
      when is_binary(biotope_id) and is_binary(player_id) and is_integer(tick) and
             is_binary(body) do
    bookmark = Keyword.get(opts, :bookmark, false)

    %BiotopeAnnotation{}
    |> BiotopeAnnotation.changeset(%{
      biotope_id: biotope_id,
      player_id: player_id,
      tick: tick,
      body: body,
      bookmark: bookmark
    })
    |> Repo.insert()
  end

  @doc """
  Delete an annotation, but only if the supplied `player_id` matches
  the author. Returns `{:ok, deleted}`, `{:error, :not_found}` if the
  id does not exist, or `{:error, :unauthorized}` if it exists but
  belongs to a different player.
  """
  @spec delete(binary(), binary()) ::
          {:ok, BiotopeAnnotation.t()} | {:error, :not_found | :unauthorized}
  def delete(annotation_id, player_id)
      when is_binary(annotation_id) and is_binary(player_id) do
    case Repo.get(BiotopeAnnotation, annotation_id) do
      nil ->
        {:error, :not_found}

      %BiotopeAnnotation{player_id: ^player_id} = annotation ->
        Repo.delete(annotation)

      %BiotopeAnnotation{} ->
        {:error, :unauthorized}
    end
  end

  @doc """
  Build a fresh changeset suitable for the LiveView form.
  """
  @spec change_annotation(map()) :: Ecto.Changeset.t()
  def change_annotation(attrs \\ %{}) do
    BiotopeAnnotation.changeset(%BiotopeAnnotation{}, attrs)
  end

  # ---------------------------------------------------------------------------
  # Phase 24 / 6.3 — bookmark toggle + bookmarks-only listing.

  @doc """
  Flip the `bookmark` flag on an annotation. Author-only.

  Returns `{:ok, updated}`, `{:error, :not_found}` or
  `{:error, :unauthorized}` mirroring `delete/2`.
  """
  @spec toggle_bookmark(binary(), binary()) ::
          {:ok, BiotopeAnnotation.t()}
          | {:error, :not_found | :unauthorized | Ecto.Changeset.t()}
  def toggle_bookmark(annotation_id, player_id)
      when is_binary(annotation_id) and is_binary(player_id) do
    case Repo.get(BiotopeAnnotation, annotation_id) do
      nil ->
        {:error, :not_found}

      %BiotopeAnnotation{player_id: ^player_id} = annotation ->
        annotation
        |> BiotopeAnnotation.changeset(%{bookmark: not annotation.bookmark})
        |> Repo.update()

      %BiotopeAnnotation{} ->
        {:error, :unauthorized}
    end
  end

  @doc """
  List only the annotations of a biotope that are flagged as
  bookmarks. The same `(tick asc, inserted_at asc)` ordering as
  `list_for_biotope/1` so the UI can render them in temporal order
  without re-sorting.
  """
  @spec list_bookmarks_for_biotope(binary()) :: [BiotopeAnnotation.t()]
  def list_bookmarks_for_biotope(biotope_id) when is_binary(biotope_id) do
    Repo.all(
      from a in BiotopeAnnotation,
        where: a.biotope_id == ^biotope_id and a.bookmark == true,
        order_by: [asc: a.tick, asc: a.inserted_at]
    )
  end
end
