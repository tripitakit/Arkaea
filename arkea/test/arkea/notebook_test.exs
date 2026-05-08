defmodule Arkea.NotebookTest do
  use Arkea.DataCase, async: true

  alias Arkea.Notebook
  alias Arkea.Persistence.BiotopeAnnotation

  defp ids do
    {Ecto.UUID.generate(), Ecto.UUID.generate()}
  end

  test "create/4 persists an annotation with tick + body" do
    {biotope_id, player_id} = ids()

    assert {:ok, %BiotopeAnnotation{} = a} =
             Notebook.create(biotope_id, player_id, 42, "First observation: lineage X dominates")

    assert a.biotope_id == biotope_id
    assert a.player_id == player_id
    assert a.tick == 42
    assert a.body == "First observation: lineage X dominates"
  end

  test "list_for_biotope/1 orders by tick asc then by inserted_at asc" do
    {biotope_id, player_id} = ids()

    {:ok, a1} = Notebook.create(biotope_id, player_id, 50, "later observation")
    {:ok, a2} = Notebook.create(biotope_id, player_id, 10, "earlier observation")
    # Two notes at the same tick — the second should sort after the first.
    {:ok, a3} = Notebook.create(biotope_id, player_id, 30, "first at tick 30")
    {:ok, a4} = Notebook.create(biotope_id, player_id, 30, "second at tick 30")

    list = Notebook.list_for_biotope(biotope_id)
    assert Enum.map(list, & &1.id) == [a2.id, a3.id, a4.id, a1.id]
  end

  test "list_for_biotope/1 isolates by biotope" do
    {biotope_a, player_id} = ids()
    {biotope_b, _} = ids()

    {:ok, _} = Notebook.create(biotope_a, player_id, 5, "in biotope A")
    {:ok, _} = Notebook.create(biotope_b, player_id, 5, "in biotope B")

    assert [a] = Notebook.list_for_biotope(biotope_a)
    assert a.body == "in biotope A"
  end

  test "create/4 rejects empty body" do
    {biotope_id, player_id} = ids()
    assert {:error, %Ecto.Changeset{}} = Notebook.create(biotope_id, player_id, 1, "")
  end

  test "create/4 rejects negative tick" do
    {biotope_id, player_id} = ids()
    assert {:error, %Ecto.Changeset{}} = Notebook.create(biotope_id, player_id, -1, "x")
  end

  test "create/4 rejects bodies above the cap" do
    {biotope_id, player_id} = ids()
    body = String.duplicate("x", BiotopeAnnotation.body_max_length() + 1)
    assert {:error, %Ecto.Changeset{}} = Notebook.create(biotope_id, player_id, 1, body)
  end

  test "create/4 normalises CRLF to LF and strips trailing whitespace" do
    {biotope_id, player_id} = ids()
    {:ok, a} = Notebook.create(biotope_id, player_id, 1, "line one\r\nline two   \n")
    assert a.body == "line one\nline two"
  end

  test "delete/2 succeeds when the player owns the annotation" do
    {biotope_id, player_id} = ids()
    {:ok, a} = Notebook.create(biotope_id, player_id, 1, "to be deleted")
    assert {:ok, _} = Notebook.delete(a.id, player_id)
    assert Notebook.list_for_biotope(biotope_id) == []
  end

  test "delete/2 returns :unauthorized when the requester is not the author" do
    {biotope_id, owner} = ids()
    {_, intruder} = ids()
    {:ok, a} = Notebook.create(biotope_id, owner, 1, "owned by alice")
    assert {:error, :unauthorized} = Notebook.delete(a.id, intruder)
    # The note must still exist.
    assert [_kept] = Notebook.list_for_biotope(biotope_id)
  end

  test "delete/2 returns :not_found for a non-existent id" do
    {_, player_id} = ids()
    assert {:error, :not_found} = Notebook.delete(Ecto.UUID.generate(), player_id)
  end

  test "change_annotation/1 returns a changeset suitable for forms" do
    cs = Notebook.change_annotation(%{tick: 0, body: "draft"})
    refute cs.valid?
    assert cs.errors[:biotope_id]
    assert cs.errors[:player_id]
  end

  describe "bookmarks (Phase 24 / 6.3)" do
    test "create/5 with bookmark: true persists the flag" do
      {biotope_id, player_id} = ids()

      assert {:ok, a} =
               Notebook.create(biotope_id, player_id, 10, "marker note", bookmark: true)

      assert a.bookmark == true
    end

    test "default is bookmark: false" do
      {biotope_id, player_id} = ids()
      {:ok, a} = Notebook.create(biotope_id, player_id, 5, "regular note")
      assert a.bookmark == false
    end

    test "toggle_bookmark/2 flips the flag for the author" do
      {biotope_id, player_id} = ids()
      {:ok, a} = Notebook.create(biotope_id, player_id, 1, "starts as note")
      assert a.bookmark == false

      assert {:ok, a2} = Notebook.toggle_bookmark(a.id, player_id)
      assert a2.bookmark == true

      assert {:ok, a3} = Notebook.toggle_bookmark(a.id, player_id)
      assert a3.bookmark == false
    end

    test "toggle_bookmark/2 rejects non-author with :unauthorized" do
      {biotope_id, owner} = ids()
      {_, intruder} = ids()
      {:ok, a} = Notebook.create(biotope_id, owner, 1, "owned by alice")
      assert {:error, :unauthorized} = Notebook.toggle_bookmark(a.id, intruder)
    end

    test "toggle_bookmark/2 returns :not_found for missing id" do
      {_, player_id} = ids()
      assert {:error, :not_found} = Notebook.toggle_bookmark(Ecto.UUID.generate(), player_id)
    end

    test "list_bookmarks_for_biotope/1 returns only flagged notes, ordered by tick" do
      {biotope_id, player_id} = ids()
      {:ok, _plain} = Notebook.create(biotope_id, player_id, 5, "not a bookmark")
      {:ok, b1} = Notebook.create(biotope_id, player_id, 20, "second bookmark", bookmark: true)
      {:ok, b2} = Notebook.create(biotope_id, player_id, 10, "first bookmark", bookmark: true)

      bookmarks = Notebook.list_bookmarks_for_biotope(biotope_id)
      assert Enum.map(bookmarks, & &1.id) == [b2.id, b1.id]
      assert Enum.all?(bookmarks, & &1.bookmark)
    end
  end
end
