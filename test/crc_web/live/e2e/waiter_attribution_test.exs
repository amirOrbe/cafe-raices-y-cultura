defmodule CRCWeb.E2E.WaiterAttributionTest do
  @moduledoc """
  End-to-end tests for waiter identity and attribution across the full
  order lifecycle.

  Verifies:
  - Every comanda is stamped with the waiter who opened it (user_id)
  - Every item marked as served records who served it (served_by_id)
  - Every closed ticket records who closed it (closed_by_id)
  - Waiters see ONLY their own comandas in /mesa/historial
  - Admins see ALL waiters' comandas and can filter by individual waiter
  - Multiple waiters working simultaneously cause no cross-contamination

  DDT sweep: @waiter_scenarios runs the full lifecycle for three different
  waiters with three different payment methods (tarjeta, efectivo,
  transferencia) so all payment paths are exercised.

  async: false — multiple connected LiveViews, shared DB sandbox, PubSub.
  """

  use CRCWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CRC.E2EFixtures

  # ---------------------------------------------------------------------------
  # DDT table — one row per waiter variant
  # ---------------------------------------------------------------------------

  @waiter_scenarios [
    %{
      label: "pago con tarjeta",
      waiter_name: "Ana Ramírez",
      customer_name: "Familia García",
      payment_method: "tarjeta",
      amount_paid: nil
    },
    %{
      label: "pago en efectivo",
      waiter_name: "Carlos López",
      customer_name: "Cumpleaños Pérez",
      payment_method: "efectivo",
      amount_paid: "250.00"
    },
    %{
      label: "pago por transferencia",
      waiter_name: "Sofía Torres",
      customer_name: "Mesa Negocios",
      payment_method: "transferencia",
      amount_paid: nil
    }
  ]

  for s <- @waiter_scenarios do
    test "ciclo completo — #{s.label}: atribución correcta en orden, items y ticket",
         %{conn: conn} do
      run_full_waiter_lifecycle(conn, unquote(Macro.escape(s)))
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario A: ciclo completo — markup & serving attribution (DDT)
  # ---------------------------------------------------------------------------

  defp run_full_waiter_lifecycle(conn, scenario) do
    waiter = create_user(%{
      name: scenario.waiter_name,
      email: "#{System.unique_integer()}@e2e.test",
      role: "empleado",
      stations: ["sala"],
      password: "pass123456"
    })
    cocinero = create_cocinero()

    cat = create_category()
    food = create_food_item(cat.id)
    drink = create_drink_item(cat.id)

    # --- Step 1: waiter creates order via TableLive ---
    conn_waiter = auth_conn(conn, waiter)
    {:ok, lv_table, _} = live(conn_waiter, "/mesa")
    render_click(lv_table, "open_takeout_modal")
    render_keyup(lv_table, "update_name_input", %{"value" => scenario.customer_name})

    assert {:error, {:live_redirect, %{to: path}}} =
             render_click(lv_table, "create_takeout")

    order_id = path |> String.replace_leading("/mesa/", "") |> String.to_integer()

    # The order belongs to this waiter
    order = CRC.Orders.get_order!(order_id)
    assert order.user_id == waiter.id,
           "expected user_id #{waiter.id} (#{scenario.waiter_name}), got #{order.user_id}"

    # --- Step 2: waiter adds food + drink in OrderLive ---
    {:ok, lv_order, html_comanda} = live(conn_waiter, "/mesa/#{order_id}")
    assert html_comanda =~ scenario.customer_name

    # Add items directly via context (add_item event requires a category selection
    # in the UI which is tested in order_live_test; here we focus on attribution)
    add_item(order_id, food.id)
    add_item(order_id, drink.id)

    # --- Step 3: waiter sends to kitchen ---
    render_click(lv_order, "send_to_kitchen")
    sent_order = CRC.Orders.get_order!(order_id)
    assert sent_order.status == "sent"
    assert Enum.all?(sent_order.order_items, &(&1.status == "sent"))

    # --- Step 4: cocinero marks all items ready (cocina + barra) ---
    conn_cocina = auth_conn(build_conn(), cocinero)
    {:ok, _lv_cocina, _} = live(conn_cocina, "/cocina")

    for oi <- sent_order.order_items do
      {:ok, _} = CRC.Orders.mark_item_ready(oi.id)
    end

    # --- Step 5: waiter sees "¡Todo listo!" banner ---
    Phoenix.PubSub.broadcast(CRC.PubSub, "orders", {:order_updated, order_id})
    html_ready = render(lv_order)
    assert html_ready =~ "¡Todo listo!"

    # --- Step 6: waiter marks EACH item as served ---
    full_order = CRC.Orders.get_order!(order_id)

    for oi <- full_order.order_items do
      html = render_click(lv_order, "mark_item_served", %{"id" => to_string(oi.id)})
      assert html =~ "Servido"
    end

    # Every item has served_by_id = this waiter
    final_order = CRC.Orders.get_order!(order_id)

    for oi <- final_order.order_items do
      assert oi.served_by_id == waiter.id,
             "expected served_by_id #{waiter.id} on item #{oi.id}, got #{oi.served_by_id}"
      assert oi.status == "served"
    end

    # --- Step 7: waiter closes the ticket ---
    render_click(lv_order, "show_payment_step")
    render_click(lv_order, "set_payment_method", %{"method" => scenario.payment_method})

    if scenario.payment_method == "efectivo" do
      render_change(lv_order, "update_amount_paid", %{"value" => scenario.amount_paid})
    end

    render_click(lv_order, "confirm_close_order")
    assert {:error, {:redirect, %{to: "/mesa"}}} =
             render_click(lv_order, "close_bill_modal")

    # Ticket belongs to this waiter — both opened and closed by the same person
    closed = CRC.Orders.get_order!(order_id)
    assert closed.status == "closed"
    assert closed.user_id == waiter.id
    assert closed.closed_by_id == waiter.id
    assert closed.payment_method == scenario.payment_method
    assert Decimal.gt?(closed.total, Decimal.new("0"))
  end

  # ---------------------------------------------------------------------------
  # Scenario B: cada mesero solo ve SUS propias comandas en /mesa/historial
  # ---------------------------------------------------------------------------

  describe "historial — aislamiento por mesero" do
    test "mesero A no ve las comandas del mesero B ni viceversa", %{conn: conn} do
      waiter_a = create_waiter("Mesero A")
      waiter_b = create_waiter("Mesero B")

      # Each waiter closes their own order
      _order_a = create_and_close_order(waiter_a, "Cliente de A")
      _order_b = create_and_close_order(waiter_b, "Cliente de B")

      # Waiter A sees only their own
      conn_a = auth_conn(conn, waiter_a)
      {:ok, _, html_a} = live(conn_a, "/mesa/historial")
      assert html_a =~ "Cliente de A"
      refute html_a =~ "Cliente de B"

      # Waiter B sees only their own
      conn_b = auth_conn(build_conn(), waiter_b)
      {:ok, _, html_b} = live(conn_b, "/mesa/historial")
      assert html_b =~ "Cliente de B"
      refute html_b =~ "Cliente de A"
    end

    test "mesero ve todas sus comandas cerradas del día", %{conn: conn} do
      waiter = create_waiter()
      other = create_waiter("Otro Mesero")

      # Waiter closes 3 orders
      create_and_close_order(waiter, "Comanda Alfa")
      create_and_close_order(waiter, "Comanda Beta")
      create_and_close_order(waiter, "Comanda Gamma")
      # Other waiter closes 1 order — should not appear
      create_and_close_order(other, "Comanda Ajena")

      conn_waiter = auth_conn(conn, waiter)
      {:ok, _, html} = live(conn_waiter, "/mesa/historial")

      assert html =~ "Comanda Alfa"
      assert html =~ "Comanda Beta"
      assert html =~ "Comanda Gamma"
      refute html =~ "Comanda Ajena"
    end

    test "mesero sin comandas cerradas ve historial vacío", %{conn: conn} do
      waiter_sin_historial = create_waiter("Sin Historial")
      # Another waiter has orders — should not contaminate
      other = create_waiter()
      create_and_close_order(other, "Contaminante")

      conn_waiter = auth_conn(conn, waiter_sin_historial)
      {:ok, _, html} = live(conn_waiter, "/mesa/historial")

      refute html =~ "Contaminante"
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario C: admin ve todas las comandas y puede filtrar por mesero
  # ---------------------------------------------------------------------------

  describe "historial — vista de admin" do
    test "admin ve comandas de todos los meseros", %{conn: conn} do
      admin = create_admin()
      waiter_x = create_waiter("Mesero X")
      waiter_y = create_waiter("Mesero Y")

      create_and_close_order(waiter_x, "Orden de X")
      create_and_close_order(waiter_y, "Orden de Y")

      conn_admin = auth_conn(conn, admin)
      {:ok, _, html} = live(conn_admin, "/mesa/historial")

      assert html =~ "Orden de X"
      assert html =~ "Orden de Y"
    end

    test "admin ve el nombre del mesero en cada fila", %{conn: conn} do
      admin = create_admin()
      waiter = create_waiter("Fernanda Ríos")
      create_and_close_order(waiter, "La Mesa de Fernanda")

      conn_admin = auth_conn(conn, admin)
      {:ok, _, html} = live(conn_admin, "/mesa/historial")

      # Admin view shows the waiter's name as a badge on each row
      assert html =~ "Fernanda Ríos"
    end

    test "admin puede filtrar historial por un mesero específico", %{conn: conn} do
      admin = create_admin()
      waiter_a = create_waiter("Raúl Soto")
      waiter_b = create_waiter("Pilar Vega")

      create_and_close_order(waiter_a, "Solo de Raúl")
      create_and_close_order(waiter_b, "Solo de Pilar")

      conn_admin = auth_conn(conn, admin)
      {:ok, lv, _} = live(conn_admin, "/mesa/historial")

      # Filter by waiter_a
      render_change(lv, "filter_user", %{"user_id" => to_string(waiter_a.id)})

      html_filtered = render(lv)
      assert html_filtered =~ "Solo de Raúl"
      refute html_filtered =~ "Solo de Pilar"
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario D (DDT): múltiples meseros simultáneos — sin contaminación cruzada
  # ---------------------------------------------------------------------------

  @concurrent_waiters [
    %{name: "Mesero 1", customer: "Mesa Norte"},
    %{name: "Mesero 2", customer: "Mesa Sur"},
    %{name: "Mesero 3", customer: "Mesa Este"}
  ]

  describe "múltiples meseros en simultáneo" do
    test "tres meseros abren comandas a la vez, cada una pertenece al mesero correcto",
         %{conn: _conn} do
      # Create all waiters and their orders
      waiter_orders =
        for s <- @concurrent_waiters do
          waiter = create_user(%{
            name: s.name,
            email: "#{System.unique_integer()}@e2e.test",
            role: "empleado",
            stations: ["sala"],
            password: "pass123456"
          })

          order = create_order(%{customer_name: s.customer, user_id: waiter.id})
          {waiter, order}
        end

      # DB attribution: every order's user_id matches the waiter who opened it
      for {waiter, order} <- waiter_orders do
        assert order.user_id == waiter.id,
               "expected #{waiter.name} to own order #{order.id}"
      end

      # Floor map is a SHARED restaurant view — all tableless dine-in orders
      # are visible to every waiter (each individual order page is still tied
      # to the waiter who opened it via user_id).
      for {waiter, _order} <- waiter_orders do
        conn_w = auth_conn(build_conn(), waiter)
        {:ok, _, html} = live(conn_w, "/mesa")

        # All 3 orders appear on every waiter's floor map (shared view)
        for {_other, other_order} <- waiter_orders do
          assert html =~ other_order.customer_name
        end
      end
    end

    test "tres meseros cierran sus comandas, cada ticket pertenece a quien lo cerró",
         %{conn: _conn} do
      cat = create_category()
      food = create_food_item(cat.id)

      closed_orders =
        for s <- @concurrent_waiters do
          waiter = create_user(%{
            name: s.name,
            email: "#{System.unique_integer()}@e2e.test",
            role: "empleado",
            stations: ["sala"],
            password: "pass123456"
          })

          order = create_order(%{customer_name: s.customer, user_id: waiter.id})
          add_item(order.id, food.id)

          conn_w = auth_conn(build_conn(), waiter)
          {:ok, lv, _} = live(conn_w, "/mesa/#{order.id}")

          render_click(lv, "show_payment_step")
          render_click(lv, "set_payment_method", %{"method" => "tarjeta"})
          render_click(lv, "confirm_close_order")
          render_click(lv, "close_bill_modal")

          closed = CRC.Orders.get_order!(order.id)
          {waiter, closed}
        end

      for {waiter, closed} <- closed_orders do
        assert closed.status == "closed"
        # Opened AND closed by the same waiter
        assert closed.user_id == waiter.id,
               "expected user_id #{waiter.id}, got #{closed.user_id}"
        assert closed.closed_by_id == waiter.id,
               "expected closed_by_id #{waiter.id}, got #{closed.closed_by_id}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario E: marcar items como servidos registra al mesero correcto
  # ---------------------------------------------------------------------------

  describe "mark_item_served — atribución en OrderItem" do
    test "served_by_id queda grabado correctamente en cada item", %{conn: conn} do
      waiter = create_waiter("Mesero Servicio")
      cat = create_category()
      food = create_food_item(cat.id)
      drink = create_drink_item(cat.id)

      order = create_order(%{customer_name: "Mesa Servicio", user_id: waiter.id})
      add_item(order.id, food.id)
      add_item(order.id, drink.id)

      # Items must be ready before waiter can serve them
      {:ok, _} = CRC.Orders.send_to_kitchen(order)
      full_order = CRC.Orders.get_order!(order.id)

      for oi <- full_order.order_items do
        {:ok, _} = CRC.Orders.mark_item_ready(oi.id)
      end

      conn_waiter = auth_conn(conn, waiter)
      {:ok, lv, _} = live(conn_waiter, "/mesa/#{order.id}")

      Phoenix.PubSub.broadcast(CRC.PubSub, "orders", {:order_updated, order.id})

      # Waiter marks each item served via LiveView event
      ready_order = CRC.Orders.get_order!(order.id)

      for oi <- ready_order.order_items do
        html = render_click(lv, "mark_item_served", %{"id" => to_string(oi.id)})
        assert html =~ "Servido"
      end

      # Verify served_by_id in DB for every item
      served_order = CRC.Orders.get_order!(order.id)

      for oi <- served_order.order_items do
        assert oi.status == "served",
               "expected item #{oi.id} to be served, got #{oi.status}"
        assert oi.served_by_id == waiter.id,
               "expected served_by_id #{waiter.id} on item #{oi.id}, got #{oi.served_by_id}"
      end
    end

    test "dos meseros sirven sus propias mesas — served_by_id no se mezcla",
         %{conn: conn} do
      waiter_a = create_waiter("Mesero A Serve")
      waiter_b = create_waiter("Mesero B Serve")
      cat = create_category()
      food = create_food_item(cat.id)

      # Each waiter has their own order
      order_a = create_order(%{customer_name: "Mesa A", user_id: waiter_a.id})
      order_b = create_order(%{customer_name: "Mesa B", user_id: waiter_b.id})
      add_item(order_a.id, food.id)
      add_item(order_b.id, food.id)

      # Both orders go through kitchen
      {:ok, _} = CRC.Orders.send_to_kitchen(order_a)
      {:ok, _} = CRC.Orders.send_to_kitchen(order_b)

      for order <- [CRC.Orders.get_order!(order_a.id), CRC.Orders.get_order!(order_b.id)],
          oi <- order.order_items do
        {:ok, _} = CRC.Orders.mark_item_ready(oi.id)
      end

      # Waiter A serves their table
      conn_a = auth_conn(conn, waiter_a)
      {:ok, lv_a, _} = live(conn_a, "/mesa/#{order_a.id}")
      full_a = CRC.Orders.get_order!(order_a.id)
      for oi <- full_a.order_items, do: render_click(lv_a, "mark_item_served", %{"id" => to_string(oi.id)})

      # Waiter B serves their table
      conn_b = auth_conn(build_conn(), waiter_b)
      {:ok, lv_b, _} = live(conn_b, "/mesa/#{order_b.id}")
      full_b = CRC.Orders.get_order!(order_b.id)
      for oi <- full_b.order_items, do: render_click(lv_b, "mark_item_served", %{"id" => to_string(oi.id)})

      # Items from order A served by waiter A
      for oi <- CRC.Orders.get_order!(order_a.id).order_items do
        assert oi.served_by_id == waiter_a.id
      end

      # Items from order B served by waiter B
      for oi <- CRC.Orders.get_order!(order_b.id).order_items do
        assert oi.served_by_id == waiter_b.id
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Creates an order and closes it via context (bypasses UI for speed).
  # get_order!/1 is called to preload :order_items before close_order/3, which
  # calls calculate_order_total/1 that iterates the association.
  defp create_and_close_order(waiter, customer_name) do
    raw = create_order(%{customer_name: customer_name, user_id: waiter.id})
    order = CRC.Orders.get_order!(raw.id)
    {:ok, closed} = CRC.Orders.close_order(order, %{payment_method: "tarjeta"}, waiter.id)
    closed
  end
end
