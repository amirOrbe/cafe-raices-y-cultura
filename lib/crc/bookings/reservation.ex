defmodule CRC.Bookings.Reservation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reservations" do
    field :name, :string
    field :email, :string
    field :phone, :string
    field :date, :date
    field :time, :time
    field :party_size, :integer
    field :notes, :string
    field :status, :string, default: "pending"

    timestamps(type: :utc_datetime)
  end

  @valid_statuses ~w(pending confirmed cancelled)
  @available_times ~w(09:00 09:30 10:00 10:30 11:00 11:30 12:00 12:30 13:00 13:30 14:00 14:30 15:00 15:30 16:00 16:30 17:00 17:30 18:00 18:30 19:00 19:30 20:00 20:30 21:00)

  def available_times, do: @available_times

  @doc false
  def changeset(reservation, attrs) do
    reservation
    |> cast(attrs, [:name, :email, :phone, :date, :time, :party_size, :notes, :status])
    |> validate_required([:name, :phone, :date, :time, :party_size])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "debe ser un correo válido")
    |> validate_format(:phone, ~r/^[\d\s\+\-\(\)]{7,20}$/, message: "debe ser un número válido")
    |> validate_number(:party_size, greater_than: 0, less_than_or_equal_to: 20)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_future_date()
  end

  defp validate_future_date(changeset) do
    case get_field(changeset, :date) do
      nil -> changeset
      date ->
        if Date.compare(date, Date.utc_today()) == :lt do
          add_error(changeset, :date, "debe ser una fecha futura")
        else
          changeset
        end
    end
  end
end
