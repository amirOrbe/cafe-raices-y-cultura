defmodule CRC.Media.Photo do
  use Ecto.Schema
  import Ecto.Changeset

  schema "photos" do
    field :url, :string
    field :caption, :string
    field :position, :integer, default: 0
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:url, :caption, :position, :active])
    |> validate_required([:url])
    |> validate_url(:url)
  end

  defp validate_url(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      url ->
        if String.starts_with?(url, ["http://", "https://", "/"]) do
          changeset
        else
          add_error(changeset, field, "debe ser una URL válida")
        end
    end
  end
end
