defmodule CRC.Schedule do
  @moduledoc "Weekly activity schedule for employees."

  import Ecto.Query
  alias CRC.Repo
  alias CRC.Schedule.{Area, Task, Assignment}
  alias CRC.Accounts.User

  # ---------------------------------------------------------------------------
  # Areas
  # ---------------------------------------------------------------------------

  def list_areas do
    Area
    |> order_by([a], asc: a.position, asc: a.id)
    |> preload(tasks: ^from(t in Task, order_by: [asc: t.position, asc: t.id]))
    |> Repo.all()
  end

  def get_area!(id), do: Repo.get!(Area, id)

  def create_area(attrs) do
    # Auto-assign next position
    max_pos = Repo.aggregate(Area, :max, :position) || -1

    %Area{}
    |> Area.changeset(Map.put_new(attrs, "position", max_pos + 1))
    |> Repo.insert()
  end

  def update_area(%Area{} = area, attrs) do
    area
    |> Area.changeset(attrs)
    |> Repo.update()
  end

  def delete_area(%Area{} = area), do: Repo.delete(area)

  def change_area(%Area{} = area, attrs \\ %{}), do: Area.changeset(area, attrs)

  # ---------------------------------------------------------------------------
  # Tasks
  # ---------------------------------------------------------------------------

  def get_task!(id), do: Repo.get!(Task, id)

  def create_task(attrs) do
    area_id = attrs["area_id"] || attrs[:area_id]

    max_pos =
      Task
      |> where([t], t.area_id == ^area_id)
      |> Repo.aggregate(:max, :position) || -1

    %Task{}
    |> Task.changeset(Map.put_new(attrs, "position", max_pos + 1))
    |> Repo.insert()
  end

  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
  end

  def delete_task(%Task{} = task), do: Repo.delete(task)

  def change_task(%Task{} = task, attrs \\ %{}), do: Task.changeset(task, attrs)

  # ---------------------------------------------------------------------------
  # Assignments
  # ---------------------------------------------------------------------------

  @doc """
  Returns assignments for a given week as a nested map:
    %{task_id => %{day_of_week => %Assignment{}}}
  """
  def get_week_assignments(%Date{} = week_start) do
    Assignment
    |> where([a], a.week_start_date == ^week_start)
    |> preload(:user)
    |> Repo.all()
    |> Enum.reduce(%{}, fn a, acc ->
      acc
      |> Map.put_new(a.task_id, %{})
      |> put_in([a.task_id, a.day_of_week], a)
    end)
  end

  @doc """
  Creates or updates an assignment for a specific task/day/week.
  Pass user_id: nil to clear the slot.
  """
  def upsert_assignment(task_id, day_of_week, week_start, user_id) do
    existing =
      Repo.get_by(Assignment,
        task_id: task_id,
        day_of_week: day_of_week,
        week_start_date: week_start
      )

    attrs = %{
      task_id: task_id,
      day_of_week: day_of_week,
      week_start_date: week_start,
      user_id: if(user_id == "" or user_id == "0", do: nil, else: user_id)
    }

    case existing do
      nil ->
        %Assignment{}
        |> Assignment.changeset(attrs)
        |> Repo.insert()

      assignment ->
        assignment
        |> Assignment.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Copies all assignments from `source_week` into `target_week`.
  Skips slots that already exist in the target week.
  """
  def copy_week(%Date{} = source_week, %Date{} = target_week) do
    source_assignments =
      Assignment
      |> where([a], a.week_start_date == ^source_week)
      |> Repo.all()

    Enum.each(source_assignments, fn a ->
      existing =
        Repo.get_by(Assignment,
          task_id: a.task_id,
          day_of_week: a.day_of_week,
          week_start_date: target_week
        )

      if is_nil(existing) do
        %Assignment{}
        |> Assignment.changeset(%{
          task_id: a.task_id,
          day_of_week: a.day_of_week,
          week_start_date: target_week,
          user_id: a.user_id
        })
        |> Repo.insert()
      end
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Users (employees)
  # ---------------------------------------------------------------------------

  def list_employees do
    User
    |> order_by([u], asc: u.name)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Week helpers
  # ---------------------------------------------------------------------------

  @doc "Returns the Monday of the week containing `date`."
  def week_start(%Date{} = date) do
    days_since_monday = Date.day_of_week(date) - 1
    Date.add(date, -days_since_monday)
  end

  @doc "Returns the short initials (up to 2 chars) for a user name."
  def initials(nil), do: "—"

  def initials(%User{name: name}) when is_binary(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  def initials(_), do: "—"

  @day_names ~w(Lun Mar Mié Jue Vie Sáb Dom)

  def day_name(day_of_week), do: Enum.at(@day_names, day_of_week, "?")
end
