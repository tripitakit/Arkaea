defmodule Arkea.Persistence.MobileElementTest do
  use Arkea.DataCase, async: true

  alias Arkea.Persistence.MobileElement

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        kind: "plasmid",
        created_at_tick: 3
      },
      overrides
    )
  end

  describe "changeset/2" do
    test "valida un elemento mobile valido" do
      changeset = MobileElement.changeset(%MobileElement{}, valid_attrs())
      assert changeset.valid?
    end

    test "accetta tutti e 3 i kind ammessi" do
      for kind <- MobileElement.kinds() do
        changeset = MobileElement.changeset(%MobileElement{}, valid_attrs(%{kind: kind}))
        assert changeset.valid?, "kind #{kind} should be valid"
      end
    end

    test "rifiuta kind non valido" do
      changeset = MobileElement.changeset(%MobileElement{}, valid_attrs(%{kind: "retrovirus"}))
      refute changeset.valid?
      assert "must be one of" <> _ = hd(errors_on(changeset).kind)
    end

    test "richiede kind e created_at_tick" do
      changeset = MobileElement.changeset(%MobileElement{}, %{})
      refute changeset.valid?
      assert errors_on(changeset).kind
      assert errors_on(changeset).created_at_tick
    end

    test "rifiuta created_at_tick negativo" do
      changeset = MobileElement.changeset(%MobileElement{}, valid_attrs(%{created_at_tick: -5}))
      refute changeset.valid?
      assert errors_on(changeset).created_at_tick
    end

    test "accetta genes nil (Phase 1: payload non ancora definito)" do
      changeset = MobileElement.changeset(%MobileElement{}, valid_attrs(%{genes: nil}))
      assert changeset.valid?
    end
  end

  describe "insert + get" do
    test "inserisce e rilancia un elemento mobile senza genes" do
      {:ok, elem} =
        %MobileElement{}
        |> MobileElement.changeset(valid_attrs(%{kind: "free_phage", created_at_tick: 7}))
        |> Repo.insert()

      fetched = Repo.get!(MobileElement, elem.id)
      assert fetched.kind == "free_phage"
      assert fetched.created_at_tick == 7
      assert fetched.genes == nil
    end

    test "inserisce e rilancia con genes serializzati" do
      gene_payload = [:receptor_gene, :lysogenic_repressor, :capsid_subunit]
      serialized = :erlang.term_to_binary(gene_payload, [:compressed])

      {:ok, elem} =
        %MobileElement{}
        |> MobileElement.changeset(
          valid_attrs(%{
            kind: "prophage",
            genes: serialized,
            origin_biotope_id: Ecto.UUID.generate(),
            origin_lineage_id: Ecto.UUID.generate()
          })
        )
        |> Repo.insert()

      fetched = Repo.get!(MobileElement, elem.id)
      assert fetched.genes != nil

      deserialized = :erlang.binary_to_term(fetched.genes, [:safe])
      assert deserialized == gene_payload
    end

    test "origin IDs sono tombstone (nessuna FK, possono essere UUID arbitrari)" do
      fake_origin_biotope = Ecto.UUID.generate()
      fake_origin_lineage = Ecto.UUID.generate()

      {:ok, elem} =
        %MobileElement{}
        |> MobileElement.changeset(
          valid_attrs(%{
            kind: "plasmid",
            origin_biotope_id: fake_origin_biotope,
            origin_lineage_id: fake_origin_lineage
          })
        )
        |> Repo.insert()

      fetched = Repo.get!(MobileElement, elem.id)
      assert fetched.origin_biotope_id == fake_origin_biotope
      assert fetched.origin_lineage_id == fake_origin_lineage
    end
  end
end
