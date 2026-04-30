defmodule CRC.ShiftNotesTest do
  use CRC.DataCase, async: true

  alias CRC.ShiftNotes
  alias CRC.ShiftNotes.ShiftNote

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Author User",
          email: "author#{System.unique_integer()}@cafe.com",
          role: "empleado",
          stations: ["sala"],
          password: "contraseña123"
        },
        overrides
      )

    {:ok, user} =
      %CRC.Accounts.User{}
      |> CRC.Accounts.User.changeset(attrs)
      |> CRC.Repo.insert()

    user
  end

  # ===========================================================================
  # ShiftNote.changeset/2
  # ===========================================================================

  describe "ShiftNote.changeset/2" do
    test "GIVEN valid attrs WHEN building changeset THEN it is valid" do
      user = insert_user()

      cs =
        ShiftNote.changeset(%ShiftNote{}, %{
          "content" => "Todo listo para el siguiente turno.",
          "category" => "general",
          "author_id" => user.id
        })

      assert cs.valid?
    end

    test "GIVEN missing content WHEN building changeset THEN invalid" do
      user = insert_user()

      cs = ShiftNote.changeset(%ShiftNote{}, %{"author_id" => user.id})
      refute cs.valid?
      assert cs.errors[:content]
    end

    test "GIVEN content too short (1 char) WHEN building changeset THEN invalid" do
      user = insert_user()

      cs =
        ShiftNote.changeset(%ShiftNote{}, %{
          "content" => "X",
          "author_id" => user.id
        })

      refute cs.valid?
      assert cs.errors[:content]
    end

    test "GIVEN content too long (> 500 chars) WHEN building changeset THEN invalid" do
      user = insert_user()
      long_content = String.duplicate("a", 501)

      cs =
        ShiftNote.changeset(%ShiftNote{}, %{
          "content" => long_content,
          "author_id" => user.id
        })

      refute cs.valid?
      assert cs.errors[:content]
    end

    test "GIVEN invalid category WHEN building changeset THEN invalid" do
      user = insert_user()

      cs =
        ShiftNote.changeset(%ShiftNote{}, %{
          "content" => "Nota de prueba.",
          "category" => "invalido",
          "author_id" => user.id
        })

      refute cs.valid?
      assert cs.errors[:category]
    end

    test "GIVEN all valid categories WHEN building changesets THEN all are valid" do
      user = insert_user()

      for cat <- ~w(stock preparacion equipo general) do
        cs =
          ShiftNote.changeset(%ShiftNote{}, %{
            "content" => "Nota de prueba.",
            "category" => cat,
            "author_id" => user.id
          })

        assert cs.valid?, "Expected valid changeset for category: #{cat}"
      end
    end

    test "GIVEN missing author_id WHEN building changeset THEN invalid" do
      cs =
        ShiftNote.changeset(%ShiftNote{}, %{
          "content" => "Nota sin autor."
        })

      refute cs.valid?
      assert cs.errors[:author_id]
    end
  end

  # ===========================================================================
  # ShiftNote.resolve_changeset/2
  # ===========================================================================

  describe "ShiftNote.resolve_changeset/2" do
    test "GIVEN an active note WHEN resolving THEN status is set to resolved" do
      user = insert_user()
      {:ok, note} = ShiftNotes.create_note(%{"content" => "Nota activa."}, user.id)

      cs = ShiftNote.resolve_changeset(note, user.id)

      assert cs.changes.status == "resolved"
      assert cs.changes.resolved_by_id == user.id
      assert cs.changes.resolved_at
    end
  end

  # ===========================================================================
  # ShiftNotes.create_note/2
  # ===========================================================================

  describe "create_note/2" do
    test "GIVEN valid attrs WHEN creating note THEN note is persisted" do
      user = insert_user()

      assert {:ok, %ShiftNote{} = note} =
               ShiftNotes.create_note(%{"content" => "Todo en orden."}, user.id)

      assert note.id
      assert note.author_id == user.id
      assert note.status == "active"
    end

    test "GIVEN valid attrs with category WHEN creating note THEN category is set" do
      user = insert_user()

      {:ok, note} =
        ShiftNotes.create_note(%{"content" => "Alerta de stock.", "category" => "stock"}, user.id)

      assert note.category == "stock"
    end

    test "GIVEN invalid attrs (empty content) WHEN creating note THEN returns error changeset" do
      user = insert_user()

      assert {:error, %Ecto.Changeset{}} = ShiftNotes.create_note(%{"content" => ""}, user.id)
    end

    test "GIVEN valid note WHEN creating THEN author is preloaded on returned note" do
      user = insert_user()

      {:ok, note} = ShiftNotes.create_note(%{"content" => "Nota con preload."}, user.id)
      assert note.author.id == user.id
    end
  end

  # ===========================================================================
  # ShiftNotes.list_active_notes/0
  # ===========================================================================

  describe "list_active_notes/0" do
    test "GIVEN active notes WHEN listing THEN they are included" do
      user = insert_user()
      {:ok, note} = ShiftNotes.create_note(%{"content" => "Nota activa visible."}, user.id)

      notes = ShiftNotes.list_active_notes()
      ids = Enum.map(notes, & &1.id)
      assert note.id in ids
    end

    test "GIVEN resolved note WHEN listing active THEN it is NOT included" do
      user = insert_user()
      {:ok, note} = ShiftNotes.create_note(%{"content" => "Nota resuelta."}, user.id)
      ShiftNotes.resolve_note(note.id, user.id)

      notes = ShiftNotes.list_active_notes()
      ids = Enum.map(notes, & &1.id)
      refute note.id in ids
    end
  end

  # ===========================================================================
  # ShiftNotes.resolve_note/2
  # ===========================================================================

  describe "resolve_note/2" do
    test "GIVEN active note WHEN resolving THEN status changes to resolved" do
      user = insert_user()
      {:ok, note} = ShiftNotes.create_note(%{"content" => "Nota para resolver."}, user.id)

      assert {:ok, resolved} = ShiftNotes.resolve_note(note.id, user.id)
      assert resolved.status == "resolved"
      assert resolved.resolved_by_id == user.id
      assert resolved.resolved_at
    end

    test "GIVEN resolved note WHEN listing recent resolved THEN it appears" do
      user = insert_user()
      {:ok, note} = ShiftNotes.create_note(%{"content" => "Nota reciente resuelta."}, user.id)
      ShiftNotes.resolve_note(note.id, user.id)

      recent = ShiftNotes.list_recent_resolved_notes()
      ids = Enum.map(recent, & &1.id)
      assert note.id in ids
    end
  end

  # ===========================================================================
  # ShiftNotes.delete_note/1
  # ===========================================================================

  describe "delete_note/1" do
    test "GIVEN existing note WHEN deleting THEN returns :ok and note is gone" do
      user = insert_user()
      {:ok, note} = ShiftNotes.create_note(%{"content" => "Nota a eliminar."}, user.id)

      assert :ok = ShiftNotes.delete_note(note.id)

      notes = ShiftNotes.list_active_notes()
      ids = Enum.map(notes, & &1.id)
      refute note.id in ids
    end

    test "GIVEN non-existent note id WHEN deleting THEN returns :ok (idempotent)" do
      assert :ok = ShiftNotes.delete_note(-999)
    end
  end

  # ===========================================================================
  # ShiftNotes.list_recent_resolved_notes/1
  # ===========================================================================

  describe "list_recent_resolved_notes/1" do
    test "GIVEN active (not resolved) notes WHEN listing recent resolved THEN they are excluded" do
      user = insert_user()
      {:ok, note} = ShiftNotes.create_note(%{"content" => "Nota no resuelta."}, user.id)

      recent = ShiftNotes.list_recent_resolved_notes()
      ids = Enum.map(recent, & &1.id)
      refute note.id in ids
    end
  end

  # ===========================================================================
  # ShiftNotes.change_note/1
  # ===========================================================================

  describe "change_note/1" do
    test "GIVEN empty attrs WHEN calling change_note THEN returns a changeset" do
      assert %Ecto.Changeset{} = ShiftNotes.change_note()
    end

    test "GIVEN attrs WHEN calling change_note THEN returns changeset with data" do
      assert %Ecto.Changeset{} = ShiftNotes.change_note(%{"content" => "hola"})
    end
  end

  # ===========================================================================
  # ShiftNotes metadata helpers
  # ===========================================================================

  describe "category_label/1" do
    test "GIVEN known categories WHEN calling label THEN returns correct label" do
      assert ShiftNotes.category_label("stock") =~ "stock"
      assert ShiftNotes.category_label("preparacion") =~ "reparaci"
      assert ShiftNotes.category_label("equipo") =~ "quipo"
      assert ShiftNotes.category_label("general") =~ "eneral"
    end

    test "GIVEN unknown category WHEN calling label THEN returns general label" do
      assert ShiftNotes.category_label("unknown") =~ "eneral"
    end
  end

  describe "categories/0" do
    test "WHEN calling categories THEN returns list of tuples" do
      cats = ShiftNotes.categories()
      assert is_list(cats)
      assert length(cats) == 4
      values = Enum.map(cats, fn {_label, value} -> value end)
      assert "stock" in values
      assert "preparacion" in values
      assert "equipo" in values
      assert "general" in values
    end
  end

  # ===========================================================================
  # End-to-end flow
  # ===========================================================================

  describe "full shift notes flow" do
    test "create note → list active → resolve → list resolved → delete" do
      author = insert_user()
      resolver = insert_user()

      # Create
      {:ok, note} =
        ShiftNotes.create_note(
          %{"content" => "Se terminó el jarabe de vainilla.", "category" => "stock"},
          author.id
        )

      assert note.status == "active"

      # List active
      active = ShiftNotes.list_active_notes()
      assert Enum.any?(active, &(&1.id == note.id))

      # Resolve
      {:ok, resolved} = ShiftNotes.resolve_note(note.id, resolver.id)
      assert resolved.status == "resolved"

      # No longer in active list
      active_after = ShiftNotes.list_active_notes()
      refute Enum.any?(active_after, &(&1.id == note.id))

      # In recent resolved list
      recent = ShiftNotes.list_recent_resolved_notes()
      assert Enum.any?(recent, &(&1.id == note.id))
    end
  end
end
