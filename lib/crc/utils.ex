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
end
