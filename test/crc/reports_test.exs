defmodule CRC.ReportsTest do
  use CRC.DataCase, async: true

  alias CRC.Reports
  alias CRC.Orders
  alias CRC.Catalog

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_category do
    {:ok, cat} = Catalog.create_category(%{name: "Cat #{System.unique_integer()}"})
    cat
  end

  defp insert_menu_item(category_id, overrides) do
    {:ok, mi} =
      Catalog.create_menu_item(
        Map.merge(
          %{name: "Item #{System.unique_integer()}", price: "50.00", category_id: category_id},
          overrides
        )
      )

    mi
  end

  defp insert_product(net_cost) do
    CRC.Repo.insert!(%CRC.Inventory.Product{
      name: "Ing #{System.unique_integer()}",
      unit: "g",
      net_cost: Decimal.new(net_cost),
      stock_quantity: Decimal.new("1000"),
      active: true
    })
  end

  defp link_ingredient(menu_item_id, product_id, quantity) do
    CRC.Repo.insert!(%CRC.Catalog.MenuItemIngredient{
      menu_item_id: menu_item_id,
      product_id: product_id,
      quantity: Decimal.new(quantity)
    })
  end

  defp close_order_with_item(price) do
    cat = insert_category()
    mi = insert_menu_item(cat.id, %{price: price})
    {:ok, order} = Orders.create_order(%{customer_name: "Cliente Reportes"})
    {:ok, _} = Orders.add_item(%{order_id: order.id, menu_item_id: mi.id, quantity: 1})
    order = Orders.get_order!(order.id)
    {:ok, closed} = Orders.close_order(order, %{payment_method: "tarjeta"})
    {closed, mi}
  end

  defp csv_rows(csv) do
    csv
    |> String.trim_leading("﻿")
    |> NimbleCSV.RFC4180.parse_string(skip_headers: false)
  end

  # ---------------------------------------------------------------------------
  # financial_summary_csv/1
  # ---------------------------------------------------------------------------

  describe "financial_summary_csv/1" do
    test "has a UTF-8 BOM prefix" do
      csv = Reports.financial_summary_csv(:all)
      assert String.starts_with?(csv, "﻿")
    end

    test "header row matches the P&L labels" do
      [header, _data] = csv_rows(Reports.financial_summary_csv(:all))

      assert header == [
               "Ingresos",
               "Costo de ventas",
               "Ganancia bruta",
               "Margen bruto %",
               "Desperdicio",
               "Ganancia neta"
             ]
    end

    test "data row matches CRC.Orders.financial_summary/1 for the same period" do
      close_order_with_item("100.00")

      summary = Orders.financial_summary(:all)

      [_header, [revenue, _cogs, _gross, _margin, _waste, net_profit]] =
        csv_rows(Reports.financial_summary_csv(:all))

      assert revenue == Decimal.to_string(summary.revenue)
      assert net_profit == Decimal.to_string(summary.net_profit)
    end
  end

  # ---------------------------------------------------------------------------
  # wasted_items_csv/1
  # ---------------------------------------------------------------------------

  describe "wasted_items_csv/1" do
    test "empty when there is no waste in the period" do
      [header | rows] = csv_rows(Reports.wasted_items_csv(:all))
      assert header == ["Platillo", "Cantidad", "Costo perdido"]
      assert rows == []
    end

    test "one row per wasted menu item, matching CRC.Orders.top_wasted_items/2" do
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Platillo Reporte Desperdicio"})
      product = insert_product("2.00")
      link_ingredient(mi.id, product.id, "5")

      {:ok, order} = Orders.create_order(%{customer_name: "Waste Reporte"})
      {:ok, item} = Orders.add_item(%{order_id: order.id, menu_item_id: mi.id, quantity: 1})
      Orders.cancel_item(item, :waste)

      [_header, [name, qty, cost]] = csv_rows(Reports.wasted_items_csv(:all))

      assert name == "Platillo Reporte Desperdicio"
      assert qty == "1"
      assert Decimal.equal?(Decimal.new(cost), Decimal.new("10"))
    end
  end

  # ---------------------------------------------------------------------------
  # closed_orders_csv/1
  # ---------------------------------------------------------------------------

  describe "closed_orders_csv/1" do
    test "empty when there are no closed orders in the period" do
      [header | rows] = csv_rows(Reports.closed_orders_csv(:all))
      assert header == ["Fecha de cierre", "Mesero", "Cliente", "Método de pago", "Total"]
      assert rows == []
    end

    test "one row per closed order" do
      {closed, _mi} = close_order_with_item("100.00")

      [_header, [_date, _mesero, cliente, metodo, total]] =
        csv_rows(Reports.closed_orders_csv(:all))

      assert cliente == closed.customer_name
      assert metodo == "tarjeta"
      assert total == Decimal.to_string(closed.total)
    end
  end
end
