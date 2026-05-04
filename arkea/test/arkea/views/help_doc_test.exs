defmodule Arkea.Views.HelpDocTest do
  use ExUnit.Case, async: true

  alias Arkea.Views.HelpDoc

  test "list/0 returns the registered docs" do
    docs = HelpDoc.list()

    slugs = Enum.map(docs, & &1.slug)
    assert "user-manual" in slugs
    assert "design" in slugs
    assert "calibration" in slugs
    assert "ui-optimization" in slugs
  end

  test "find/1 returns nil for unknown slug" do
    assert is_nil(HelpDoc.find("does-not-exist"))
  end

  test "every registered doc resolves to a file that exists on disk" do
    for doc <- HelpDoc.list() do
      assert File.exists?(doc.path), "missing file for #{doc.slug}: #{doc.path}"
    end
  end

  test "render/1 returns html and a non-empty heading list for the user manual" do
    doc = HelpDoc.find("user-manual")
    assert {:ok, %{html: {:safe, html_iolist}, headings: headings}} = HelpDoc.render(doc)

    html = IO.iodata_to_binary(html_iolist)

    assert byte_size(html) > 1_000
    assert String.contains?(html, "<h1>")
    assert length(headings) > 0
    assert Enum.all?(headings, &Map.has_key?(&1, :anchor))
  end
end
