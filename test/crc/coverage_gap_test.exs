defmodule CRC.CoverageGapTest do
  @moduledoc """
  Supplemental tests targeting modules/functions not yet covered:
  - CRC.Utils
  - CRC.Events.EventPhoto (changeset + context functions)
  - CRC.Settings.available_windows/1
  - CRC.Orders.Order (manual_changeset, close_changeset)
  """
  use CRC.DataCase, async: true

  alias CRC.Utils
  alias CRC.Events
  alias CRC.Events.EventPhoto
  alias CRC.Settings
  alias CRC.Orders.Order

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_event(overrides \\ %{}) do
    tomorrow = Date.add(Date.utc_today(), 1)

    attrs =
      Map.merge(
        %{
          title: "Evento Test #{System.unique_integer()}",
          event_date: tomorrow,
          start_time: ~T[19:00:00],
          end_time: ~T[22:00:00]
        },
        overrides
      )

    {:ok, event} = Events.create_event(attrs, [])
    event
  end

  # ===========================================================================
  # CRC.Utils.title_case/1
  # ===========================================================================

  describe "CRC.Utils.title_case/1" do
    test "GIVEN nil WHEN title_casing THEN returns nil" do
      assert Utils.title_case(nil) == nil
    end

    test "GIVEN empty string WHEN title_casing THEN returns empty string" do
      assert Utils.title_case("") == ""
    end

    test "GIVEN lowercase string WHEN title_casing THEN capitalises each word" do
      assert Utils.title_case("leche evaporada") == "Leche Evaporada"
    end

    test "GIVEN uppercase string WHEN title_casing THEN converts to title case" do
      assert Utils.title_case("CAFÉ") == "Café"
    end

    test "GIVEN mixed-case multi-word WHEN title_casing THEN returns title case" do
      assert Utils.title_case("café de especialidad") == "Café De Especialidad"
    end

    test "GIVEN string with extra whitespace WHEN title_casing THEN trims and collapses" do
      result = Utils.title_case("  leche   entera  ")
      assert result == "Leche Entera"
    end

    test "GIVEN single word WHEN title_casing THEN capitalises first letter" do
      assert Utils.title_case("azúcar") == "Azúcar"
    end
  end

  # ===========================================================================
  # CRC.Events.EventPhoto.changeset/2
  # ===========================================================================

  describe "EventPhoto.changeset/2" do
    test "GIVEN valid attrs WHEN building changeset THEN it is valid" do
      event = insert_event()

      cs =
        EventPhoto.changeset(%EventPhoto{}, %{
          event_id: event.id,
          image_url: "https://example.com/photo.jpg"
        })

      assert cs.valid?
    end

    test "GIVEN missing image_url WHEN building changeset THEN invalid" do
      event = insert_event()

      cs = EventPhoto.changeset(%EventPhoto{}, %{event_id: event.id})
      refute cs.valid?
      assert cs.errors[:image_url]
    end

    test "GIVEN missing event_id WHEN building changeset THEN invalid" do
      cs = EventPhoto.changeset(%EventPhoto{}, %{image_url: "https://example.com/photo.jpg"})
      refute cs.valid?
      assert cs.errors[:event_id]
    end

    test "GIVEN valid attrs with caption WHEN building changeset THEN it is valid" do
      event = insert_event()

      cs =
        EventPhoto.changeset(%EventPhoto{}, %{
          event_id: event.id,
          image_url: "https://example.com/photo.jpg",
          caption: "Un momento especial"
        })

      assert cs.valid?
    end
  end

  # ===========================================================================
  # CRC.Events.add_event_photo/3 and list_event_photos/1 and delete_event_photo/1
  # ===========================================================================

  describe "Events.add_event_photo/3" do
    test "GIVEN existing event WHEN adding photo THEN photo is persisted" do
      event = insert_event()

      assert {:ok, %EventPhoto{} = photo} =
               Events.add_event_photo(event.id, "https://example.com/photo.jpg")

      assert photo.event_id == event.id
      assert photo.image_url == "https://example.com/photo.jpg"
    end

    test "GIVEN existing event WHEN adding photo with caption THEN caption is saved" do
      event = insert_event()

      {:ok, photo} =
        Events.add_event_photo(event.id, "https://example.com/photo2.jpg", "Foto de la noche")

      assert photo.caption == "Foto de la noche"
    end

    test "GIVEN invalid attrs WHEN adding photo THEN returns error" do
      event = insert_event()

      assert {:error, %Ecto.Changeset{}} = Events.add_event_photo(event.id, "")
    end
  end

  describe "Events.list_event_photos/1" do
    test "GIVEN event with photos WHEN listing THEN returns all photos" do
      event = insert_event()
      Events.add_event_photo(event.id, "https://example.com/photo1.jpg")
      Events.add_event_photo(event.id, "https://example.com/photo2.jpg")

      photos = Events.list_event_photos(event.id)
      assert length(photos) == 2
    end

    test "GIVEN event with no photos WHEN listing THEN returns empty list" do
      event = insert_event()
      assert Events.list_event_photos(event.id) == []
    end
  end

  describe "Events.delete_event_photo/1" do
    test "GIVEN existing photo WHEN deleting THEN returns ok and photo is gone" do
      event = insert_event()
      {:ok, photo} = Events.add_event_photo(event.id, "https://example.com/delete_me.jpg")

      assert {:ok, _} = Events.delete_event_photo(photo.id)

      photos = Events.list_event_photos(event.id)
      ids = Enum.map(photos, & &1.id)
      refute photo.id in ids
    end
  end

  # ===========================================================================
  # CRC.Settings.available_windows/1
  # ===========================================================================

  describe "Settings.available_windows/1" do
    test "GIVEN no hours configured for date WHEN checking windows THEN returns empty list" do
      # Use a specific date that definitely has no hours configured
      future_date = Date.add(Date.utc_today(), 30)
      assert Settings.available_windows(future_date) == []
    end

    test "GIVEN open day with no events WHEN checking windows THEN returns single full window" do
      today = Date.utc_today()
      day = Date.day_of_week(today)

      Settings.set_cafe_hours([
        %{
          day_of_week: day,
          opening_time: ~T[10:00:00],
          closing_time: ~T[22:00:00],
          is_closed: false
        }
      ])

      windows = Settings.available_windows(today)
      assert length(windows) == 1
      [{from, until}] = windows
      assert from == ~T[10:00:00]
      assert until == ~T[22:00:00]
    end

    test "GIVEN closed day WHEN checking windows THEN returns empty list" do
      today = Date.utc_today()
      day = Date.day_of_week(today)

      Settings.set_cafe_hours([
        %{
          day_of_week: day,
          opening_time: ~T[10:00:00],
          closing_time: ~T[22:00:00],
          is_closed: true
        }
      ])

      assert Settings.available_windows(today) == []
    end

    test "GIVEN open day with event blocking middle WHEN checking THEN returns 2 windows" do
      today = Date.utc_today()
      day = Date.day_of_week(today)

      Settings.set_cafe_hours([
        %{
          day_of_week: day,
          opening_time: ~T[10:00:00],
          closing_time: ~T[22:00:00],
          is_closed: false
        }
      ])

      # Insert an event that blocks 13:00–15:00
      {:ok, _event} =
        Events.create_event(
          %{
            title: "Evento Bloqueo",
            event_date: today,
            start_time: ~T[13:00:00],
            end_time: ~T[15:00:00]
          },
          []
        )

      windows = Settings.available_windows(today)
      # Should be: [10:00–13:00, 15:00–22:00]
      assert length(windows) == 2
    end
  end

  # ===========================================================================
  # CRC.Orders.Order.manual_changeset/2
  # ===========================================================================

  describe "Order.manual_changeset/2" do
    test "GIVEN valid attrs WHEN building manual changeset THEN it is valid" do
      cs =
        Order.manual_changeset(%Order{}, %{
          customer_name: "Mesa 5",
          payment_method: "efectivo",
          amount_paid: "150.00",
          total: "100.00",
          closed_at: DateTime.utc_now()
        })

      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :status) == "closed"
      assert Ecto.Changeset.get_change(cs, :manual_entry) == true
    end

    test "GIVEN missing customer_name WHEN building manual changeset THEN invalid" do
      cs =
        Order.manual_changeset(%Order{}, %{
          payment_method: "tarjeta",
          total: "100.00",
          closed_at: DateTime.utc_now()
        })

      refute cs.valid?
      assert cs.errors[:customer_name]
    end

    test "GIVEN cash payment without amount_paid WHEN building manual changeset THEN invalid" do
      cs =
        Order.manual_changeset(%Order{}, %{
          customer_name: "Mesa 3",
          payment_method: "efectivo",
          total: "80.00",
          closed_at: DateTime.utc_now()
        })

      refute cs.valid?
      assert cs.errors[:amount_paid]
    end

    test "GIVEN card payment without amount_paid WHEN building manual changeset THEN valid" do
      cs =
        Order.manual_changeset(%Order{}, %{
          customer_name: "Mesa 7",
          payment_method: "tarjeta",
          total: "200.00",
          closed_at: DateTime.utc_now()
        })

      assert cs.valid?
    end

    test "GIVEN invalid payment_method WHEN building manual changeset THEN invalid" do
      cs =
        Order.manual_changeset(%Order{}, %{
          customer_name: "Mesa 2",
          payment_method: "crypto",
          total: "100.00",
          closed_at: DateTime.utc_now()
        })

      refute cs.valid?
      assert cs.errors[:payment_method]
    end
  end

  # ===========================================================================
  # CRC.Orders.Order.close_changeset/2
  # ===========================================================================

  describe "Order.close_changeset/2" do
    test "GIVEN valid card payment WHEN building close changeset THEN it is valid" do
      cs =
        Order.close_changeset(%Order{}, %{
          status: "closed",
          payment_method: "tarjeta",
          total: "150.00"
        })

      assert cs.valid?
    end

    test "GIVEN valid transfer payment WHEN building close changeset THEN it is valid" do
      cs =
        Order.close_changeset(%Order{}, %{
          status: "closed",
          payment_method: "transferencia",
          total: "150.00"
        })

      assert cs.valid?
    end

    test "GIVEN cash payment with amount_paid WHEN building close changeset THEN valid" do
      cs =
        Order.close_changeset(%Order{}, %{
          status: "closed",
          payment_method: "efectivo",
          amount_paid: "200.00",
          total: "150.00"
        })

      assert cs.valid?
    end

    test "GIVEN cash without amount_paid WHEN building close changeset THEN invalid" do
      cs =
        Order.close_changeset(%Order{}, %{
          status: "closed",
          payment_method: "efectivo",
          total: "100.00"
        })

      refute cs.valid?
      assert cs.errors[:amount_paid]
    end

    test "GIVEN invalid status WHEN building close changeset THEN invalid" do
      cs =
        Order.close_changeset(%Order{}, %{
          status: "invalid",
          payment_method: "tarjeta",
          total: "100.00"
        })

      refute cs.valid?
      assert cs.errors[:status]
    end
  end
end
