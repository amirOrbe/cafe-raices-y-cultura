defmodule CRC.ShiftNotes.ShiftNote do
  @moduledoc "Schema for a shift handoff note (bitácora de turno)."

  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Accounts.User

  schema "shift_notes" do
    field :content, :string
    field :category, :string, default: "general"
    field :status, :string, default: "active"
    field :resolved_at, :utc_datetime

    belongs_to :author, User
    belongs_to :resolved_by, User

    timestamps(type: :utc_datetime)
  end

  @valid_categories ~w(stock preparacion equipo general)

  def changeset(shift_note, attrs) do
    shift_note
    |> cast(attrs, [:content, :category, :author_id])
    |> validate_required([:content, :author_id])
    |> validate_length(:content, min: 2, max: 500)
    |> validate_inclusion(:category, @valid_categories)
    |> put_change(:status, "active")
  end

  def resolve_changeset(shift_note, resolved_by_id) do
    shift_note
    |> change(%{
      status: "resolved",
      resolved_by_id: resolved_by_id,
      resolved_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end
end
