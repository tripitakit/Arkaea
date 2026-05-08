defmodule Arkea.Repo.Migrations.AddBookmarkToBiotopeAnnotations do
  use Ecto.Migration

  # Phase 24 / 6.3 — bookmark flag on biotope annotations.
  #
  # A bookmark is a lab-notebook annotation that the player has
  # promoted to "this tick is worth showing on the time-series".
  # Bookmarks render as a vertical marker on the Trends chart
  # next to audit events, with the note's body as the tooltip.
  #
  # Storing the flag on the annotation row (instead of in a separate
  # table) keeps the data model minimal and lets the same author-
  # only CRUD authorisation cover both surfaces.
  def change do
    alter table(:biotope_annotations) do
      add :bookmark, :boolean, null: false, default: false
    end

    # Bookmarks are a small subset (single-digit %) of all notes;
    # a partial index keeps the time-series-marker query fast.
    create index(:biotope_annotations, [:biotope_id, :tick],
             where: "bookmark = true",
             name: :biotope_annotations_bookmark_index
           )
  end
end
