defmodule CRC.Bookings do
  @moduledoc """
  The Bookings context manages table reservations.
  """

  import Ecto.Query, warn: false
  alias CRC.Repo
  alias CRC.Bookings.Reservation

  @doc "Returns a list of all reservations."
  def list_reservations do
    Reservation
    |> order_by([:date, :time])
    |> Repo.all()
  end

  @doc "Returns reservations for a given date."
  def list_reservations_for_date(%Date{} = date) do
    Reservation
    |> where(date: ^date, status: "confirmed")
    |> order_by(:time)
    |> Repo.all()
  end

  @doc "Gets a single reservation. Raises if not found."
  def get_reservation!(id), do: Repo.get!(Reservation, id)

  @doc "Creates a reservation from the booking form."
  def create_reservation(attrs \\ %{}) do
    %Reservation{}
    |> Reservation.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a reservation."
  def update_reservation(%Reservation{} = reservation, attrs) do
    reservation
    |> Reservation.changeset(attrs)
    |> Repo.update()
  end

  @doc "Returns a fresh changeset for the booking form."
  def change_reservation(%Reservation{} = reservation \\ %Reservation{}, attrs \\ %{}) do
    Reservation.changeset(reservation, attrs)
  end
end
