defmodule CRC.HR do
  @moduledoc """
  Human Resources bounded context.

  Handles employee work schedules, attendance clock-in/out, and metrics.

  ## Geolocation
  Clock-in via the mobile app requires the employee to be within
  `@max_distance_m` metres of the café. Admins can override this
  by registering arrivals manually.

  ## Time zone
  All datetimes are stored in UTC. The café operates in Mexico City
  (America/Mexico_City, UTC-6 / UTC-5 DST). For now the system treats
  scheduled times as UTC-naive and compares against UTC clock-in times,
  which works correctly as long as the server clock is synced and
  consistent. Full tz support can be added later with the `tz` library.
  """

  import Ecto.Query, warn: false

  alias CRC.Repo
  alias CRC.HR.{WorkSchedule, AttendanceRecord}
  alias CRC.Accounts.User

  # ---------------------------------------------------------------------------
  # Café constants
  # ---------------------------------------------------------------------------

  # Dr. Mariano Azuela #80, Santa María la Ribera, CDMX
  # Coordinates extracted from the official Google Maps pin for "Café Raíces y Cultura"
  @cafe_lat 19.445424998689816
  @cafe_lng -99.15739759497082

  # Maximum distance from the café (metres) to allow clock-in.
  # 350 m covers the ~287 m GPS offset observed in production logs
  # while keeping the check meaningful (< 1 city block extra).
  @max_distance_m 350

  # Minutes after scheduled_start before the record is considered "late"
  @grace_minutes 15

  # ---------------------------------------------------------------------------
  # Work Schedules — public API
  # ---------------------------------------------------------------------------

  @doc "Returns all work-schedule entries for a user, ordered Mon→Sun."
  @spec list_work_schedules(integer()) :: [WorkSchedule.t()]
  def list_work_schedules(user_id) do
    WorkSchedule
    |> where([s], s.user_id == ^user_id)
    |> order_by([s], s.day_of_week)
    |> Repo.all()
  end

  @doc """
  Atomically replaces all work-schedule entries for a user.

  `entries` is a list of maps with keys `:day_of_week`, `:start_time`, `:end_time`.
  Passing an empty list clears the schedule entirely.
  """
  @spec set_work_schedules(integer(), [map()]) ::
          {:ok, [WorkSchedule.t()]} | {:error, Ecto.Changeset.t()}
  def set_work_schedules(user_id, entries) do
    Repo.transaction(fn ->
      Repo.delete_all(from(s in WorkSchedule, where: s.user_id == ^user_id))

      Enum.each(entries, fn entry ->
        %WorkSchedule{}
        |> WorkSchedule.changeset(Map.put(entry, :user_id, user_id))
        |> Repo.insert!()
      end)

      list_work_schedules(user_id)
    end)
  end

  @doc "Returns the work schedule for a specific day, or nil if the user is off."
  @spec get_schedule_for_day(integer(), 1..7) :: WorkSchedule.t() | nil
  def get_schedule_for_day(user_id, day_of_week) do
    WorkSchedule
    |> where([s], s.user_id == ^user_id and s.day_of_week == ^day_of_week)
    |> Repo.one()
  end

  # ---------------------------------------------------------------------------
  # Attendance — public API
  # ---------------------------------------------------------------------------

  @doc "Returns today's attendance record for a user, or nil."
  @spec get_attendance_record(integer(), Date.t()) :: AttendanceRecord.t() | nil
  def get_attendance_record(user_id, date) do
    AttendanceRecord
    |> where([a], a.user_id == ^user_id and a.date == ^date)
    |> Repo.one()
  end

  @doc """
  Returns today's attendance record, creating it if it doesn't exist yet.
  The `scheduled_start` / `scheduled_end` snapshot is taken from the current schedule.
  """
  @spec get_or_create_today_record(User.t()) :: AttendanceRecord.t()
  def get_or_create_today_record(%User{id: user_id} = _user) do
    today = Date.utc_today()
    day_of_week = Date.day_of_week(today)

    case get_attendance_record(user_id, today) do
      nil ->
        schedule = get_schedule_for_day(user_id, day_of_week)

        %AttendanceRecord{}
        |> AttendanceRecord.changeset(%{
          user_id: user_id,
          date: today,
          scheduled_start: schedule && schedule.start_time,
          scheduled_end: schedule && schedule.end_time,
          status: "absent"
        })
        |> Repo.insert!()

      record ->
        record
    end
  end

  @doc """
  Records a clock-in for `user` after verifying they are within #{@max_distance_m} m
  of the café.

  Returns:
  - `{:ok, record}` on success.
  - `{:error, :too_far}` when the employee is outside the allowed radius.
  - `{:error, :already_clocked_in}` when a clock-in already exists today.
  """
  @spec clock_in(User.t(), float(), float()) ::
          {:ok, AttendanceRecord.t()} | {:error, :too_far | :already_clocked_in}
  def clock_in(%User{} = user, lat, lng) do
    distance = haversine_distance(lat, lng, @cafe_lat, @cafe_lng)

    require Logger

    Logger.info(
      "[clock_in] user=#{user.id} lat=#{lat} lng=#{lng} " <>
        "cafe_lat=#{@cafe_lat} cafe_lng=#{@cafe_lng} " <>
        "distance_m=#{Float.round(distance, 1)} max_m=#{@max_distance_m}"
    )

    if distance <= @max_distance_m do
      do_clock_in(user, lat, lng, false)
    else
      {:error, :too_far}
    end
  end

  @doc """
  Admin registers a clock-in on behalf of an employee.

  `clock_in_time` is a `%DateTime{}` in UTC representing the actual arrival time.
  """
  @spec clock_in_manual(User.t(), User.t(), DateTime.t()) ::
          {:ok, AttendanceRecord.t()} | {:error, any()}
  def clock_in_manual(%User{role: "admin"}, %User{} = employee, %DateTime{} = clock_in_time) do
    record = get_or_create_today_record(employee)

    status = compute_status(record.scheduled_start, clock_in_time)

    record
    |> AttendanceRecord.changeset(%{
      clocked_in_at: clock_in_time,
      manual_entry: true,
      status: status
    })
    |> Repo.update()
  end

  @doc """
  Records a clock-out for `user`.

  Returns:
  - `{:ok, record}` on success.
  - `{:error, :not_clocked_in}` when no clock-in exists today.
  """
  @spec clock_out(User.t()) ::
          {:ok, AttendanceRecord.t()} | {:error, :not_clocked_in}
  def clock_out(%User{} = user) do
    today = Date.utc_today()

    case get_attendance_record(user.id, today) do
      %{clocked_in_at: nil} ->
        {:error, :not_clocked_in}

      nil ->
        {:error, :not_clocked_in}

      record ->
        record
        |> AttendanceRecord.changeset(%{clocked_out_at: DateTime.utc_now()})
        |> Repo.update()
    end
  end

  @doc "Admin registers a clock-out on behalf of an employee."
  @spec clock_out_manual(User.t(), User.t(), DateTime.t()) ::
          {:ok, AttendanceRecord.t()} | {:error, any()}
  def clock_out_manual(%User{role: "admin"}, %User{} = employee, %DateTime{} = clock_out_time) do
    today = Date.utc_today()

    case get_attendance_record(employee.id, today) do
      nil ->
        {:error, :not_clocked_in}

      record ->
        record
        |> AttendanceRecord.changeset(%{
          clocked_out_at: clock_out_time,
          manual_entry: true
        })
        |> Repo.update()
    end
  end

  @doc "Returns all attendance records for a user in the given month/year, ordered by date."
  @spec list_attendance_for_user(integer(), integer(), integer()) :: [AttendanceRecord.t()]
  def list_attendance_for_user(user_id, year, month) do
    start_date = Date.new!(year, month, 1)
    end_date = Date.end_of_month(start_date)

    AttendanceRecord
    |> where([a], a.user_id == ^user_id and a.date >= ^start_date and a.date <= ^end_date)
    |> order_by([a], a.date)
    |> Repo.all()
  end

  @doc """
  Returns all non-cliente staff together with their today's attendance record
  (or nil when no record exists yet).

  Result: `[{%User{}, %AttendanceRecord{} | nil}]` sorted alphabetically.
  """
  @spec list_staff_today() :: [{User.t(), AttendanceRecord.t() | nil}]
  def list_staff_today do
    today = Date.utc_today()

    users =
      User
      |> where([u], u.role != "cliente" and u.is_active == true)
      |> order_by([u], u.name)
      |> Repo.all()

    records =
      AttendanceRecord
      |> where([a], a.date == ^today)
      |> Repo.all()
      |> Map.new(&{&1.user_id, &1})

    Enum.map(users, fn user -> {user, Map.get(records, user.id)} end)
  end

  @doc """
  Returns a per-employee attendance summary for the given month/year.

  Each entry is a map with:
  - `:user_id`, `:name`
  - `:on_time`, `:late`, `:absent` — counts
  - `:avg_late_minutes` — average minutes late (0 when never late)
  - `:overtime_days` — days where clocked_out_at > scheduled_end + 30 min
  """
  @spec attendance_summary(integer(), integer()) :: [map()]
  def attendance_summary(year, month) do
    start_date = Date.new!(year, month, 1)
    end_date = Date.end_of_month(start_date)

    AttendanceRecord
    |> where([a], a.date >= ^start_date and a.date <= ^end_date)
    |> join(:inner, [a], u in assoc(a, :user))
    |> where([_a, u], u.role != "cliente")
    |> preload([_a, u], user: u)
    |> order_by([a], a.date)
    |> Repo.all()
    |> Enum.group_by(& &1.user_id)
    |> Enum.map(fn {_uid, records} ->
      user = hd(records).user

      early = Enum.count(records, &(&1.status == "early"))
      on_time = Enum.count(records, &(&1.status == "on_time"))
      late = Enum.count(records, &(&1.status == "late"))
      absent = Enum.count(records, &(&1.status == "absent"))

      late_minutes =
        records
        |> Enum.filter(&((&1.status == "late" and &1.clocked_in_at) && &1.scheduled_start))
        |> Enum.map(fn r ->
          sched_dt = DateTime.new!(r.date, r.scheduled_start, "Etc/UTC")
          DateTime.diff(r.clocked_in_at, sched_dt, :minute)
        end)

      avg_late_minutes =
        if late_minutes == [], do: 0, else: round(Enum.sum(late_minutes) / length(late_minutes))

      early_minutes =
        records
        |> Enum.filter(&((&1.status == "early" and &1.clocked_in_at) && &1.scheduled_start))
        |> Enum.map(fn r ->
          sched_dt = DateTime.new!(r.date, r.scheduled_start, "Etc/UTC")
          # Positive value = minutes early
          abs(DateTime.diff(r.clocked_in_at, sched_dt, :minute))
        end)

      avg_early_minutes =
        if early_minutes == [],
          do: 0,
          else: round(Enum.sum(early_minutes) / length(early_minutes))

      overtime_days =
        Enum.count(records, fn r ->
          r.clocked_out_at && r.scheduled_end &&
            DateTime.diff(
              r.clocked_out_at,
              DateTime.new!(r.date, r.scheduled_end, "Etc/UTC"),
              :minute
            ) > 30
        end)

      %{
        user_id: user.id,
        name: user.name,
        early: early,
        on_time: on_time,
        late: late,
        absent: absent,
        avg_late_minutes: avg_late_minutes,
        avg_early_minutes: avg_early_minutes,
        overtime_days: overtime_days
      }
    end)
    |> Enum.sort_by(& &1.late, :desc)
  end

  # ---------------------------------------------------------------------------
  # Geolocation
  # ---------------------------------------------------------------------------

  @doc """
  Returns `true` when the given coordinates are within #{@max_distance_m} m of the café.
  Uses the Haversine formula with Earth radius = 6 371 000 m.
  """
  @spec near_cafe?(float(), float()) :: boolean()
  def near_cafe?(lat, lng) do
    haversine_distance(lat, lng, @cafe_lat, @cafe_lng) <= @max_distance_m
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_clock_in(%User{} = user, lat, lng, manual) do
    record = get_or_create_today_record(user)

    if record.clocked_in_at do
      {:error, :already_clocked_in}
    else
      now = DateTime.utc_now()
      status = compute_status(record.scheduled_start, now)

      record
      |> AttendanceRecord.changeset(%{
        clocked_in_at: now,
        latitude: lat,
        longitude: lng,
        manual_entry: manual,
        status: status
      })
      |> Repo.update()
    end
  end

  # No scheduled start → always on_time (unscheduled day, walk-in)
  defp compute_status(nil, _clocked_in_at), do: "on_time"

  defp compute_status(scheduled_start, clocked_in_at) do
    # Build a UTC DateTime for the scheduled start on today's date
    sched_dt = DateTime.new!(Date.utc_today(), scheduled_start, "Etc/UTC")
    diff_minutes = DateTime.diff(clocked_in_at, sched_dt, :minute)

    cond do
      diff_minutes < 0 -> "early"
      diff_minutes <= @grace_minutes -> "on_time"
      true -> "late"
    end
  end

  defp haversine_distance(lat1, lng1, lat2, lng2) do
    r = 6_371_000
    phi1 = lat1 * :math.pi() / 180
    phi2 = lat2 * :math.pi() / 180
    dphi = (lat2 - lat1) * :math.pi() / 180
    dlambda = (lng2 - lng1) * :math.pi() / 180

    a =
      :math.sin(dphi / 2) ** 2 +
        :math.cos(phi1) * :math.cos(phi2) * :math.sin(dlambda / 2) ** 2

    2 * r * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
  end
end
