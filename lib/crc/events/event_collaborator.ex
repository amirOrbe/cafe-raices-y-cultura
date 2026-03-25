defmodule CRC.Events.EventCollaborator do
  @moduledoc """
  Join table schema connecting events and collaborators,
  with an optional role_in_event field.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "event_collaborators" do
    field :role_in_event, :string

    belongs_to :event, CRC.Events.Event
    belongs_to :collaborator, CRC.Events.Collaborator

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event_collaborator, attrs) do
    event_collaborator
    |> cast(attrs, [:event_id, :collaborator_id, :role_in_event])
    |> validate_required([:event_id, :collaborator_id])
  end
end
