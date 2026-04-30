defmodule CRC.HRTest do
  use CRC.DataCase, async: true

  alias CRC.HR
  alias CRC.HR.{WorkSchedule, AttendanceRecord}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Test User",
          email: "user#{System.unique_integer()}@cafe.com",
          role: "empleado",
          stations: ["sala"],
          password: "contraseña123"
        },
        overrides
      )

    {:ok, user} =
      %CRC.Accounts.User{}
      |> CRC.Accounts.User.changeset(attrs)
      |> CRC.Repo.insert()

    user
  end

  defp insert_admin(overrides \\ %{}) do
    insert_user(Map.merge(%{role: "admin", stations: []}, overrides))
  end

  # Coordinates within 350 m of the café (Dr. Mariano Azuela #80, CDMX)
  @near_lat 19.445424998689816
  @near_lng -99.15739759497082

  # Coordinates clearly outside 350 m
  @far_lat 19.420
  @far_lng -99.160

  # ===========================================================================
  # WorkSchedule.changeset/2
  # ===========================================================================

  describe "WorkSchedule.changeset/2" do
    test "GIVEN valid attrs WHEN building changeset THEN it is valid" do
      user = insert_user()

      cs =
        WorkSchedule.changeset(%WorkSchedule{}, %{
          user_id: user.id,
          day_of_week: 1,
          start_time: ~T[08:00:00],
          end_time: ~T[16:00:00]
        })

      assert cs.valid?
    end

    test "GIVEN missing user_id WHEN building changeset THEN invalid" do
      cs =
        WorkSchedule.changeset(%WorkSchedule{}, %{
          day_of_week: 1,
          start_time: ~T[08:00:00],
          end_time: ~T[16:00:00]
        })

      refute cs.valid?
      assert cs.errors[:user_id]
    end

    test "GIVEN invalid day_of_week (0) WHEN building changeset THEN invalid" do
      user = insert_user()

      cs =
        WorkSchedule.changeset(%WorkSchedule{}, %{
          user_id: user.id,
          day_of_week: 0,
          start_time: ~T[08:00:00],
          end_time: ~T[16:00:00]
        })

      refute cs.valid?
      assert cs.errors[:day_of_week]
    end

    test "GIVEN invalid day_of_week (8) WHEN building changeset THEN invalid" do
      user = insert_user()

      cs =
        WorkSchedule.changeset(%WorkSchedule{}, %{
          user_id: user.id,
          day_of_week: 8,
          start_time: ~T[08:00:00],
          end_time: ~T[16:00:00]
        })

      refute cs.valid?
      assert cs.errors[:day_of_week]
    end

    test "GIVEN end_time before start_time WHEN building changeset THEN invalid" do
      user = insert_user()

      cs =
        WorkSchedule.changeset(%WorkSchedule{}, %{
          user_id: user.id,
          day_of_week: 2,
          start_time: ~T[16:00:00],
          end_time: ~T[08:00:00]
        })

      refute cs.valid?
      assert cs.errors[:end_time]
    end

    test "GIVEN end_time equal to start_time WHEN building changeset THEN invalid" do
      user = insert_user()

      cs =
        WorkSchedule.changeset(%WorkSchedule{}, %{
          user_id: user.id,
          day_of_week: 3,
          start_time: ~T[10:00:00],
          end_time: ~T[10:00:00]
        })

      refute cs.valid?
      assert cs.errors[:end_time]
    end

    test "GIVEN all 7 day names WHEN calling day_name/1 THEN correct Spanish names returned" do
      assert WorkSchedule.day_name(1) == "Lunes"
      assert WorkSchedule.day_name(2) == "Martes"
      assert WorkSchedule.day_name(3) == "Miércoles"
      assert WorkSchedule.day_name(4) == "Jueves"
      assert WorkSchedule.day_name(5) == "Viernes"
      assert WorkSchedule.day_name(6) == "Sábado"
      assert WorkSchedule.day_name(7) == "Domingo"
    end

    test "GIVEN all 7 days WHEN calling day_short/1 THEN correct short names returned" do
      assert WorkSchedule.day_short(1) == "Lun"
      assert WorkSchedule.day_short(2) == "Mar"
      assert WorkSchedule.day_short(3) == "Mié"
      assert WorkSchedule.day_short(4) == "Jue"
      assert WorkSchedule.day_short(5) == "Vie"
      assert WorkSchedule.day_short(6) == "Sáb"
      assert WorkSchedule.day_short(7) == "Dom"
    end
  end

  # ===========================================================================
  # AttendanceRecord.changeset/2
  # ===========================================================================

  describe "AttendanceRecord.changeset/2" do
    test "GIVEN valid attrs WHEN building changeset THEN it is valid" do
      user = insert_user()

      cs =
        AttendanceRecord.changeset(%AttendanceRecord{}, %{
          user_id: user.id,
          date: Date.utc_today(),
          status: "absent"
        })

      assert cs.valid?
    end

    test "GIVEN invalid status WHEN building changeset THEN invalid" do
      user = insert_user()

      cs =
        AttendanceRecord.changeset(%AttendanceRecord{}, %{
          user_id: user.id,
          date: Date.utc_today(),
          status: "unknown"
        })

      refute cs.valid?
      assert cs.errors[:status]
    end

    test "GIVEN missing date WHEN building changeset THEN invalid" do
      user = insert_user()

      cs =
        AttendanceRecord.changeset(%AttendanceRecord{}, %{
          user_id: user.id,
          status: "absent"
        })

      refute cs.valid?
      assert cs.errors[:date]
    end

    test "GIVEN statuses/0 WHEN called THEN returns all 4 status values" do
      statuses = AttendanceRecord.statuses()
      assert "early" in statuses
      assert "on_time" in statuses
      assert "late" in statuses
      assert "absent" in statuses
      assert length(statuses) == 4
    end
  end

  # ===========================================================================
  # HR.list_work_schedules/1
  # ===========================================================================

  describe "list_work_schedules/1" do
    test "GIVEN user with no schedules WHEN listing THEN returns empty list" do
      user = insert_user()
      assert HR.list_work_schedules(user.id) == []
    end

    test "GIVEN user with schedules WHEN listing THEN returns all schedules ordered" do
      user = insert_user()

      {:ok, _} =
        HR.set_work_schedules(user.id, [
          %{day_of_week: 3, start_time: ~T[08:00:00], end_time: ~T[16:00:00]},
          %{day_of_week: 1, start_time: ~T[09:00:00], end_time: ~T[17:00:00]}
        ])

      schedules = HR.list_work_schedules(user.id)
      assert length(schedules) == 2
      days = Enum.map(schedules, & &1.day_of_week)
      assert days == Enum.sort(days)
    end
  end

  # ===========================================================================
  # HR.set_work_schedules/2
  # ===========================================================================

  describe "set_work_schedules/2" do
    test "GIVEN valid entries WHEN setting schedules THEN all are persisted" do
      user = insert_user()

      entries = [
        %{day_of_week: 1, start_time: ~T[08:00:00], end_time: ~T[16:00:00]},
        %{day_of_week: 2, start_time: ~T[08:00:00], end_time: ~T[16:00:00]},
        %{day_of_week: 5, start_time: ~T[10:00:00], end_time: ~T[18:00:00]}
      ]

      assert {:ok, schedules} = HR.set_work_schedules(user.id, entries)
      assert length(schedules) == 3
    end

    test "GIVEN existing schedules WHEN setting new ones THEN old schedules are replaced" do
      user = insert_user()

      HR.set_work_schedules(user.id, [
        %{day_of_week: 1, start_time: ~T[08:00:00], end_time: ~T[16:00:00]},
        %{day_of_week: 2, start_time: ~T[08:00:00], end_time: ~T[16:00:00]}
      ])

      {:ok, schedules} =
        HR.set_work_schedules(user.id, [
          %{day_of_week: 5, start_time: ~T[10:00:00], end_time: ~T[18:00:00]}
        ])

      assert length(schedules) == 1
      assert hd(schedules).day_of_week == 5
    end

    test "GIVEN empty entries WHEN setting schedules THEN all existing schedules cleared" do
      user = insert_user()

      HR.set_work_schedules(user.id, [
        %{day_of_week: 1, start_time: ~T[08:00:00], end_time: ~T[16:00:00]}
      ])

      {:ok, schedules} = HR.set_work_schedules(user.id, [])
      assert schedules == []
    end
  end

  # ===========================================================================
  # HR.get_schedule_for_day/2
  # ===========================================================================

  describe "get_schedule_for_day/2" do
    test "GIVEN user with Monday schedule WHEN querying Monday THEN returns schedule" do
      user = insert_user()

      HR.set_work_schedules(user.id, [
        %{day_of_week: 1, start_time: ~T[08:00:00], end_time: ~T[16:00:00]}
      ])

      result = HR.get_schedule_for_day(user.id, 1)
      assert result
      assert result.day_of_week == 1
    end

    test "GIVEN user without Tuesday schedule WHEN querying Tuesday THEN returns nil" do
      user = insert_user()

      HR.set_work_schedules(user.id, [
        %{day_of_week: 1, start_time: ~T[08:00:00], end_time: ~T[16:00:00]}
      ])

      assert HR.get_schedule_for_day(user.id, 2) == nil
    end
  end

  # ===========================================================================
  # HR.get_or_create_today_record/1
  # ===========================================================================

  describe "get_or_create_today_record/1" do
    test "GIVEN user with no record today WHEN calling THEN creates and returns record" do
      user = insert_user()
      record = HR.get_or_create_today_record(user)

      assert record.user_id == user.id
      assert record.date == Date.utc_today()
      assert record.status == "absent"
    end

    test "GIVEN user with existing record today WHEN calling again THEN returns same record" do
      user = insert_user()
      first = HR.get_or_create_today_record(user)
      second = HR.get_or_create_today_record(user)

      assert first.id == second.id
    end

    test "GIVEN user with schedule for today WHEN creating record THEN scheduled times are snapshotted" do
      user = insert_user()
      today = Date.utc_today()
      day_of_week = Date.day_of_week(today)

      HR.set_work_schedules(user.id, [
        %{day_of_week: day_of_week, start_time: ~T[09:00:00], end_time: ~T[17:00:00]}
      ])

      record = HR.get_or_create_today_record(user)
      assert record.scheduled_start == ~T[09:00:00]
      assert record.scheduled_end == ~T[17:00:00]
    end
  end

  # ===========================================================================
  # HR.get_attendance_record/2
  # ===========================================================================

  describe "get_attendance_record/2" do
    test "GIVEN no record for date WHEN querying THEN returns nil" do
      user = insert_user()
      yesterday = Date.add(Date.utc_today(), -1)
      assert HR.get_attendance_record(user.id, yesterday) == nil
    end

    test "GIVEN existing record WHEN querying THEN returns it" do
      user = insert_user()
      record = HR.get_or_create_today_record(user)

      found = HR.get_attendance_record(user.id, Date.utc_today())
      assert found.id == record.id
    end
  end

  # ===========================================================================
  # HR.near_cafe?/2
  # ===========================================================================

  describe "near_cafe?/2" do
    test "GIVEN coordinates AT the café WHEN checking THEN returns true" do
      assert HR.near_cafe?(@near_lat, @near_lng)
    end

    test "GIVEN coordinates far from the café WHEN checking THEN returns false" do
      refute HR.near_cafe?(@far_lat, @far_lng)
    end

    test "GIVEN coordinates just within 350m WHEN checking THEN returns true" do
      # Offset ~100 m north
      assert HR.near_cafe?(@near_lat + 0.0009, @near_lng)
    end

    test "GIVEN coordinates beyond 350m WHEN checking THEN returns false" do
      # Offset ~2 km north
      refute HR.near_cafe?(@near_lat + 0.018, @near_lng)
    end
  end

  # ===========================================================================
  # HR.clock_in/3
  # ===========================================================================

  describe "clock_in/3" do
    test "GIVEN employee near café WHEN clocking in THEN returns ok with record" do
      user = insert_user()

      assert {:ok, record} = HR.clock_in(user, @near_lat, @near_lng)
      assert record.user_id == user.id
      assert record.clocked_in_at
      assert record.latitude == @near_lat
      assert record.longitude == @near_lng
    end

    test "GIVEN employee far from café WHEN clocking in THEN returns :too_far" do
      user = insert_user()

      assert {:error, :too_far} = HR.clock_in(user, @far_lat, @far_lng)
    end

    test "GIVEN employee already clocked in WHEN clocking in again THEN returns :already_clocked_in" do
      user = insert_user()

      {:ok, _} = HR.clock_in(user, @near_lat, @near_lng)

      assert {:error, :already_clocked_in} = HR.clock_in(user, @near_lat, @near_lng)
    end

    test "GIVEN user with no schedule WHEN clocking in near café THEN status is on_time" do
      user = insert_user()

      {:ok, record} = HR.clock_in(user, @near_lat, @near_lng)
      assert record.status == "on_time"
    end
  end

  # ===========================================================================
  # HR.clock_in_manual/3
  # ===========================================================================

  describe "clock_in_manual/3" do
    test "GIVEN admin and employee WHEN registering manual clock-in at current time THEN succeeds" do
      admin = insert_admin()
      employee = insert_user()

      now = DateTime.utc_now()
      assert {:ok, record} = HR.clock_in_manual(admin, employee, now)
      assert record.manual_entry == true
      assert record.clocked_in_at
    end

    test "GIVEN employee with schedule WHEN clocking in late manually THEN status is late" do
      admin = insert_admin()
      employee = insert_user()
      today = Date.utc_today()
      day_of_week = Date.day_of_week(today)

      # Schedule: 08:00. Manual clock-in: 10:00 (2 hours late, > 15 min grace)
      HR.set_work_schedules(employee.id, [
        %{day_of_week: day_of_week, start_time: ~T[08:00:00], end_time: ~T[16:00:00]}
      ])

      late_time = DateTime.new!(today, ~T[10:00:00], "Etc/UTC")
      {:ok, record} = HR.clock_in_manual(admin, employee, late_time)
      assert record.status == "late"
    end

    test "GIVEN employee with schedule WHEN clocking in early manually THEN status is early" do
      admin = insert_admin()
      employee = insert_user()
      today = Date.utc_today()
      day_of_week = Date.day_of_week(today)

      HR.set_work_schedules(employee.id, [
        %{day_of_week: day_of_week, start_time: ~T[10:00:00], end_time: ~T[18:00:00]}
      ])

      early_time = DateTime.new!(today, ~T[08:00:00], "Etc/UTC")
      {:ok, record} = HR.clock_in_manual(admin, employee, early_time)
      assert record.status == "early"
    end
  end

  # ===========================================================================
  # HR.clock_out/1
  # ===========================================================================

  describe "clock_out/1" do
    test "GIVEN user clocked in WHEN clocking out THEN returns ok with clocked_out_at set" do
      user = insert_user()
      HR.clock_in(user, @near_lat, @near_lng)

      assert {:ok, record} = HR.clock_out(user)
      assert record.clocked_out_at
    end

    test "GIVEN user NOT clocked in WHEN clocking out THEN returns :not_clocked_in" do
      user = insert_user()

      assert {:error, :not_clocked_in} = HR.clock_out(user)
    end

    test "GIVEN user with record but nil clocked_in_at WHEN clocking out THEN returns :not_clocked_in" do
      user = insert_user()
      # Creates record with no clock-in
      HR.get_or_create_today_record(user)

      assert {:error, :not_clocked_in} = HR.clock_out(user)
    end
  end

  # ===========================================================================
  # HR.clock_out_manual/3
  # ===========================================================================

  describe "clock_out_manual/3" do
    test "GIVEN admin and clocked-in employee WHEN registering manual clock-out THEN succeeds" do
      admin = insert_admin()
      employee = insert_user()
      HR.clock_in(employee, @near_lat, @near_lng)

      now = DateTime.utc_now()
      assert {:ok, record} = HR.clock_out_manual(admin, employee, now)
      assert record.clocked_out_at
      assert record.manual_entry == true
    end

    test "GIVEN admin and employee with no record WHEN manual clock-out THEN returns error" do
      admin = insert_admin()
      employee = insert_user()

      assert {:error, :not_clocked_in} = HR.clock_out_manual(admin, employee, DateTime.utc_now())
    end
  end

  # ===========================================================================
  # HR.list_attendance_for_user/3
  # ===========================================================================

  describe "list_attendance_for_user/3" do
    test "GIVEN user with records in month WHEN listing THEN returns all for that month" do
      user = insert_user()
      today = Date.utc_today()
      HR.get_or_create_today_record(user)

      records = HR.list_attendance_for_user(user.id, today.year, today.month)
      assert length(records) >= 1
    end

    test "GIVEN user with no records WHEN listing THEN returns empty list" do
      user = insert_user()
      records = HR.list_attendance_for_user(user.id, 2020, 1)
      assert records == []
    end
  end

  # ===========================================================================
  # HR.list_staff_today/0
  # ===========================================================================

  describe "list_staff_today/0" do
    test "GIVEN active non-cliente users WHEN listing staff THEN all are included" do
      emp = insert_user(%{role: "empleado", name: "Ana Staff"})

      result = HR.list_staff_today()
      user_ids = Enum.map(result, fn {u, _r} -> u.id end)
      assert emp.id in user_ids
    end

    test "GIVEN user clocked in today WHEN listing staff THEN their record is attached" do
      user = insert_user()
      HR.clock_in(user, @near_lat, @near_lng)

      result = HR.list_staff_today()
      {_u, record} = Enum.find(result, fn {u, _} -> u.id == user.id end)
      assert record
      assert record.clocked_in_at
    end

    test "GIVEN user NOT clocked in WHEN listing staff THEN their record may be nil or absent" do
      user = insert_user(%{name: "Sin Entrada"})

      result = HR.list_staff_today()
      entry = Enum.find(result, fn {u, _} -> u.id == user.id end)
      assert entry
      {_u, record} = entry
      # record is either nil or has no clocked_in_at
      assert is_nil(record) or is_nil(record.clocked_in_at)
    end
  end

  # ===========================================================================
  # HR.attendance_summary/2
  # ===========================================================================

  describe "attendance_summary/2" do
    test "GIVEN no attendance records WHEN computing summary THEN returns empty list" do
      today = Date.utc_today()
      result = HR.attendance_summary(today.year, today.month)
      assert is_list(result)
    end

    test "GIVEN employee with on_time record WHEN computing summary THEN on_time count is correct" do
      user = insert_user()
      today = Date.utc_today()

      # Clock in without a schedule → status defaults to on_time
      HR.clock_in(user, @near_lat, @near_lng)

      summary = HR.attendance_summary(today.year, today.month)
      entry = Enum.find(summary, &(&1.user_id == user.id))
      assert entry
      assert entry.on_time >= 1
    end
  end

  # ===========================================================================
  # End-to-end flow
  # ===========================================================================

  describe "full HR flow" do
    test "create employee → assign schedule → clock in → clock out → view history" do
      admin = insert_admin()
      employee = insert_user()
      today = Date.utc_today()
      day_of_week = Date.day_of_week(today)

      # Assign schedule
      {:ok, schedules} =
        HR.set_work_schedules(employee.id, [
          %{day_of_week: day_of_week, start_time: ~T[08:00:00], end_time: ~T[17:00:00]}
        ])

      assert length(schedules) == 1

      # Clock in via GPS (near café)
      assert {:ok, record} = HR.clock_in(employee, @near_lat, @near_lng)
      assert record.clocked_in_at

      # Cannot clock in again
      assert {:error, :already_clocked_in} = HR.clock_in(employee, @near_lat, @near_lng)

      # Clock out
      assert {:ok, out_record} = HR.clock_out(employee)
      assert out_record.clocked_out_at

      # View attendance history
      records = HR.list_attendance_for_user(employee.id, today.year, today.month)
      assert length(records) >= 1
      assert hd(records).user_id == employee.id
    end
  end
end
