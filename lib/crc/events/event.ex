defmodule CRC.Events.Event do
  @moduledoc """
  Schema representing an event at Café Raíces y Cultura.

  Events can have a type, collaborators (through event_collaborators),
  tags (stored as a Postgres array), and a date + time window.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "events" do
    field :title, :string
    field :description, :string
    field :event_date, :date
    field :start_time, :time
    field :end_time, :time
    field :tags, {:array, :string}, default: []
    field :active, :boolean, default: true

    belongs_to :event_type, CRC.Events.EventType

    has_many :event_collaborators, CRC.Events.EventCollaborator, on_replace: :delete

    many_to_many :collaborators, CRC.Events.Collaborator,
      join_through: CRC.Events.EventCollaborator,
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :title,
      :description,
      :event_type_id,
      :event_date,
      :start_time,
      :end_time,
      :tags,
      :active
    ])
    |> validate_required([:title, :event_date, :start_time, :end_time],
      message: "no puede estar en blanco"
    )
    |> validate_length(:title, min: 2, max: 200, message: "debe tener entre 2 y 200 caracteres")
    |> validate_end_after_start()
  end

  defp validate_end_after_start(changeset) do
    start_time = get_field(changeset, :start_time)
    end_time = get_field(changeset, :end_time)

    if start_time && end_time && Time.compare(end_time, start_time) != :gt do
      add_error(changeset, :end_time, "debe ser después de la hora de inicio")
    else
      changeset
    end
  end
end
