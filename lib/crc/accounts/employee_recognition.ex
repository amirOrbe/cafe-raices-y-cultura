defmodule CRC.Accounts.EmployeeRecognition do
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Accounts.User

  @valid_kinds ~w(top_sales top_speed custom)

  schema "employee_recognitions" do
    belongs_to :user, User
    belongs_to :given_by, User

    field :kind, :string
    field :note, :string
    field :period_date, :date

    timestamps(type: :utc_datetime)
  end

  def changeset(recognition, attrs) do
    recognition
    |> cast(attrs, [:user_id, :given_by_id, :kind, :note, :period_date])
    |> validate_required([:user_id, :kind, :period_date])
    |> validate_inclusion(:kind, @valid_kinds, message: "tipo de reconocimiento inválido")
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:given_by_id)
  end
end
