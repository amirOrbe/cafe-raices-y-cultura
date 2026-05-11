defmodule CRCWeb.E2E.RestaurantWorkflowTest do
  @moduledoc """
  Data-driven end-to-end tests for the full order lifecycle.

  Each row in @order_scenarios covers a distinct order type:
    - dine_in en mesa   (order_type: "dine_in", is_group: false)
    - para llevar       (order_type: "takeout",  is_group: false)
    - grupo de comensales (order_type: "dine_in", is_group: true)

  For every scenario the same lifecycle is exercised:
    1. Waiter abre la comanda y envía a cocina/barra
    2. Cocinero marca el platillo como listo en /cocina
    3. Barman marca la bebida como lista en /barra
    4. Waiter cierra la cuenta con pago con tarjeta

  A second DDT sweep verifies that the type/group badges are visible
  in the comanda (/mesa/:id), cocina (/cocina) and barra (/barra) views.

  async: false because multiple LiveView processes share the DB sandbox
  and we test PubSub propagation between them.
  """

  use CRCWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CRC.E2EFixtures

  # ---------------------------------------------------------------------------
  # DDT table — one row per order variant
  # ---------------------------------------------------------------------------

  @order_scenarios [
    %{
      label: "dine_in en mesa",
      order_attrs: %{customer_name: "Mesa — Rocío", order_type: "dine_in", is_group: false},
      expect_takeout_badge: false,
      expect_group_badge: false
    },
    %{
      label: "para llevar",
      order_attrs: %{customer_name: "Llevar — Luis", order_type: "takeout", is_group: false},
      expect_takeout_badge: true,
      expect_group_badge: false
    },
    %{
      label: "grupo de comensales",
      order_attrs: %{customer_name: "Grupo Cumpleaños", order_type: "dine_in", is_group: true},
      expect_takeout_badge: false,
      expect_group_badge: true
    }
  ]

  # Generate one test per scenario for each DDT pass
  for s <- @order_scenarios do
    test "lifecycle completo — #{s.label}", %{conn: conn} do
      run_lifecycle(conn, unquote(Macro.escape(s)))
    end

    test "badges visibles en comanda, cocina y barra — #{s.label}", %{conn: conn} do
      run_badge_visibility(conn, unquote(Macro.escape(s)))
    end
  end

  # ---------------------------------------------------------------------------
  # Lifecycle helper — shared by all scenario rows
  # ---------------------------------------------------------------------------

  defp run_lifecycle(conn, %{order_attrs: order_attrs}) do
    waiter = create_waiter()
    cocinero = create_cocinero()
    barman = create_barman()
    {food, drink} = build_catalog()

    # --- Setup: order with one food item and one drink item -----------------
    order = create_order(order_attrs)
    add_item(order.id, food.id)
    add_item(order.id, drink.id)

    # --- Step 1: waiter opens comanda and sends to kitchen ------------------
    conn_waiter = auth_conn(conn, waiter)
    {:ok, lv_waiter, html_comanda} = live(conn_waiter, "/mesa/#{order.id}")

    assert html_comanda =~ order_attrs.customer_name
    assert html_comanda =~ food.name
    assert html_comanda =~ drink.name

    render_click(lv_waiter, "send_to_kitchen")

    sent_order = CRC.Orders.get_order!(order.id)
    assert sent_order.status == "sent"

    # All items must have transitioned to "sent"
    assert Enum.all?(sent_order.order_items, &(&1.status == "sent"))

    # --- Step 2: cocinero marks food item ready in /cocina ------------------
    conn_cocina = auth_conn(build_conn(), cocinero)
    {:ok, lv_cocina, html_cocina} = live(conn_cocina, "/cocina")

    assert html_cocina =~ food.name

    food_oi = find_order_item(sent_order, food.id)
    render_click(lv_cocina, "mark_item_ready", %{"id" => to_string(food_oi.id)})

    assert CRC.Repo.get!(CRC.Orders.OrderItem, food_oi.id).status == "ready"

    # --- Step 3: barman marks drink item ready in /barra --------------------
    conn_barra = auth_conn(build_conn(), barman)
    {:ok, lv_barra, html_barra} = live(conn_barra, "/barra")

    assert html_barra =~ drink.name

    drink_oi = find_order_item(sent_order, drink.id)
    render_click(lv_barra, "mark_item_ready", %{"id" => to_string(drink_oi.id)})

    assert CRC.Repo.get!(CRC.Orders.OrderItem, drink_oi.id).status == "ready"

    # --- Step 4: waiter closes the order with card payment ------------------
    render_click(lv_waiter, "show_payment_step")
    render_click(lv_waiter, "set_payment_method", %{"method" => "tarjeta"})

    assert {:error, {:redirect, %{to: "/mesa"}}} =
             render_click(lv_waiter, "confirm_close_order")

    closed = CRC.Orders.get_order!(order.id)
    assert closed.status == "closed"
    assert closed.payment_method == "tarjeta"
    assert Decimal.gt?(closed.total, Decimal.new("0"))
  end

  # ---------------------------------------------------------------------------
  # Badge visibility helper — shared by all scenario rows
  # ---------------------------------------------------------------------------

  defp run_badge_visibility(conn, scenario) do
    waiter = create_waiter()
    cocinero = create_cocinero()
    barman = create_barman()
    {food, drink} = build_catalog()

    order = create_order(scenario.order_attrs)
    add_item(order.id, food.id)
    add_item(order.id, drink.id)

    # Send to kitchen so items appear on cocina/barra displays
    {:ok, _} = CRC.Orders.send_to_kitchen(order)

    conn_waiter = auth_conn(conn, waiter)
    {:ok, _, html_comanda} = live(conn_waiter, "/mesa/#{order.id}")

    conn_cocina = auth_conn(build_conn(), cocinero)
    {:ok, _, html_cocina} = live(conn_cocina, "/cocina")

    conn_barra = auth_conn(build_conn(), barman)
    {:ok, _, html_barra} = live(conn_barra, "/barra")

    # En la comanda (orden abierta) el tipo se indica con data-order-type en el
    # toggle interactivo. En cocina y barra se usa el badge de texto "Para llevar".
    if scenario.expect_takeout_badge do
      assert html_comanda =~ ~s(data-order-type="takeout"),
             "expected data-order-type=takeout in comanda for scenario '#{scenario.label}'"
    else
      refute html_comanda =~ ~s(data-order-type="takeout"),
             "unexpected data-order-type=takeout in comanda for scenario '#{scenario.label}'"
    end

    if scenario.expect_group_badge do
      assert html_comanda =~ "Grupo",
             "expected 'Grupo' badge in comanda for scenario '#{scenario.label}'"
    else
      refute html_comanda =~ "Grupo",
             "unexpected 'Grupo' badge in comanda for scenario '#{scenario.label}'"
    end

    # Cocina y barra usan badges de texto — la lógica original aplica sin cambios
    for {view_name, html} <- [{"cocina", html_cocina}, {"barra", html_barra}] do
      if scenario.expect_takeout_badge do
        assert html =~ "Para llevar",
               "expected 'Para llevar' badge in #{view_name} for scenario '#{scenario.label}'"
      else
        refute html =~ "Para llevar",
               "unexpected 'Para llevar' badge in #{view_name} for scenario '#{scenario.label}'"
      end

      if scenario.expect_group_badge do
        assert html =~ "Grupo",
               "expected 'Grupo' badge in #{view_name} for scenario '#{scenario.label}'"
      else
        refute html =~ "Grupo",
               "unexpected 'Grupo' badge in #{view_name} for scenario '#{scenario.label}'"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Shared catalog builder
  # ---------------------------------------------------------------------------

  defp build_catalog do
    cat = create_category()
    food = create_food_item(cat.id)
    drink = create_drink_item(cat.id)
    {food, drink}
  end

  defp find_order_item(order, menu_item_id) do
    Enum.find(order.order_items, &(&1.menu_item_id == menu_item_id))
  end
end
