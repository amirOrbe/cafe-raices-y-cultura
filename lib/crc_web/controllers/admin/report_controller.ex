defmodule CRCWeb.Admin.ReportController do
  @moduledoc """
  Downloadable CSV reports for the admin panel (`/admin/reportes/*.csv`).

  Plain controller, not a LiveView — `send_download/3` needs a `Plug.Conn`,
  which `handle_event/3` doesn't have. Reuses `CRC.Reports`, which in turn
  reuses the exact same `CRC.Orders` functions the LiveViews call, so a
  downloaded report can never disagree with what's on screen for the same
  period.
  """
  use CRCWeb, :controller

  alias CRC.Reports

  def finanzas_csv(conn, params) do
    download(conn, "finanzas", Reports.financial_summary_csv(parse_period(params)))
  end

  def desperdicio_csv(conn, params) do
    download(conn, "desperdicio", Reports.wasted_items_csv(parse_period(params)))
  end

  def ventas_csv(conn, params) do
    download(conn, "ventas", Reports.closed_orders_csv(parse_period(params)))
  end

  defp download(conn, name, csv) do
    filename = "#{name}_#{Date.to_iso8601(Date.utc_today())}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> send_download({:binary, csv}, filename: filename)
  end

  # Mirrors the period shape the admin LiveViews already use:
  # :today | :week | :month | :all | {:range, Date, Date}
  defp parse_period(%{"period" => "range", "date_from" => from, "date_to" => to}) do
    with {:ok, d_from} <- Date.from_iso8601(from),
         {:ok, d_to} <- Date.from_iso8601(to),
         true <- Date.compare(d_from, d_to) != :gt do
      {:range, d_from, d_to}
    else
      _ -> :all
    end
  end

  defp parse_period(%{"period" => period}) when period in ~w(today week month all) do
    String.to_existing_atom(period)
  end

  defp parse_period(_params), do: :all
end
