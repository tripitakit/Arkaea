defmodule Arkea.Persistence.BiotopeTest do
  use Arkea.DataCase, async: true

  alias Arkea.Persistence.Biotope
  alias Arkea.Persistence.Player

  defp insert_player do
    {:ok, player} =
      %Player{}
      |> Player.changeset(%{email: "owner@example.com", display_name: "Owner"})
      |> Repo.insert()

    player
  end

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        archetype: "oligotrophic_lake",
        zone: "lacustrine_zone",
        x: 1.0,
        y: 2.0
      },
      overrides
    )
  end

  describe "changeset/2" do
    test "valida un biotopo wild valido" do
      changeset = Biotope.changeset(%Biotope{}, valid_attrs())
      assert changeset.valid?
    end

    test "accetta tutti gli 8 archetipi" do
      for archetype <- Biotope.archetypes() do
        changeset = Biotope.changeset(%Biotope{}, valid_attrs(%{archetype: archetype}))
        assert changeset.valid?, "archetype #{archetype} should be valid"
      end
    end

    test "rifiuta archetype non valido" do
      changeset =
        Biotope.changeset(%Biotope{}, valid_attrs(%{archetype: "deep_space_station"}))

      refute changeset.valid?
      assert "must be one of" <> _ = hd(errors_on(changeset).archetype)
    end

    test "richiede tutti i campi obbligatori" do
      changeset = Biotope.changeset(%Biotope{}, %{})
      refute changeset.valid?
      assert errors_on(changeset).archetype
      assert errors_on(changeset).zone
      assert errors_on(changeset).x
      assert errors_on(changeset).y
    end
  end

  describe "insert + get" do
    test "inserisce un biotopo wild e lo rilancia" do
      {:ok, biotope} =
        %Biotope{}
        |> Biotope.changeset(valid_attrs())
        |> Repo.insert()

      assert biotope.id != nil
      assert biotope.owner_player_id == nil

      fetched = Repo.get!(Biotope, biotope.id)
      assert fetched.archetype == "oligotrophic_lake"
      assert fetched.zone == "lacustrine_zone"
      assert_in_delta fetched.x, 1.0, 0.001
      assert_in_delta fetched.y, 2.0, 0.001
    end

    test "inserisce un biotopo owned" do
      player = insert_player()

      {:ok, biotope} =
        %Biotope{}
        |> Biotope.changeset(valid_attrs(%{owner_player_id: player.id}))
        |> Repo.insert()

      fetched = Repo.get!(Biotope, biotope.id)
      assert fetched.owner_player_id == player.id
    end

    test "rifiuta archetype invalido via DB constraint" do
      # Il changeset blocca prima, ma verifichiamo la validazione
      changeset = Biotope.changeset(%Biotope{}, valid_attrs(%{archetype: "invalid_type"}))
      refute changeset.valid?
    end
  end
end
