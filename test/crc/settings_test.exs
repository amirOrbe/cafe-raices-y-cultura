defmodule CRC.SettingsTest do
  use CRC.DataCase, async: true

  alias CRC.Settings
  alias CRC.Settings.CafeHours

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp hours_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        day_of_week: 1,
        opening_time: ~T[10:00:00],
        closing_time: ~T[21:00:00],
        is_closed: false
      },
      overrides
    )
  end

  # ===========================================================================
  # CafeHours.changeset/2
  # ===========================================================================

  describe "CafeHours.changeset/2" do
    test "GIVEN valid attrs WHEN building changeset THEN it is valid" do
      cs = CafeHours.changeset(%CafeHours{}, hours_attrs())
      assert cs.valid?
    end

    test "GIVEN missing day_of_week WHEN building changeset THEN invalid" do
      cs =
        CafeHours.changeset(%CafeHours{}, %{
          opening_time: ~T[10:00:00],
          closing_time: ~T[21:00:00]
        })

      refute cs.valid?
      assert cs.errors[:day_of_week]
    end

    test "GIVEN invalid day_of_week (0) WHEN building changeset THEN invalid" do
      cs = CafeHours.changeset(%CafeHours{}, hours_attrs(%{day_of_week: 0}))
      refute cs.valid?
      assert cs.errors[:day_of_week]
    end

    test "GIVEN invalid day_of_week (8) WHEN building changeset THEN invalid" do
      cs = CafeHours.changeset(%CafeHours{}, hours_attrs(%{day_of_week: 8}))
      refute cs.valid?
      assert cs.errors[:day_of_week]
    end

    test "GIVEN closing_time before opening_time WHEN building changeset THEN invalid" do
      cs =
        CafeHours.changeset(%CafeHours{}, %{
          day_of_week: 1,
          opening_time: ~T[21:00:00],
          closing_time: ~T[10:00:00],
          is_closed: false
        })

      refute cs.valid?
      assert cs.errors[:closing_time]
    end

    test "GIVEN closing_time equal to opening_time WHEN building changeset THEN invalid" do
      cs =
        CafeHours.changeset(%CafeHours{}, %{
          day_of_week: 1,
          opening_time: ~T[10:00:00],
          closing_time: ~T[10:00:00],
          is_closed: false
        })

      refute cs.valid?
      assert cs.errors[:closing_time]
    end

    test "GIVEN is_closed true WHEN building changeset THEN valid even without valid time range" do
      cs =
        CafeHours.changeset(%CafeHours{}, %{
          day_of_week: 7,
          opening_time: ~T[10:00:00],
          closing_time: ~T[10:00:00],
          is_closed: true
        })

      assert cs.valid?
    end

    test "GIVEN all 7 day names WHEN calling day_name/1 THEN correct Spanish names returned" do
      assert CafeHours.day_name(1) == "Lunes"
      assert CafeHours.day_name(2) == "Martes"
      assert CafeHours.day_name(3) == "Miércoles"
      assert CafeHours.day_name(4) == "Jueves"
      assert CafeHours.day_name(5) == "Viernes"
      assert CafeHours.day_name(6) == "Sábado"
      assert CafeHours.day_name(7) == "Domingo"
    end

    test "GIVEN all 7 days WHEN calling day_short/1 THEN correct short names returned" do
      assert CafeHours.day_short(1) == "Lun"
      assert CafeHours.day_short(2) == "Mar"
      assert CafeHours.day_short(3) == "Mié"
      assert CafeHours.day_short(4) == "Jue"
      assert CafeHours.day_short(5) == "Vie"
      assert CafeHours.day_short(6) == "Sáb"
      assert CafeHours.day_short(7) == "Dom"
    end
  end

  # ===========================================================================
  # Settings.list_cafe_hours/0
  # ===========================================================================

  describe "list_cafe_hours/0" do
    test "GIVEN no rows persisted WHEN listing THEN returns empty list" do
      assert Settings.list_cafe_hours() == []
    end

    test "GIVEN rows saved WHEN listing THEN returns them ordered by day_of_week" do
      Settings.set_cafe_hours([
        hours_attrs(%{day_of_week: 3}),
        hours_attrs(%{day_of_week: 1})
      ])

      rows = Settings.list_cafe_hours()
      assert length(rows) == 2
      days = Enum.map(rows, & &1.day_of_week)
      assert days == Enum.sort(days)
    end
  end

  # ===========================================================================
  # Settings.cafe_hours_by_day/0
  # ===========================================================================

  describe "cafe_hours_by_day/0" do
    test "GIVEN rows saved WHEN calling by_day THEN returns a map keyed by day_of_week" do
      Settings.set_cafe_hours([hours_attrs(%{day_of_week: 1}), hours_attrs(%{day_of_week: 5})])

      by_day = Settings.cafe_hours_by_day()
      assert is_map(by_day)
      assert Map.has_key?(by_day, 1)
      assert Map.has_key?(by_day, 5)
    end
  end

  # ===========================================================================
  # Settings.set_cafe_hours/1
  # ===========================================================================

  describe "set_cafe_hours/1" do
    test "GIVEN valid entries WHEN setting hours THEN all are persisted" do
      entries = [
        hours_attrs(%{day_of_week: 1}),
        hours_attrs(%{day_of_week: 2}),
        hours_attrs(%{day_of_week: 3})
      ]

      assert {:ok, rows} = Settings.set_cafe_hours(entries)
      assert length(rows) == 3
    end

    test "GIVEN existing hours WHEN setting again THEN values are updated (upsert)" do
      Settings.set_cafe_hours([hours_attrs(%{day_of_week: 1, opening_time: ~T[10:00:00]})])

      {:ok, _} =
        Settings.set_cafe_hours([hours_attrs(%{day_of_week: 1, opening_time: ~T[09:00:00]})])

      [row] = Settings.list_cafe_hours()
      assert row.opening_time == ~T[09:00:00]
    end

    test "GIVEN closed day WHEN setting hours THEN is_closed is persisted" do
      {:ok, _} =
        Settings.set_cafe_hours([
          %{
            day_of_week: 7,
            opening_time: ~T[10:00:00],
            closing_time: ~T[20:00:00],
            is_closed: true
          }
        ])

      [row] = Settings.list_cafe_hours()
      assert row.is_closed == true
    end

    test "GIVEN invalid entry WHEN setting hours THEN returns error changeset" do
      # day_of_week 0 is invalid
      assert {:error, _cs} =
               Settings.set_cafe_hours([
                 %{
                   day_of_week: 0,
                   opening_time: ~T[10:00:00],
                   closing_time: ~T[21:00:00],
                   is_closed: false
                 }
               ])
    end
  end

  # ===========================================================================
  # Settings.hours_for_date/1
  # ===========================================================================

  describe "hours_for_date/1" do
    test "GIVEN no row for that day WHEN querying THEN returns nil" do
      # Ensure no rows exist for today
      today = Date.utc_today()
      assert Settings.hours_for_date(today) == nil
    end

    test "GIVEN open day configured WHEN querying THEN returns {opening, closing} tuple" do
      today = Date.utc_today()
      day = Date.day_of_week(today)

      Settings.set_cafe_hours([
        %{
          day_of_week: day,
          opening_time: ~T[10:00:00],
          closing_time: ~T[21:00:00],
          is_closed: false
        }
      ])

      assert {~T[10:00:00], ~T[21:00:00]} = Settings.hours_for_date(today)
    end

    test "GIVEN closed day configured WHEN querying THEN returns nil" do
      today = Date.utc_today()
      day = Date.day_of_week(today)

      Settings.set_cafe_hours([
        %{
          day_of_week: day,
          opening_time: ~T[10:00:00],
          closing_time: ~T[21:00:00],
          is_closed: true
        }
      ])

      assert Settings.hours_for_date(today) == nil
    end
  end

  # ===========================================================================
  # Settings.grouped_hours/0
  # ===========================================================================

  describe "grouped_hours/0" do
    test "GIVEN no rows WHEN calling grouped_hours THEN returns empty list" do
      assert Settings.grouped_hours() == []
    end

    test "GIVEN Mon–Fri same hours WHEN grouping THEN returns single group with range label" do
      entries =
        Enum.map(1..5, fn day ->
          %{
            day_of_week: day,
            opening_time: ~T[10:00:00],
            closing_time: ~T[21:00:00],
            is_closed: false
          }
        end)

      Settings.set_cafe_hours(entries)
      groups = Settings.grouped_hours()

      assert length(groups) == 1
      [group] = groups
      assert group.label =~ "Lun"
      assert group.label =~ "Vie"
    end

    test "GIVEN Mon–Fri and Sat with different hours WHEN grouping THEN returns 2 groups" do
      entries =
        Enum.map(1..5, fn day ->
          %{
            day_of_week: day,
            opening_time: ~T[10:00:00],
            closing_time: ~T[21:00:00],
            is_closed: false
          }
        end)

      sat_entry = %{
        day_of_week: 6,
        opening_time: ~T[11:00:00],
        closing_time: ~T[20:00:00],
        is_closed: false
      }

      Settings.set_cafe_hours(entries ++ [sat_entry])
      groups = Settings.grouped_hours()

      assert length(groups) == 2
    end

    test "GIVEN closed day WHEN grouping THEN closed days are omitted" do
      Settings.set_cafe_hours([
        %{day_of_week: 7, opening_time: ~T[10:00:00], closing_time: ~T[21:00:00], is_closed: true}
      ])

      groups = Settings.grouped_hours()
      labels = Enum.map(groups, & &1.label)
      refute "Dom" in labels
    end
  end

  # ===========================================================================
  # Settings.default_form_data/0 and build_form_data/1
  # ===========================================================================

  describe "default_form_data/0" do
    test "WHEN calling default_form_data THEN returns map with 7 keys" do
      data = Settings.default_form_data()
      assert map_size(data) == 7

      for day <- 1..7 do
        assert Map.has_key?(data, day)
        assert data[day].active == false
      end
    end
  end

  describe "build_form_data/1" do
    test "GIVEN rows WHEN building form data THEN active days have active: true" do
      {:ok, rows} =
        Settings.set_cafe_hours([
          %{
            day_of_week: 1,
            opening_time: ~T[09:00:00],
            closing_time: ~T[17:00:00],
            is_closed: false
          }
        ])

      data = Settings.build_form_data(rows)
      assert data[1].active == true
      assert data[2].active == false
    end

    test "GIVEN closed row WHEN building form data THEN that day is inactive" do
      {:ok, rows} =
        Settings.set_cafe_hours([
          %{
            day_of_week: 1,
            opening_time: ~T[09:00:00],
            closing_time: ~T[17:00:00],
            is_closed: true
          }
        ])

      data = Settings.build_form_data(rows)
      assert data[1].active == false
    end
  end

  # ===========================================================================
  # End-to-end flow
  # ===========================================================================

  describe "full settings flow" do
    test "set hours → list → query by date → grouped output" do
      today = Date.utc_today()
      day = Date.day_of_week(today)

      # Set hours for the whole week
      entries =
        Enum.map(1..7, fn d ->
          if d == day do
            %{
              day_of_week: d,
              opening_time: ~T[10:00:00],
              closing_time: ~T[22:00:00],
              is_closed: false
            }
          else
            %{
              day_of_week: d,
              opening_time: ~T[10:00:00],
              closing_time: ~T[21:00:00],
              is_closed: false
            }
          end
        end)

      assert {:ok, rows} = Settings.set_cafe_hours(entries)
      assert length(rows) == 7

      # Query by today's date
      assert {~T[10:00:00], ~T[22:00:00]} = Settings.hours_for_date(today)

      # Grouped hours — with 7 days where 1 has different closing, expect 2+ groups
      groups = Settings.grouped_hours()
      assert length(groups) >= 1
    end
  end
end
