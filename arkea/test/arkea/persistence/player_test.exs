defmodule Arkea.Persistence.PlayerTest do
  use Arkea.DataCase, async: true

  alias Arkea.Persistence.Player

  describe "changeset/2" do
    test "valida un player valido" do
      attrs = %{email: "alice@example.com", display_name: "Alice"}
      changeset = Player.changeset(%Player{}, attrs)
      assert changeset.valid?
    end

    test "normalizza email a lowercase" do
      attrs = %{email: "ALICE@EXAMPLE.COM", display_name: "Alice"}
      changeset = Player.changeset(%Player{}, attrs)
      assert get_change(changeset, :email) == "alice@example.com"
    end

    test "richiede email" do
      changeset = Player.changeset(%Player{}, %{display_name: "Alice"})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).email
    end

    test "richiede display_name" do
      changeset = Player.changeset(%Player{}, %{email: "alice@example.com"})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).display_name
    end

    test "rifiuta email malformata" do
      attrs = %{email: "not-an-email", display_name: "Alice"}
      changeset = Player.changeset(%Player{}, attrs)
      refute changeset.valid?
      assert "must be a valid email address" in errors_on(changeset).email
    end

    test "rifiuta display_name vuoto" do
      attrs = %{email: "alice@example.com", display_name: ""}
      changeset = Player.changeset(%Player{}, attrs)
      refute changeset.valid?
    end

    test "accetta colonization_cooldown_until nullable" do
      attrs = %{
        email: "bob@example.com",
        display_name: "Bob",
        colonization_cooldown_until: nil
      }

      changeset = Player.changeset(%Player{}, attrs)
      assert changeset.valid?
    end
  end

  describe "insert + get" do
    test "inserisce e rilancia un player" do
      attrs = %{email: "charlie@example.com", display_name: "Charlie"}

      {:ok, player} =
        %Player{}
        |> Player.changeset(attrs)
        |> Repo.insert()

      assert player.id != nil
      assert player.email == "charlie@example.com"

      fetched = Repo.get!(Player, player.id)
      assert fetched.email == "charlie@example.com"
      assert fetched.display_name == "Charlie"
      assert fetched.colonization_cooldown_until == nil
    end

    test "rifiuta email duplicata" do
      attrs = %{email: "dup@example.com", display_name: "First"}

      {:ok, _} =
        %Player{}
        |> Player.changeset(attrs)
        |> Repo.insert()

      {:error, changeset} =
        %Player{}
        |> Player.changeset(%{email: "dup@example.com", display_name: "Second"})
        |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).email
    end

    test "inserisce con cooldown popolato" do
      cooldown = ~U[2026-05-01 12:00:00.000000Z]

      attrs = %{
        email: "delta@example.com",
        display_name: "Delta",
        colonization_cooldown_until: cooldown
      }

      {:ok, player} =
        %Player{}
        |> Player.changeset(attrs)
        |> Repo.insert()

      fetched = Repo.get!(Player, player.id)
      assert fetched.colonization_cooldown_until == cooldown
    end
  end
end
