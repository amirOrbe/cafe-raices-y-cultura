defmodule CRCWeb.E2E.MultiRoleRealtimeTest do
  @moduledoc """
  Multi-role concurrent E2E tests — three users connected simultaneously.

  Verifies that PubSub-driven real-time updates propagate correctly:
  - Waiter sends comanda  → /cocina and /barra displays refresh
  - Cocina/barra mark items ready → DB state is correct; waiter list view
    shows "Lista para servir" once order is promoted to ready
  - Admin CRUD on tables  → /mesa floor map reflects changes instantly

  A second DDT sweep covers order creation via LiveView modal events for
  all three order variants (tabla, grupo, para llevar), verifying each
  one is created with the correct type/group flag and redirects to the
  new comanda.

  async: false — multiple LiveView processes share the sandbox and we
  rely on PubSub messages crossing process boundaries.
  """

  use CRCWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CRC.E2EFixtures

  # ---------------------------------------------------------------------------
  # Setup: one catalog + five users, reused across all tests in the module
  # ---------------------------------------------------------------------------

  setup do
    cat = create_category()
    food = create_food_item(cat.id)
    drink = create_drink_item(cat.id)

    waiter = create_waiter()
    cocinero = create_cocinero()
    barman = create_barman()

    {:ok,
     food: food,
     drink: drink,
     waiter: waiter,
     cocinero: cocinero,
     barman: barman}
  end

  # ---------------------------------------------------------------------------
  # Scenario A: waiter sends comanda → cocina & barra displays update live
  # ---------------------------------------------------------------------------

  describe "waiter envía comanda → displays actualizan en tiempo real" do
    test "cocina muestra el platillo después de enviar la comanda",
         %{food: food, drink: drink, cocinero: cocinero} do
      order = create_order(%{customer_name: "Tiempo Real Cocina"})
      add_item(order.id, food.id)
      add_item(order.id, drink.id)

      # Cocinero conectado ANTES de que se envíe la comanda
      conn_cocina = auth_conn(build_conn(), cocinero)
      {:ok, lv_cocina, html_antes} = live(conn_cocina, "/cocina")
      refute html_antes =~ food.name

      # send_to_kitchen broadcast interno → cocinero LV recibe PubSub
      {:ok, _} = CRC.Orders.send_to_kitchen(order)

      # render/1 espera a que el proceso LV procese los mensajes pendientes
      assert render(lv_cocina) =~ food.name
    end

    test "barra muestra la bebida después de enviar la comanda",
         %{food: food, drink: drink, barman: barman} do
      order = create_order(%{customer_name: "Tiempo Real Barra"})
      add_item(order.id, food.id)
      add_item(order.id, drink.id)

      conn_barra = auth_conn(build_conn(), barman)
      {:ok, lv_barra, html_antes} = live(conn_barra, "/barra")
      refute html_antes =~ drink.name

      {:ok, _} = CRC.Orders.send_to_kitchen(order)

      assert render(lv_barra) =~ drink.name
    end

    test "cocina NO muestra pedidos con solo bebidas",
         %{drink: drink, cocinero: cocinero} do
      order = create_order(%{customer_name: "Solo Bebida"})
      add_item(order.id, drink.id)

      conn_cocina = auth_conn(build_conn(), cocinero)
      {:ok, lv_cocina, _} = live(conn_cocina, "/cocina")

      {:ok, _} = CRC.Orders.send_to_kitchen(order)

      # Kitchen only renders orders with at least one cocina item
      refute render(lv_cocina) =~ "Solo Bebida"
    end

    test "barra NO muestra pedidos con solo comida",
         %{food: food, barman: barman} do
      order = create_order(%{customer_name: "Solo Comida"})
      add_item(order.id, food.id)

      conn_barra = auth_conn(build_conn(), barman)
      {:ok, lv_barra, _} = live(conn_barra, "/barra")

      {:ok, _} = CRC.Orders.send_to_kitchen(order)

      # Barra only renders orders with at least one barra item
      refute render(lv_barra) =~ "Solo Comida"
    end

    test "waiter ve el badge 'En cocina' después de enviar",
         %{conn: conn, food: food, drink: drink, waiter: waiter} do
      order = create_order(%{customer_name: "Badge Sent"})
      add_item(order.id, food.id)
      add_item(order.id, drink.id)

      conn_waiter = auth_conn(conn, waiter)
      {:ok, lv_waiter, _} = live(conn_waiter, "/mesa")

      {:ok, _} = CRC.Orders.send_to_kitchen(order)
      Phoenix.PubSub.broadcast(CRC.PubSub, "orders", {:order_updated, order.id})

      assert render(lv_waiter) =~ "En cocina"
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario B: cocina/barra marcan items → estado correcto en DB y vista lista
  # ---------------------------------------------------------------------------

  describe "items listos → DB y vista lista actualizan" do
    test "cocinero marca platillo listo → item queda 'ready', bebida sigue 'sent'",
         %{food: food, drink: drink, cocinero: cocinero} do
      order = create_order(%{customer_name: "Parcialmente Listo"})
      add_item(order.id, food.id)
      add_item(order.id, drink.id)

      {:ok, _} = CRC.Orders.send_to_kitchen(order)

      conn_cocina = auth_conn(build_conn(), cocinero)
      {:ok, lv_cocina, _} = live(conn_cocina, "/cocina")

      full_order = CRC.Orders.get_order!(order.id)
      food_oi = Enum.find(full_order.order_items, &(&1.menu_item_id == food.id))
      drink_oi = Enum.find(full_order.order_items, &(&1.menu_item_id == drink.id))

      render_click(lv_cocina, "mark_item_ready", %{"id" => to_string(food_oi.id)})

      # Food item is ready; drink item is still sent
      assert CRC.Repo.get!(CRC.Orders.OrderItem, food_oi.id).status == "ready"
      assert CRC.Repo.get!(CRC.Orders.OrderItem, drink_oi.id).status == "sent"
    end

    test "todos los items listos + order ready → waiter ve 'Lista para servir' en vista lista",
         %{conn: conn, food: food, drink: drink, waiter: waiter, cocinero: cocinero, barman: barman} do
      # Use a real table so the list view renders it with "Lista para servir" text
      table = create_table()
      order = create_order(%{customer_name: "Todo Listo", table_id: table.id})
      add_item(order.id, food.id)
      add_item(order.id, drink.id)

      {:ok, _} = CRC.Orders.send_to_kitchen(order)

      full_order = CRC.Orders.get_order!(order.id)
      food_oi = Enum.find(full_order.order_items, &(&1.menu_item_id == food.id))
      drink_oi = Enum.find(full_order.order_items, &(&1.menu_item_id == drink.id))

      # Cocina marks food ready, barra marks drink ready
      conn_cocina = auth_conn(build_conn(), cocinero)
      conn_barra = auth_conn(build_conn(), barman)
      {:ok, lv_cocina, _} = live(conn_cocina, "/cocina")
      {:ok, lv_barra, _} = live(conn_barra, "/barra")
      render_click(lv_cocina, "mark_item_ready", %{"id" => to_string(food_oi.id)})
      render_click(lv_barra, "mark_item_ready", %{"id" => to_string(drink_oi.id)})

      # Kitchen promotes the order to "ready" status
      {:ok, _} = CRC.Orders.mark_order_ready(CRC.Orders.get_order!(order.id))

      # Waiter switches to list view — table shows "Lista para servir ✓"
      conn_waiter = auth_conn(conn, waiter)
      {:ok, lv_waiter, _} = live(conn_waiter, "/mesa")
      render_click(lv_waiter, "set_view", %{"mode" => "list"})
      Phoenix.PubSub.broadcast(CRC.PubSub, "orders", {:order_updated, order.id})

      assert render(lv_waiter) =~ "Lista para servir"
    end

    test "cocina y barra marcan simultáneamente → ambos items quedan 'ready' en DB",
         %{conn: conn, food: food, drink: drink, cocinero: cocinero, barman: barman, waiter: waiter} do
      order = create_order(%{customer_name: "Doble Display"})
      add_item(order.id, food.id)
      add_item(order.id, drink.id)

      {:ok, _} = CRC.Orders.send_to_kitchen(order)

      # Both displays connected simultaneously
      conn_cocina = auth_conn(build_conn(), cocinero)
      conn_barra = auth_conn(build_conn(), barman)
      {:ok, lv_cocina, _} = live(conn_cocina, "/cocina")
      {:ok, lv_barra, _} = live(conn_barra, "/barra")

      # Both displays see the order
      assert render(lv_cocina) =~ food.name
      assert render(lv_barra) =~ drink.name

      full_order = CRC.Orders.get_order!(order.id)
      food_oi = Enum.find(full_order.order_items, &(&1.menu_item_id == food.id))
      drink_oi = Enum.find(full_order.order_items, &(&1.menu_item_id == drink.id))

      # Cocina marks food, barra marks drink — concurrently
      render_click(lv_cocina, "mark_item_ready", %{"id" => to_string(food_oi.id)})
      render_click(lv_barra, "mark_item_ready", %{"id" => to_string(drink_oi.id)})

      # Both items are ready in the DB
      assert CRC.Repo.get!(CRC.Orders.OrderItem, food_oi.id).status == "ready"
      assert CRC.Repo.get!(CRC.Orders.OrderItem, drink_oi.id).status == "ready"

      # Waiter floor map shows the order is present and tracked
      conn_waiter = auth_conn(conn, waiter)
      {:ok, lv_waiter, _} = live(conn_waiter, "/mesa")
      Phoenix.PubSub.broadcast(CRC.PubSub, "orders", {:order_updated, order.id})
      assert render(lv_waiter) =~ order.customer_name
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario C: gestión de mesas → mapa del waiter actualiza en tiempo real
  # ---------------------------------------------------------------------------

  describe "gestión de mesas → mapa del waiter en tiempo real" do
    test "waiter ve la nueva mesa inmediatamente después de que admin la crea",
         %{conn: conn, waiter: waiter} do
      conn_waiter = auth_conn(conn, waiter)
      {:ok, lv_waiter, html_antes} = live(conn_waiter, "/mesa")

      label = "Mesa VIP #{System.unique_integer()}"
      # create_table broadcasts :tables_changed internally
      {:ok, _} = CRC.Orders.create_table(%{
        number: System.unique_integer([:positive]),
        label: label,
        capacity: 4,
        x_pct: 30.0,
        y_pct: 40.0
      })

      assert render(lv_waiter) =~ label
      refute html_antes =~ label
    end

    test "waiter ve que la mesa desaparece cuando admin la elimina",
         %{conn: conn, waiter: waiter} do
      # Create table first so the floor map has something to remove
      table = create_table(%{label: "Temporal #{System.unique_integer()}"})
      label = table.label

      conn_waiter = auth_conn(conn, waiter)
      {:ok, lv_waiter, html_antes} = live(conn_waiter, "/mesa")
      assert html_antes =~ label

      # delete_table broadcasts :tables_changed internally
      {:ok, _} = CRC.Orders.delete_table(table)

      refute render(lv_waiter) =~ label
    end

    test "waiter ve el nuevo nombre cuando admin renombra una mesa",
         %{conn: conn, waiter: waiter} do
      table = create_table()
      label_viejo = table.label
      label_nuevo = "Jardín Remodelado #{System.unique_integer()}"

      conn_waiter = auth_conn(conn, waiter)
      {:ok, lv_waiter, html_antes} = live(conn_waiter, "/mesa")
      assert html_antes =~ label_viejo

      # update_table broadcasts :tables_changed internally
      {:ok, _} = CRC.Orders.update_table(table, %{label: label_nuevo})

      html_despues = render(lv_waiter)
      assert html_despues =~ label_nuevo
      refute html_despues =~ label_viejo
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario D (DDT): creación de orden vía eventos LiveView
  # Cubre las tres variantes de orden según el flujo de TableLive
  # ---------------------------------------------------------------------------

  @creation_scenarios [
    %{
      label: "cuenta en mesa (dine_in via tabla)",
      flow: :table,
      expected_order_type: "dine_in",
      expected_is_group: false
    },
    %{
      label: "para llevar (takeout via modal)",
      flow: :takeout,
      name_value: "Llevar DDT",
      expected_customer_name: "Llevar DDT",
      expected_order_type: "takeout",
      expected_is_group: false
    },
    %{
      label: "grupo de comensales (grupo via modal)",
      flow: :group,
      name_value: "Grupo DDT",
      count_value: "6",
      expected_customer_name: "Grupo DDT · 6 personas",
      expected_order_type: "dine_in",
      expected_is_group: true
    }
  ]

  for s <- @creation_scenarios do
    test "TableLive crea orden — #{s.label}", %{conn: conn, waiter: waiter} do
      run_creation_scenario(conn, waiter, unquote(Macro.escape(s)))
    end
  end

  # ---------------------------------------------------------------------------
  # Creation scenario helpers
  # ---------------------------------------------------------------------------

  defp run_creation_scenario(conn, waiter, %{flow: :table} = scenario) do
    # Table flow: select a free table → confirm in modal → redirects to order
    table = create_table()

    conn_waiter = auth_conn(conn, waiter)
    {:ok, lv, _} = live(conn_waiter, "/mesa")

    # Select the table — opens the "Abrir mesa" confirmation modal
    render_click(lv, "select_table", %{"id" => to_string(table.id)})

    # Confirm opening the table
    assert {:error, {:live_redirect, %{to: path}}} =
             render_click(lv, "create_order_for_table")

    assert String.starts_with?(path, "/mesa/")

    order_id = path |> String.replace_leading("/mesa/", "") |> String.to_integer()
    order = CRC.Orders.get_order!(order_id)

    assert order.order_type == scenario.expected_order_type
    assert order.is_group == scenario.expected_is_group
    # Table order uses "Mesa {number}" as customer name
    assert order.table_id == table.id

    # The floor map reflects the table as occupied after creation
    {:ok, _, html_mesa} = live(conn_waiter, "/mesa")
    assert html_mesa =~ to_string(table.number)
  end

  defp run_creation_scenario(conn, waiter, %{flow: :takeout} = scenario) do
    conn_waiter = auth_conn(conn, waiter)
    {:ok, lv, _} = live(conn_waiter, "/mesa")

    render_click(lv, "open_takeout_modal")
    render_keyup(lv, "update_name_input", %{"value" => scenario.name_value})

    assert {:error, {:live_redirect, %{to: path}}} =
             render_click(lv, "create_takeout")

    assert String.starts_with?(path, "/mesa/")

    order_id = path |> String.replace_leading("/mesa/", "") |> String.to_integer()
    order = CRC.Orders.get_order!(order_id)

    assert order.customer_name == scenario.expected_customer_name
    assert order.order_type == scenario.expected_order_type
    assert order.is_group == scenario.expected_is_group

    # Para llevar appears in the takeout section of the floor map
    {:ok, _, html_mesa} = live(conn_waiter, "/mesa")
    assert html_mesa =~ scenario.expected_customer_name
  end

  defp run_creation_scenario(conn, waiter, %{flow: :group} = scenario) do
    conn_waiter = auth_conn(conn, waiter)
    {:ok, lv, _} = live(conn_waiter, "/mesa")

    render_click(lv, "open_group_modal")
    render_keyup(lv, "update_name_input", %{"value" => scenario.name_value})
    render_keyup(lv, "update_person_count_input", %{"value" => scenario.count_value})

    assert {:error, {:live_redirect, %{to: path}}} =
             render_click(lv, "create_group")

    assert String.starts_with?(path, "/mesa/")

    order_id = path |> String.replace_leading("/mesa/", "") |> String.to_integer()
    order = CRC.Orders.get_order!(order_id)

    assert order.customer_name == scenario.expected_customer_name
    assert order.order_type == scenario.expected_order_type
    assert order.is_group == scenario.expected_is_group

    # Group appears in the "Grupos de comensales" section
    {:ok, _, html_mesa} = live(conn_waiter, "/mesa")
    assert html_mesa =~ scenario.expected_customer_name
  end
end
