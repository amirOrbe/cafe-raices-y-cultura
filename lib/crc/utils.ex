defmodule CRC.Utils do
  @moduledoc """
  General-purpose helpers shared across bounded contexts.
  """

  @doc """
  Converts a string to Title Case: first letter of each word capitalised,
  rest lower-cased. Trims surrounding whitespace and collapses internal
  runs of spaces to a single space.

      iex> CRC.Utils.title_case("leche evaporada")
      "Leche Evaporada"

      iex> CRC.Utils.title_case("CAFÉ DE  ESPECIALIDAD")
      "Café De  Especialidad"

      iex> CRC.Utils.title_case(nil)
      nil
  """
  @spec title_case(String.t() | nil) :: String.t() | nil
  def title_case(nil), do: nil
  def title_case(""), do: ""

  def title_case(str) when is_binary(str) do
    str
    |> String.trim()
    |> String.split(~r/\s+/)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  @doc """
  Formats a monetary amount as a plain string with thousands separators and
  two decimals. No currency symbol — callers prepend `$` where needed.

      iex> CRC.Utils.format_money(Decimal.new("208171"))
      "208,171.00"

      iex> CRC.Utils.format_money(Decimal.new("11.665"))
      "11.67"

      iex> CRC.Utils.format_money(Decimal.new("-1234.5"))
      "-1,234.50"

      iex> CRC.Utils.format_money(nil)
      "0.00"
  """
  @spec format_money(Decimal.t() | number() | binary() | nil) :: String.t()
  def format_money(nil), do: "0.00"

  def format_money(%Decimal{} = d) do
    d
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> group_thousands()
  end

  def format_money(n) when is_integer(n), do: format_money(Decimal.new(n))
  def format_money(n) when is_float(n), do: format_money(Decimal.from_float(n))

  def format_money(n) when is_binary(n) do
    case Decimal.parse(n) do
      {d, ""} -> format_money(d)
      _ -> n
    end
  end

  @doc """
  Shifts a UTC datetime into the café's local wall-clock time using the
  configured `:utc_offset_hours` (default -6, Ciudad de México).

  For display only — the returned value's date/time fields read as local, but
  its zone metadata is unchanged, so never persist it or compare it to `utc_now`.

      iex> CRC.Utils.to_local(~U[2026-09-09 18:54:00Z]) |> Calendar.strftime("%H:%M")
      "12:54"

      iex> CRC.Utils.to_local(nil)
      nil
  """
  @spec to_local(DateTime.t() | NaiveDateTime.t() | nil) ::
          DateTime.t() | NaiveDateTime.t() | nil
  def to_local(nil), do: nil

  def to_local(%DateTime{} = dt), do: DateTime.add(dt, offset_seconds(), :second)

  def to_local(%NaiveDateTime{} = ndt), do: NaiveDateTime.add(ndt, offset_seconds(), :second)

  @doc """
  Inverse of `to_local/1`: takes a naive datetime whose fields are the café's
  local wall-clock time and returns the corresponding UTC `DateTime`.

      iex> CRC.Utils.from_local_naive(~N[2026-09-09 12:54:00])
      ~U[2026-09-09 18:54:00Z]
  """
  @spec from_local_naive(NaiveDateTime.t()) :: DateTime.t()
  def from_local_naive(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.add(-offset_seconds(), :second)
  end

  defp offset_seconds, do: Application.get_env(:crc, :utc_offset_hours, -6) * 3600

  defp group_thousands(str) do
    {sign, digits} =
      case str do
        "-" <> rest -> {"-", rest}
        _ -> {"", str}
      end

    {int, frac} =
      case String.split(digits, ".") do
        [i] -> {i, "00"}
        [i, f] -> {i, String.pad_trailing(f, 2, "0")}
      end

    grouped =
      int
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
      |> String.reverse()

    sign <> grouped <> "." <> frac
  end
end
