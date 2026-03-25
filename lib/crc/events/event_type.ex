defmodule CRC.Events.EventType do
  @moduledoc """
  Schema representing a type/category of event (e.g. Concierto, Taller, Lectura).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "event_types" do
    field :name, :string
    field :active, :boolean, default: true

    has_many :events, CRC.Events.Event

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event_type, attrs) do
    event_type
    |> cast(attrs, [:name, :active])
    |> validate_required([:name], message: "no puede estar en blanco")
    |> validate_length(:name, min: 2, max: 100, message: "debe tener entre 2 y 100 caracteres")
  end
end
