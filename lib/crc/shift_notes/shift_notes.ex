defmodule CRC.ShiftNotes do
  @moduledoc "Context for shift handoff notes (bitácora de turno)."

  import Ecto.Query

  alias CRC.Repo
  alias CRC.ShiftNotes.ShiftNote

  @pubsub CRC.PubSub
  @topic "shift_notes"

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  # ---------------------------------------------------------------------------
  # Queries
  # ---------------------------------------------------------------------------

  def list_active_notes do
    ShiftNote
    |> where([n], n.status == "active")
    |> order_by([n], desc: n.inserted_at)
    |> preload([:author, :resolved_by])
    |> Repo.all()
  end

  def list_recent_resolved_notes(days \\ 3) do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    ShiftNote
    |> where([n], n.status == "resolved" and n.inserted_at >= ^cutoff)
    |> order_by([n], desc: n.resolved_at)
    |> preload([:author, :resolved_by])
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Mutations
  # ---------------------------------------------------------------------------

  def create_note(attrs, author_id) do
    attrs = Map.put(attrs, "author_id", author_id)

    case %ShiftNote{} |> ShiftNote.changeset(attrs) |> Repo.insert() do
      {:ok, note} ->
        note = Repo.preload(note, [:author, :resolved_by])
        broadcast({:note_created, note})
        {:ok, note}

      error ->
        error
    end
  end

  def resolve_note(note_id, resolved_by_id) do
    note = Repo.get!(ShiftNote, note_id)

    case ShiftNote.resolve_changeset(note, resolved_by_id) |> Repo.update() do
      {:ok, note} ->
        note = Repo.preload(note, [:author, :resolved_by])
        broadcast({:note_resolved, note})
        {:ok, note}

      error ->
        error
    end
  end

  def delete_note(note_id) do
    case Repo.get(ShiftNote, note_id) do
      nil ->
        :ok

      note ->
        case Repo.delete(note) do
          {:ok, _} ->
            broadcast({:note_deleted, note_id})
            :ok

          error ->
            error
        end
    end
  end

  def change_note(attrs \\ %{}) do
    ShiftNote.changeset(%ShiftNote{}, attrs)
  end

  # ---------------------------------------------------------------------------
  # Labels / metadata
  # ---------------------------------------------------------------------------

  def category_label("stock"),       do: "🔴 Alerta de stock"
  def category_label("preparacion"), do: "📋 Preparación"
  def category_label("equipo"),      do: "⚙️ Equipo"
  def category_label(_),             do: "💬 General"

  def categories do
    [
      {"🔴 Stock", "stock"},
      {"📋 Preparación", "preparacion"},
      {"⚙️ Equipo", "equipo"},
      {"💬 General", "general"}
    ]
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp broadcast(event), do: Phoenix.PubSub.broadcast(@pubsub, @topic, event)
end
