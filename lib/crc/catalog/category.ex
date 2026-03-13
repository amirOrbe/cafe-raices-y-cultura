defmodule CRC.Catalog.Category do
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Catalog.MenuItem

  schema "categories" do
    field :name, :string
    field :slug, :string
    field :position, :integer, default: 0
    field :kind, :string, default: "food"
    field :active, :boolean, default: true

    has_many :menu_items, MenuItem, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @valid_kinds ~w(food drink)

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :slug, :position, :kind, :active])
    |> validate_required([:name, :kind])
    |> validate_inclusion(:kind, @valid_kinds)
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
