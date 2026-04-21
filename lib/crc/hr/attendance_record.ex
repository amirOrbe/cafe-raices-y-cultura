defmodule CRC.HR.AttendanceRecord do
  @moduledoc """
  Represents a single working day for an employee.

  One record per employee per calendar date (unique index on user_id + date).

  Status values:
  - `"early"`   — clocked in before the scheduled_start time.
  - `"on_time"` — clocked in within the grace period after scheduled_start.
  - `"late"`    — clocked in after the grace period.
  - `"absent"`  — no clock-in recorded for a scheduled work day.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Accounts.User

  @type t :: %__MODULE__{}
  @statuses ~w(early on_time late absent)

  schema "attendance_records" do
    field :date, :date
    field :scheduled_start, :time
    field :scheduled_end, :time
    field :clocked_in_at, :utc_datetime
    field :clocked_out_at, :utc_datetime
    field :latitude, :float
    field :longitude, :float
    field :manual_entry, :boolean, default: false
    field :status, :string, default: "absent"

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :user_id,
      :date,
      :scheduled_start,
      :scheduled_end,
      :clocked_in_at,
      :clocked_out_at,
      :latitude,
      :longitude,
      :manual_entry,
      :status
    ])
    |> validate_required([:user_id, :date], message: "no puede estar en blanco")
    |> validate_inclusion(:status, @statuses, message: "estado inválido")
    |> unique_constraint([:user_id, :date],
      message: "ya existe un registro para ese día"
    )
  end

  @doc "Returns all valid status values."
  def statuses, do: @statuses
end
