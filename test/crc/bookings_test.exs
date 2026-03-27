defmodule CRC.BookingsTest do
  use CRC.DataCase, async: true

  alias CRC.Bookings
  alias CRC.Bookings.Reservation

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp future_date do
    Date.add(Date.utc_today(), 7)
  end

  defp reservation_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "María López",
        phone: "55 1234 5678",
        date: future_date(),
        time: ~T[14:00:00],
        party_size: 2,
        status: "pending"
      },
      overrides
    )
  end

  defp insert_reservation(overrides \\ %{}) do
    {:ok, res} = Bookings.create_reservation(reservation_attrs(overrides))
    res
  end

  # ===========================================================================
  # Reservation.changeset/2
  # ===========================================================================

  describe "Reservation.changeset/2" do
    test "válido con todos los campos requeridos" do
      changeset = Reservation.changeset(%Reservation{}, reservation_attrs())
      assert changeset.valid?
    end

    test "inválido sin nombre" do
      changeset = Reservation.changeset(%Reservation{}, reservation_attrs(%{name: nil}))
      refute changeset.valid?
      assert changeset.errors[:name]
    end

    test "inválido sin teléfono" do
      changeset = Reservation.changeset(%Reservation{}, reservation_attrs(%{phone: nil}))
      refute changeset.valid?
      assert changeset.errors[:phone]
    end

    test "inválido sin fecha" do
      changeset = Reservation.changeset(%Reservation{}, reservation_attrs(%{date: nil}))
      refute changeset.valid?
      assert changeset.errors[:date]
    end

    test "inválido sin hora" do
      changeset = Reservation.changeset(%Reservation{}, reservation_attrs(%{time: nil}))
      refute changeset.valid?
      assert changeset.errors[:time]
    end

    test "inválido sin tamaño de grupo" do
      changeset = Reservation.changeset(%Reservation{}, reservation_attrs(%{party_size: nil}))
      refute changeset.valid?
      assert changeset.errors[:party_size]
    end

    test "inválido con party_size <= 0" do
      changeset = Reservation.changeset(%Reservation{}, reservation_attrs(%{party_size: 0}))
      refute changeset.valid?
      assert changeset.errors[:party_size]
    end

    test "inválido con party_size > 20" do
      changeset = Reservation.changeset(%Reservation{}, reservation_attrs(%{party_size: 21}))
      refute changeset.valid?
      assert changeset.errors[:party_size]
    end

    test "inválido con fecha en el pasado" do
      past_date = Date.add(Date.utc_today(), -1)
      changeset = Reservation.changeset(%Reservation{}, reservation_attrs(%{date: past_date}))
      refute changeset.valid?
      assert changeset.errors[:date]
    end

    test "email es opcional" do
      changeset = Reservation.changeset(%Reservation{}, reservation_attrs(%{email: nil}))
      assert changeset.valid?
    end

    test "email inválido es rechazado" do
      changeset = Reservation.changeset(%Reservation{}, reservation_attrs(%{email: "no-es-email"}))
      refute changeset.valid?
      assert changeset.errors[:email]
    end

    test "status tiene default pending" do
      {:ok, res} = Bookings.create_reservation(Map.delete(reservation_attrs(), :status))
      assert res.status == "pending"
    end

    test "status inválido es rechazado" do
      changeset = Reservation.changeset(%Reservation{}, reservation_attrs(%{status: "unknown"}))
      refute changeset.valid?
      assert changeset.errors[:status]
    end

    test "statuses válidos: pending, confirmed, cancelled" do
      for status <- ~w(pending confirmed cancelled) do
        changeset = Reservation.changeset(%Reservation{}, reservation_attrs(%{status: status}))
        assert changeset.valid?, "esperaba válido con status=#{status}"
      end
    end

    test "nombre demasiado corto es inválido" do
      changeset = Reservation.changeset(%Reservation{}, reservation_attrs(%{name: "A"}))
      refute changeset.valid?
      assert changeset.errors[:name]
    end
  end

  # ===========================================================================
  # list_reservations/0
  # ===========================================================================

  describe "list_reservations/0" do
    test "retorna todas las reservaciones ordenadas por fecha y hora" do
      insert_reservation(%{
        date: Date.add(Date.utc_today(), 10),
        time: ~T[18:00:00],
        name: "Tercera"
      })

      insert_reservation(%{
        date: Date.add(Date.utc_today(), 5),
        time: ~T[10:00:00],
        name: "Primera"
      })

      insert_reservation(%{
        date: Date.add(Date.utc_today(), 5),
        time: ~T[14:00:00],
        name: "Segunda"
      })

      reservations = Bookings.list_reservations()

      assert length(reservations) == 3
      names = Enum.map(reservations, & &1.name)
      assert names == ["Primera", "Segunda", "Tercera"]
    end
  end

  # ===========================================================================
  # list_reservations_for_date/1
  # ===========================================================================

  describe "list_reservations_for_date/1" do
    test "retorna solo reservaciones confirmadas para la fecha" do
      target_date = Date.add(Date.utc_today(), 3)

      insert_reservation(%{date: target_date, status: "confirmed", name: "Confirmada"})
      insert_reservation(%{date: target_date, status: "pending", name: "Pendiente"})
      insert_reservation(%{
        date: Date.add(target_date, 1),
        status: "confirmed",
        name: "Otra fecha"
      })

      results = Bookings.list_reservations_for_date(target_date)
      names = Enum.map(results, & &1.name)

      assert "Confirmada" in names
      refute "Pendiente" in names
      refute "Otra fecha" in names
    end

    test "retorna lista vacía si no hay reservas confirmadas para la fecha" do
      future = Date.add(Date.utc_today(), 20)
      assert Bookings.list_reservations_for_date(future) == []
    end
  end

  # ===========================================================================
  # get_reservation!/1
  # ===========================================================================

  describe "get_reservation!/1" do
    test "retorna la reservación por id" do
      res = insert_reservation()
      assert Bookings.get_reservation!(res.id).id == res.id
    end

    test "lanza excepción si no existe" do
      assert_raise Ecto.NoResultsError, fn -> Bookings.get_reservation!(0) end
    end
  end

  # ===========================================================================
  # create_reservation/1
  # ===========================================================================

  describe "create_reservation/1" do
    test "crea reservación con datos válidos" do
      assert {:ok, %Reservation{name: "María López"}} =
               Bookings.create_reservation(reservation_attrs())
    end

    test "falla con datos inválidos" do
      assert {:error, %Ecto.Changeset{}} = Bookings.create_reservation(%{name: nil})
    end
  end

  # ===========================================================================
  # update_reservation/2
  # ===========================================================================

  describe "update_reservation/2" do
    test "actualiza la reservación exitosamente" do
      res = insert_reservation()
      assert {:ok, updated} = Bookings.update_reservation(res, %{status: "confirmed"})
      assert updated.status == "confirmed"
    end

    test "falla con datos inválidos" do
      res = insert_reservation()
      assert {:error, %Ecto.Changeset{}} = Bookings.update_reservation(res, %{party_size: 0})
    end
  end

  # ===========================================================================
  # change_reservation/2
  # ===========================================================================

  describe "change_reservation/2" do
    test "retorna un changeset vacío para nueva reservación" do
      cs = Bookings.change_reservation(%Reservation{})
      assert %Ecto.Changeset{} = cs
    end

    test "retorna un changeset con los attrs dados" do
      cs = Bookings.change_reservation(%Reservation{}, %{name: "Juan"})
      assert %Ecto.Changeset{} = cs
    end
  end

  describe "Reservation.available_times/0" do
    test "returns list of available time slots" do
      times = Reservation.available_times()
      assert is_list(times)
      assert length(times) > 0
    end
  end

  describe "create_reservation/0 default arg" do
    test "returns error with empty attrs (required fields missing)" do
      assert {:error, %Ecto.Changeset{}} = Bookings.create_reservation()
    end
  end
end
