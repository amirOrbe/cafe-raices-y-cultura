defmodule CRC.Catalog.Category do
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Catalog.MenuItem

  schema "categories" do
    field :name, :string
    field :slug, :string
    field :active, :boolean, default: true

    has_many :menu_items, MenuItem, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :slug, :active])
    |> update_change(:name, &CRC.Utils.title_case/1)
    |> validate_required([:name])
    |> maybe_put_slug()
    |> unique_constraint(:slug)
  end

  defp maybe_put_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        name = get_field(changeset, :name) || ""
        put_change(changeset, :slug, to_slug(name))

      _existing ->
        changeset
    end
  end

  defp to_slug(name) do
    name
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end
end
