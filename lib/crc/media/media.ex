defmodule CRC.Media do
  @moduledoc """
  The Media context manages photos for the carousel and gallery.
  """

  import Ecto.Query, warn: false
  alias CRC.Repo
  alias CRC.Media.Photo

  @doc "Returns all active photos ordered by position."
  def list_photos do
    Photo
    |> where(active: true)
    |> order_by(:position)
    |> Repo.all()
  end

  @doc "Returns all photos (including inactive) for admin use."
  def list_all_photos do
    Photo |> order_by(:position) |> Repo.all()
  end

  @doc "Gets a single photo. Raises if not found."
  def get_photo!(id), do: Repo.get!(Photo, id)

  @doc "Creates a photo."
  def create_photo(attrs \\ %{}) do
    %Photo{}
    |> Photo.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a photo."
  def update_photo(%Photo{} = photo, attrs) do
    photo
    |> Photo.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a photo."
  def delete_photo(%Photo{} = photo), do: Repo.delete(photo)
end
