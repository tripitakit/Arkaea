defmodule Arkea.Persistence.PhaseTest do
  use Arkea.DataCase, async: true

  alias Arkea.Persistence.Biotope
  alias Arkea.Persistence.Phase

  defp insert_biotope do
    {:ok, biotope} =
      %Biotope{}
      |> Biotope.changeset(%{
        archetype: "oligotrophic_lake",
        zone: "lacustrine_zone",
        x: 0.0,
        y: 0.0
      })
      |> Repo.insert()

    biotope
  end

  defp valid_attrs(biotope_id, overrides \\ %{}) do
    Map.merge(
      %{
        biotope_id: biotope_id,
        name: "surface",
        temperature: 18.0,
        ph: 7.2,
        osmolarity: 50.0,
        dilution_rate: 0.05
      },
      overrides
    )
  end

  describe "changeset/2" do
    test "valida una fase valida" do
      biotope = insert_biotope()
      changeset = Phase.changeset(%Phase{}, valid_attrs(biotope.id))
      assert changeset.valid?
    end

    test "richiede tutti i campi obbligatori" do
      changeset = Phase.changeset(%Phase{}, %{})
      refute changeset.valid?
      assert errors_on(changeset).biotope_id
      assert errors_on(changeset).name
      assert errors_on(changeset).temperature
      assert errors_on(changeset).ph
      assert errors_on(changeset).osmolarity
      assert errors_on(changeset).dilution_rate
    end

    test "rifiuta ph fuori range" do
      biotope = insert_biotope()

      changeset =
        Phase.changeset(%Phase{}, valid_attrs(biotope.id, %{ph: 15.0}))

      refute changeset.valid?
      assert errors_on(changeset).ph
    end

    test "rifiuta temperature fuori range" do
      biotope = insert_biotope()

      changeset =
        Phase.changeset(%Phase{}, valid_attrs(biotope.id, %{temperature: 200.0}))

      refute changeset.valid?
      assert errors_on(changeset).temperature
    end

    test "rifiuta dilution_rate > 1.0" do
      biotope = insert_biotope()

      changeset =
        Phase.changeset(%Phase{}, valid_attrs(biotope.id, %{dilution_rate: 1.5}))

      refute changeset.valid?
      assert errors_on(changeset).dilution_rate
    end
  end

  describe "insert + get" do
    test "inserisce e rilancia una fase" do
      biotope = insert_biotope()

      {:ok, phase} =
        %Phase{}
        |> Phase.changeset(valid_attrs(biotope.id))
        |> Repo.insert()

      fetched = Repo.get!(Phase, phase.id)
      assert fetched.name == "surface"
      assert fetched.biotope_id == biotope.id
      assert_in_delta fetched.temperature, 18.0, 0.001
      assert_in_delta fetched.ph, 7.2, 0.001
    end

    test "unique constraint su (biotope_id, name)" do
      biotope = insert_biotope()

      {:ok, _} =
        %Phase{}
        |> Phase.changeset(valid_attrs(biotope.id))
        |> Repo.insert()

      {:error, changeset} =
        %Phase{}
        |> Phase.changeset(valid_attrs(biotope.id))
        |> Repo.insert()

      errors = errors_on(changeset)

      # Ecto places unique_constraint errors under the first field of the
      # constraint tuple (`:biotope_id`). The custom message is what we set
      # in `Phase.changeset/2`.
      assert "a phase with this name already exists in the biotope" in (errors[:biotope_id] || [])
    end
  end
end
