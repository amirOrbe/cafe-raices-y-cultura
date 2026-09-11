defmodule CRC.CRM.LoyaltyReward do
  @moduledoc """
  Configuración de un beneficio de lealtad. Dos tipos (`kind`):

    * `"visits"`   — tarjeta perforada: al llegar a `visits_required` visitas el
      cliente gana el beneficio. `repeatable` = se vuelve a ganar cada bloque.
    * `"birthday"` — beneficio de cumpleaños. Solo una config activa a la vez.
      `birthday_window_days` amplía la ventana alrededor del día exacto.

  `benefit` es texto libre para el mostrador ("Café gratis"). Si además se
  configura `benefit_menu_item_id`, la redención inserta una línea a $0 de ese
  platillo en la comanda.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Catalog.MenuItem

  @kinds ~w(visits birthday)

  schema "loyalty_rewards" do
    field :kind, :string
    field :name, :string
    field :visits_required, :integer
    field :benefit, :string
    field :repeatable, :boolean, default: true
    field :birthday_window_days, :integer, default: 0
    field :active, :boolean, default: true

    belongs_to :benefit_menu_item, MenuItem

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  @doc false
  def changeset(reward, attrs) do
    reward
    |> cast(attrs, [
      :kind,
      :name,
      :visits_required,
      :benefit,
      :benefit_menu_item_id,
      :repeatable,
      :birthday_window_days,
      :active
    ])
    |> validate_required([:kind, :name, :benefit], message: "no puede estar en blanco")
    |> validate_inclusion(:kind, @kinds)
    |> validate_number(:birthday_window_days, greater_than_or_equal_to: 0)
    |> validate_visits_required()
    |> assoc_constraint(:benefit_menu_item)
    |> unique_constraint(:visits_required,
      name: :loyalty_rewards_unique_visits_required_index,
      message: "ya existe un nivel con ese número de visitas"
    )
    |> unique_constraint(:kind,
      name: :loyalty_rewards_one_active_birthday_index,
      message: "ya hay un beneficio de cumpleaños activo"
    )
  end

  defp validate_visits_required(changeset) do
    if get_field(changeset, :kind) == "visits" do
      changeset
      |> validate_required([:visits_required], message: "es requerido para niveles por visitas")
      |> validate_number(:visits_required, greater_than: 0)
    else
      put_change(changeset, :visits_required, nil)
    end
  end
end
