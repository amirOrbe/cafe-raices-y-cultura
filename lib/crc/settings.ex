defmodule CRC.Settings do
  @moduledoc """
  Bounded context for café-wide configuration.

  Currently manages weekly business hours (opening/closing times per day of week).
  Future: blocked time slots, reservation limits, etc.
  """

  import Ecto.Query

  alias CRC.Repo
  alias CRC.Settings.CafeHours

  @days 1..7

  # ---------------------------------------------------------------------------
  # Café hours — public API
  # ---------------------------------------------------------------------------

  @doc """
  Returns all 7 cafe_hours rows, ordered Monday → Sunday.
  Rows that haven't been saved yet won't appear; use `full_week/0` to get
  a guaranteed 7-element list with defaults filled in.
  """
  @spec list_cafe_hours() :: [CafeHours.t()]
  def list_cafe_hours do
    Repo.all(from ch in CafeHours, order_by: ch.day_of_week)
  end

  @doc """
  Returns a map of %{day_of_week => CafeHours.t()} for all persisted rows.
  """
  @spec cafe_hours_by_day() :: %{1..7 => CafeHours.t()}
  def cafe_hours_by_day do
    list_cafe_hours() |> Map.new(&{&1.day_of_week, &1})
  end

  @doc """
  Atomically replaces all cafe_hours rows.

  `entries` is a list of maps with keys:
    - `:day_of_week` (1–7)
    - `:opening_time` (%Time{})
    - `:closing_time` (%Time{})
    - `:is_closed` (boolean)

  Passing fewer than 7 entries leaves missing days untouched.
  Passing an entry for a day that already exists updates it (upsert on day_of_week).
  """
  @spec set_cafe_hours([map()]) :: {:ok, [CafeHours.t()]} | {:error, Ecto.Changeset.t()}
  def set_cafe_hours(entries) do
    Repo.transaction(fn ->
      Enum.each(entries, fn entry ->
        existing = Repo.get_by(CafeHours, day_of_week: entry.day_of_week)

        result =
          if existing do
            existing |> CafeHours.changeset(entry) |> Repo.update()
          else
            %CafeHours{} |> CafeHours.changeset(entry) |> Repo.insert()
          end

        case result do
          {:ok, _} -> :ok
          {:error, cs} -> Repo.rollback(cs)
        end
      end)

      list_cafe_hours()
    end)
  end

  @doc """
  Returns the opening and closing times for a specific date.
  Returns `nil` if no hours are configured for that day, or if the café is
  marked as closed.

  `date` — a `Date` struct.
  """
  @spec hours_for_date(Date.t()) :: {Time.t(), Time.t()} | nil
  def hours_for_date(%Date{} = date) do
    day = Date.day_of_week(date)  # 1 = Mon … 7 = Sun
    row = Repo.get_by(CafeHours, day_of_week: day)

    cond do
      is_nil(row) -> nil
      row.is_closed -> nil
      true -> {row.opening_time, row.closing_time}
    end
  end

  @doc """
  Returns the list of available time windows for a given date, after
  subtracting active events that fall within the café's opening hours.

  Returns an empty list if:
    - No cafe_hours row exists for that day of week.
    - The café is marked as closed on that day.
    - Events occupy the entire operating window.

  Each element is a `{open_from, open_until}` tuple of `%Time{}` values.
  """
  @spec available_windows(Date.t()) :: [{Time.t(), Time.t()}]
  def available_windows(%Date{} = date) do
    case hours_for_date(date) do
      nil ->
        []

      {opening, closing} ->
        events = CRC.Events.list_events_for_date(date)

        # Collect event blocks sorted by start
        blocks =
          events
          |> Enum.map(fn e -> {e.start_time, e.end_time} end)
          |> Enum.filter(fn {s, e} ->
            Time.compare(s, closing) == :lt and Time.compare(e, opening) == :gt
          end)
          |> Enum.sort_by(fn {s, _} -> Time.to_seconds_after_midnight(s) end)

        subtract_blocks(opening, closing, blocks)
    end
  end

  # ---------------------------------------------------------------------------
  # Default form data helpers
  # ---------------------------------------------------------------------------

  @doc "Returns a map of day => %{active, opening, closing} suitable for the admin form."
  @spec default_form_data() :: map()
  def default_form_data do
    Enum.reduce(@days, %{}, fn day, acc ->
      Map.put(acc, day, %{active: false, opening: "10:00", closing: "21:00"})
    end)
  end

  @doc "Builds form data from persisted CafeHours rows."
  @spec build_form_data([CafeHours.t()]) :: map()
  def build_form_data(rows) do
    Enum.reduce(@days, default_form_data(), fn day, acc ->
      case Enum.find(rows, &(&1.day_of_week == day)) do
        nil -> acc
        row ->
          Map.put(acc, day, %{
            active: !row.is_closed,
            opening: format_time(row.opening_time),
            closing: format_time(row.closing_time)
          })
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Subtracts sorted non-overlapping blocks from [window_start, window_end].
  # Returns a list of free {from, until} tuples.
  defp subtract_blocks(start, finish, []) do
    if Time.compare(start, finish) == :lt, do: [{start, finish}], else: []
  end

  defp subtract_blocks(window_start, window_end, [{block_start, block_end} | rest]) do
    # Clamp the block to the window
    b_start = later(window_start, block_start)
    b_end = earlier(window_end, block_end)

    free_before =
      if Time.compare(window_start, b_start) == :lt do
        [{window_start, b_start}]
      else
        []
      end

    free_before ++ subtract_blocks(b_end, window_end, rest)
  end

  defp later(a, b), do: if(Time.compare(a, b) == :gt, do: a, else: b)
  defp earlier(a, b), do: if(Time.compare(a, b) == :lt, do: a, else: b)

  defp format_time(%Time{} = t), do: Calendar.strftime(t, "%H:%M")
  defp format_time(nil), do: "10:00"
end
