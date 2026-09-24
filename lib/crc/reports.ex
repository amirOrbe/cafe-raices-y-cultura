defmodule CRC.Reports do
  @moduledoc """
  CSV formatting for the admin reports download buttons
  (`/admin/reportes/*.csv`). Pure formatting layer — every number here comes
  from `CRC.Orders`, so a report can never disagree with what its matching
  LiveView shows on screen.
  """

  alias CRC.Orders
  alias NimbleCSV.RFC4180, as: CSV

  @doc "One-row P&L summary CSV for the given period. Mirrors FinanzasLive's stat cards."
  def financial_summary_csv(period \\ :all) do
    summary = Orders.financial_summary(period)

    rows = [
      [
        "Ingresos",
        "Costo de ventas",
        "Ganancia bruta",
        "Margen bruto %",
        "Desperdicio",
        "Ganancia neta"
      ],
      [
        money(summary.revenue),
        money(summary.cogs),
        money(summary.gross_profit),
        Decimal.to_string(summary.margin_pct),
        money(summary.waste_cost),
        money(summary.net_profit)
      ]
    ]

    to_csv(rows)
  end

  @doc "One row per wasted menu item for the given period. Mirrors FinanzasLive's wasted-items table."
  def wasted_items_csv(period \\ :all) do
    header = ["Platillo", "Cantidad", "Costo perdido"]

    rows =
      period
      |> Orders.top_wasted_items(1_000_000)
      |> Enum.map(fn item -> [item.name, item.qty, money(item.cost)] end)

    to_csv([header | rows])
  end

  @doc "One row per closed order for the given period. Mirrors VentasLive's order history."
  def closed_orders_csv(period \\ :all) do
    header = ["Fecha de cierre", "Mesero", "Cliente", "Método de pago", "Total"]

    rows =
      period
      |> Orders.list_closed_orders()
      |> CRC.Repo.preload(:user)
      |> Enum.map(fn order ->
        [
          format_datetime(order.closed_at),
          order.user && order.user.name,
          order.customer_name,
          order.payment_method,
          money(order.total)
        ]
      end)

    to_csv([header | rows])
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  # UTF-8 BOM so Excel reads accented characters correctly instead of mojibake.
  @bom "﻿"

  defp to_csv(rows) do
    @bom <> IO.iodata_to_binary(CSV.dump_to_iodata(rows))
  end

  defp money(%Decimal{} = d), do: Decimal.to_string(d)
  defp money(_), do: "0"

  defp format_datetime(nil), do: ""

  defp format_datetime(%DateTime{} = dt),
    do: dt |> CRC.Utils.to_local() |> Calendar.strftime("%Y-%m-%d %H:%M")
end
