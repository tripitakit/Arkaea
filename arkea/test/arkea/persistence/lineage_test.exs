defmodule Arkea.Persistence.LineageTest do
  use Arkea.DataCase, async: true

  alias Arkea.Persistence.Biotope
  alias Arkea.Persistence.Lineage

  defp insert_biotope do
    {:ok, biotope} =
      %Biotope{}
      |> Biotope.changeset(%{
        archetype: "mesophilic_soil",
        zone: "soil_zone",
        x: 5.0,
        y: 5.0
      })
      |> Repo.insert()

    biotope
  end

  defp valid_attrs(biotope_id, overrides \\ %{}) do
    id = Ecto.UUID.generate()

    Map.merge(
      %{
        biotope_id: biotope_id,
        clade_ref_id: id,
        abundance_by_phase: %{"aerated_pore" => 100, "wet_clump" => 50},
        created_at_tick: 0
      },
      overrides
    )
  end

  describe "changeset/2" do
    test "valida un lineage founder valido" do
      biotope = insert_biotope()
      changeset = Lineage.changeset(%Lineage{}, valid_attrs(biotope.id))
      assert changeset.valid?
    end

    test "richiede i campi obbligatori" do
      changeset = Lineage.changeset(%Lineage{}, %{})
      refute changeset.valid?
      assert errors_on(changeset).biotope_id
      assert errors_on(changeset).clade_ref_id
      assert errors_on(changeset).abundance_by_phase
      assert errors_on(changeset).created_at_tick
    end

    test "rifiuta created_at_tick negativo" do
      biotope = insert_biotope()

      changeset =
        Lineage.changeset(%Lineage{}, valid_attrs(biotope.id, %{created_at_tick: -1}))

      refute changeset.valid?
      assert errors_on(changeset).created_at_tick
    end

    test "rifiuta fitness_cache negativo" do
      biotope = insert_biotope()

      changeset =
        Lineage.changeset(%Lineage{}, valid_attrs(biotope.id, %{fitness_cache: -0.5}))

      refute changeset.valid?
      assert errors_on(changeset).fitness_cache
    end

    test "rifiuta abundance_by_phase con valori negativi" do
      biotope = insert_biotope()

      changeset =
        Lineage.changeset(
          %Lineage{},
          valid_attrs(biotope.id, %{abundance_by_phase: %{"surface" => -10}})
        )

      refute changeset.valid?
      assert errors_on(changeset).abundance_by_phase
    end

    test "accetta genome come nil (Phase 4 delta-encoding futuro)" do
      biotope = insert_biotope()

      changeset =
        Lineage.changeset(%Lineage{}, valid_attrs(biotope.id, %{genome: nil}))

      assert changeset.valid?
    end
  end

  describe "insert + get con serializzazione genome" do
    test "inserisce e rilancia un lineage" do
      biotope = insert_biotope()

      {:ok, lineage} =
        %Lineage{}
        |> Lineage.changeset(valid_attrs(biotope.id))
        |> Repo.insert()

      fetched = Repo.get!(Lineage, lineage.id)
      assert fetched.biotope_id == biotope.id
      assert fetched.created_at_tick == 0
      assert fetched.abundance_by_phase == %{"aerated_pore" => 100, "wet_clump" => 50}
    end

    test "serializza e deserializza genome come :erlang.term_to_binary" do
      biotope = insert_biotope()

      # Struct di dominio generica che vogliamo serializzare
      original_term = %{
        chromosome: [:gene_a, :gene_b, :gene_c],
        plasmids: [],
        prophages: []
      }

      serialized = :erlang.term_to_binary(original_term, [:compressed])

      {:ok, lineage} =
        %Lineage{}
        |> Lineage.changeset(valid_attrs(biotope.id, %{genome: serialized}))
        |> Repo.insert()

      fetched = Repo.get!(Lineage, lineage.id)
      assert fetched.genome != nil

      deserialized = :erlang.binary_to_term(fetched.genome, [:safe])
      assert deserialized == original_term
    end

    test "inserisce lineage child con parent_id" do
      biotope = insert_biotope()
      parent_clade_id = Ecto.UUID.generate()

      {:ok, parent} =
        %Lineage{}
        |> Lineage.changeset(%{
          biotope_id: biotope.id,
          clade_ref_id: parent_clade_id,
          abundance_by_phase: %{"aerated_pore" => 200},
          created_at_tick: 0
        })
        |> Repo.insert()

      {:ok, child} =
        %Lineage{}
        |> Lineage.changeset(%{
          biotope_id: biotope.id,
          parent_id: parent.id,
          clade_ref_id: parent_clade_id,
          abundance_by_phase: %{"aerated_pore" => 50},
          created_at_tick: 5
        })
        |> Repo.insert()

      fetched_child = Repo.get!(Lineage, child.id)
      assert fetched_child.parent_id == parent.id
      assert fetched_child.created_at_tick == 5
    end
  end
end
