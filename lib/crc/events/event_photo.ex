defmodule CRC.Events.EventPhoto do
  @moduledoc "Photo attached to a past event as evidence or gallery entry."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "event_photos" do
    field :image_url, :string
    field :caption, :string

    belongs_to :event, CRC.Events.Event

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:image_url, :caption, :event_id])
    |> validate_required([:image_url, :event_id])
  end
end
