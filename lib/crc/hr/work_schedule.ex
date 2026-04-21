defmodule CRC.HR.WorkSchedule do
  @moduledoc """
  A single day-of-week slot in an employee's recurring weekly schedule.

  day_of_week follows ISO 8601: 1 = Monday … 7 = Sunday.
  Each user has at most one entry per day (unique index on user_id + day_of_week).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Accounts.User

  @type t :: %__MODULE__{}

  schema "work_schedules" do
    field :day_of_week, :integer
    field :start_time, :time
    field :end_time, :time

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [:user_id, :day_of_week, :start_time, :end_time])
    |> validate_required([:user_id, :day_of_week, :start_time, :end_time],
      message: "no puede estar en blanco"
    )
    |> validate_inclusion(:day_of_week, 1..7, message: "día inválido")
    |> validate_end_after_start()
    |> unique_constraint([:user_id, :day_of_week],
      message: "ya existe un horario para ese día"
    )
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  @doc "Returns the Spanish name for a day_of_week integer (1–7)."
  @spec day_name(1..7) :: String.t()
  def day_name(1), do: "Lunes"
  def day_name(2), do: "Martes"
  def day_name(3), do: "Miércoles"
  def day_name(4), do: "Jueves"
  def day_name(5), do: "Viernes"
  def day_name(6), do: "Sábado"
  def day_name(7), do: "Domingo"

  @doc "Returns the short Spanish name for a day_of_week integer (1–7)."
  @spec day_short(1..7) :: String.t()
  def day_short(1), do: "Lun"
  def day_short(2), do: "Mar"
  def day_short(3), do: "Mié"
  def day_short(4), do: "Jue"
  def day_short(5), do: "Vie"
  def day_short(6), do: "Sáb"
  def day_short(7), do: "Dom"

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp validate_end_after_start(changeset) do
    start_time = get_field(changeset, :start_time)
    end_time = get_field(changeset, :end_time)

    if start_time && end_time && Time.compare(end_time, start_time) != :gt do
      add_error(changeset, :end_time, "debe ser después de la hora de entrada")
    else
      changeset
    end
  end
end
