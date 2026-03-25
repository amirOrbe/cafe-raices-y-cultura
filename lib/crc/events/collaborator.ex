defmodule CRC.Events.Collaborator do
  @moduledoc """
  Schema representing a collaborator (musician, poet, artist, barista, etc.)
  who can participate in events.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "collaborators" do
    field :name, :string
    field :bio, :string
    field :instagram_handle, :string
    field :active, :boolean, default: true

    has_many :event_collaborators, CRC.Events.EventCollaborator
    many_to_many :events, CRC.Events.Event, join_through: CRC.Events.EventCollaborator

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(collaborator, attrs) do
    collaborator
    |> cast(attrs, [:name, :bio, :instagram_handle, :active])
    |> validate_required([:name], message: "no puede estar en blanco")
    |> validate_length(:name, min: 2, max: 120, message: "debe tener entre 2 y 120 caracteres")
    |> validate_format(:instagram_handle, ~r/^[a-zA-Z0-9._]*$/,
      message: "solo puede contener letras, números, puntos y guiones bajos"
    )
  end
end
