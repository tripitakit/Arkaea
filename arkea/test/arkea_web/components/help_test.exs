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
end
