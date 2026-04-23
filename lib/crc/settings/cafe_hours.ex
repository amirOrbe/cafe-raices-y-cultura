defmodule CRC.Settings.CafeHours do
  @moduledoc """
  Weekly business hours for the café.

  One row per day of the week (1 = Monday … 7 = Sunday).
  `is_closed` marks days when the café does not open at all.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "cafe_hours" do
    field :day_of_week, :integer
    field :opening_time, :time
    field :closing_time, :time
    field :is_closed, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(cafe_hours, attrs) do
    cafe_hours
    |> cast(attrs, [:day_of_week, :opening_time, :closing_time, :is_closed])
    |> validate_required([:day_of_week, :opening_time, :closing_time],
      message: "no puede estar en blanco"
    )
    |> validate_inclusion(:day_of_week, 1..7, message: "día inválido")
    |> validate_end_after_start()
    |> unique_constraint(:day_of_week, message: "ya existe un horario para ese día")
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
    is_closed = get_field(changeset, :is_closed)

    if is_closed do
      changeset
    else
      opening = get_field(changeset, :opening_time)
      closing = get_field(changeset, :closing_time)

      if opening && closing && Time.compare(closing, opening) != :gt do
        add_error(changeset, :closing_time, "debe ser después de la hora de apertura")
      else
        changeset
      end
    end
  end
end
