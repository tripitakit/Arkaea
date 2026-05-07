defmodule ArkeaWeb.Components.HelpTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias ArkeaWeb.Components.Help

  test "lookup is case-insensitive and returns the metadata map" do
    refute is_nil(Help.lookup("kcat"))
    refute is_nil(Help.lookup("KCAT"))
    refute is_nil(Help.lookup("R-M"))
    assert is_nil(Help.lookup("definitely-not-a-real-term"))
  end

  test "glossary_term renders an anchor with hint cursor and tooltip when term is known" do
    html =
      render_component(&Help.glossary_term/1, %{term: "kcat"})

    assert html =~ "arkea-glossary-term"
    assert html =~ ~s|href="/help/design?section=|
    assert html =~ "Turnover number"
  end

  test "glossary_term renders a plain span fallback for unknown terms" do
    html = render_component(&Help.glossary_term/1, %{term: "no-such-term"})
    assert html =~ "<span"
    refute html =~ "arkea-glossary-term"
  end

  test "every glossary entry points to a registered HelpDoc slug" do
    valid_slugs = Enum.map(Arkea.Views.HelpDoc.list(), & &1.slug)

    for {term, meta} <- Help.glossary() do
      assert meta.doc in valid_slugs,
             "glossary term #{term} points to unknown doc #{meta.doc}"
    end
  end

  # Regression guard: every glossary entry must deep-link to a section
  # anchor that actually exists in its target doc. The Help live view
  # silently falls back to "doc top" when the anchor is missing, so a
  # broken section pointer is invisible without this check.
  test "every glossary section anchor resolves to a heading in its target doc" do
    docs = Arkea.Views.HelpDoc.list() |> Map.new(&{&1.slug, &1})

    headings_per_doc =
      Map.new(docs, fn {slug, meta} ->
        {:ok, %{headings: hs}} = Arkea.Views.HelpDoc.render(meta)
        {slug, MapSet.new(hs, & &1.anchor)}
      end)

    for {term, meta} <- Help.glossary() do
      anchors = Map.fetch!(headings_per_doc, meta.doc)

      assert MapSet.member?(anchors, meta.section),
             "glossary term #{term} → #{meta.doc}##{meta.section} : anchor not found in doc"
    end
  end
end
