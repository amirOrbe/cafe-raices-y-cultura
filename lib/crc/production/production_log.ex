defmodule CRC.Production.ProductionLog do
  @moduledoc "Records when a production batch was actually made."

  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Accounts.User
  alias CRC.Production.Recipe

  schema "production_logs" do
    field :batches, :decimal
    field :notes, :string
    field :produced_at, :utc_datetime

    belongs_to :recipe, Recipe
    belongs_to :produced_by, User, foreign_key: :produced_by_id

    timestamps(type: :utc_datetime)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:recipe_id, :batches, :notes, :produced_by_id, :produced_at])
    |> validate_required([:recipe_id, :batches, :produced_at],
      message: "no puede estar en blanco"
    )
    |> validate_number(:batches, greater_than: 0, message: "debe ser mayor a 0")
  end
end
