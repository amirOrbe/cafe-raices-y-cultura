defmodule CRCWeb.Barra.DisplayLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ecto.Query, only: [from: 2]

  alias CRC.Accounts.User
  alias CRC.Orders
  alias CRC.Catalog

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Barman",
          email: "barra#{System.unique_integer()}@cafe.com",
          role: "empleado",
          stations: ["barra"],
          password: "pass123456"
        },
        overrides
      )

    {:ok, user} = %User{} |> User.changeset(attrs) |> CRC.Repo.insert()
    user
  end

  defp auth_conn(conn) do
    user = insert_user()
    {init_test_session(conn, %{"user_id" => user.id}), user}
  end

  defp insert_category(_kind \\ "drink") do
    {:ok, cat} = Catalog.create_category(%{name: "Cat #{System.unique_integer()}"})
    cat
  end

  defp insert_menu_item(category_id, name \\ "Bebida", destination \\ "barra") do
    {:ok, item} =
      Catalog.create_menu_item(%{
        name: name,
        price: "60.00",
        category_id: category_id,
        destination: destination
      })

    item
  end

  defp insert_order(overrides \\ %{}) do
    {:ok, order} = Orders.create_order(Map.merge(%{customer_name: "Test"}, overrides))
    order
  end

  defp insert_order_item(order_id, menu_item_id, overrides \\ %{}) do
    {:ok, item} =
      Orders.add_item(
        Map.merge(%{order_id: order_id, menu_item_id: menu_item_id, quantity: 1}, overrides)
      )

    item
  end

  # ---------------------------------------------------------------------------
  # Authentication
  # ---------------------------------------------------------------------------

  describe "authentication" do
    test "redirects to login when not authenticated", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, "/barra")
      assert path =~ "/iniciar-sesion"
    end
  end

  # ---------------------------------------------------------------------------
  # Empty state
  # ---------------------------------------------------------------------------

  describe "empty state" do
    test "shows no-orders message when nothing is sent", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, _lv, html} = live(conn, "/barra")
      assert html =~ "No hay bebidas pendientes"
    end

    test "does not show open (unsent) orders", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "open"})
      insert_order_item(order.id, mi.id, %{status: "pending"})
      {:ok, _lv, html} = live(conn, "/barra")
      assert html =~ "No hay bebidas pendientes"
    end
  end

  # ---------------------------------------------------------------------------
  # Drink-only filtering
  # ---------------------------------------------------------------------------

  describe "drink filtering" do
    test "shows barra items from sent orders", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, "Café de olla")
      order = insert_order(%{customer_name: "Mesa 5", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, _lv, html} = live(conn, "/barra")
      assert html =~ "Café De Olla"
      assert html =~ "Mesa 5"
    end

    test "does NOT show cocina items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      food_mi = insert_menu_item(cat.id, "Chilaquiles", "cocina")
      order = insert_order(%{customer_name: "Solo Comida", status: "sent"})
      insert_order_item(order.id, food_mi.id, %{status: "sent"})
      {:ok, _lv, html} = live(conn, "/barra")
      refute html =~ "Chilaquiles"
      refute html =~ "Solo Comida"
    end

    test "does NOT show pending (not yet sent) barra items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, "Agua fresca")
      order = insert_order(%{customer_name: "Sin Enviar", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "pending"})
      {:ok, _lv, html} = live(conn, "/barra")
      refute html =~ "Agua fresca"
    end

    test "shows multiple barra items from the same order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi1 = insert_menu_item(cat.id, "Limonada")
      mi2 = insert_menu_item(cat.id, "Jamaica")
      order = insert_order(%{customer_name: "Dos Bebidas", status: "sent"})
      insert_order_item(order.id, mi1.id, %{status: "sent"})
      insert_order_item(order.id, mi2.id, %{status: "sent"})
      {:ok, _lv, html} = live(conn, "/barra")
      assert html =~ "Limonada"
      assert html =~ "Jamaica"
    end
  end

  # ---------------------------------------------------------------------------
  # mark_item_ready
  # ---------------------------------------------------------------------------

  describe "mark_item_ready" do
    test "marks drink item as ready", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, "Horchata")
      order = insert_order(%{customer_name: "Lista", status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/barra")

      render_click(lv, "mark_item_ready", %{"id" => to_string(item.id)})

      reloaded = Orders.get_order!(order.id)
      assert hd(reloaded.order_items).status == "ready"
    end

    test "removes drink from queue after marking it ready", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, "Tepache")
      order = insert_order(%{customer_name: "Listo Ya", status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/barra")

      html = render_click(lv, "mark_item_ready", %{"id" => to_string(item.id)})
      # Item moves to "ready" — disappears from the bar queue
      refute html =~ "Tepache"
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  describe "PubSub" do
    test "refreshes when order_updated is broadcast", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, html} = live(conn, "/barra")
      assert html =~ "No hay bebidas pendientes"

      cat = insert_category()
      mi = insert_menu_item(cat.id, "Michelada")
      order = insert_order(%{customer_name: "PubSub Barra", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})

      Phoenix.PubSub.broadcast(CRC.PubSub, "orders", {:order_updated, order.id})

      html = render(lv)
      assert html =~ "Michelada"
    end
  end

  # ---------------------------------------------------------------------------
  # Mixed order (food + drinks) — barra only sees drinks
  # ---------------------------------------------------------------------------

  describe "mixed order" do
    test "barra only shows barra items from a mixed order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      food_mi = insert_menu_item(cat.id, "Pozole", "cocina")
      drink_mi = insert_menu_item(cat.id, "Agua de tamarindo")
      order = insert_order(%{customer_name: "Mixto", status: "sent"})
      insert_order_item(order.id, food_mi.id, %{status: "sent"})
      insert_order_item(order.id, drink_mi.id, %{status: "sent"})
      {:ok, _lv, html} = live(conn, "/barra")
      refute html =~ "Pozole"
      assert html =~ "Agua De Tamarindo"
    end
  end

  describe "nav events" do
    test "toggle_nav opens and closes nav", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/barra")

      render_click(lv, "toggle_nav", %{})
      render_click(lv, "toggle_nav", %{})
      assert render(lv) =~ "Barra"
    end

    test "close_nav closes nav", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/barra")

      render_click(lv, "toggle_nav", %{})
      render_click(lv, "close_nav", %{})
      assert render(lv) =~ "Barra"
    end
  end

  describe "mark_item_ready error path" do
    test "handles item not found gracefully", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/barra")

      # Should not crash when item id doesn't exist
      html = render_click(lv, "mark_item_ready", %{"id" => "0"})
      assert html =~ "Barra"
    end
  end

  describe "drink item with ready status" do
    test "does NOT show already-ready drinks in the pending queue", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, "Agua Lista")
      order = insert_order(%{customer_name: "Bebida Lista", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "ready"})

      {:ok, _lv, html} = live(conn, "/barra")
      # Already-ready drinks must not resurface in the bar queue
      refute html =~ "Agua Lista"
    end
  end

  # ---------------------------------------------------------------------------
  # Bug regression: second-batch sends must not resurface already-ready drinks
  # ---------------------------------------------------------------------------

  describe "second batch does not resurface ready drinks (Bug 1)" do
    test "only shows newly-sent drinks when a second batch arrives", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi1 = insert_menu_item(cat.id, "Limonada Servida")
      mi2 = insert_menu_item(cat.id, "Horchata Nueva")
      order = insert_order(%{customer_name: "Mesa Segundas Barra", status: "sent"})

      # First batch: mi1 already served (ready)
      insert_order_item(order.id, mi1.id, %{status: "ready"})
      # Second batch: mi2 newly sent
      insert_order_item(order.id, mi2.id, %{status: "sent"})

      {:ok, _lv, html} = live(conn, "/barra")

      assert html =~ "Horchata Nueva"
      refute html =~ "Limonada Servida"
    end

    test "order leaves pending queue (moves to Listos) when all drinks are marked ready", %{
      conn: conn
    } do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id, "Café Final")
      order = insert_order(%{customer_name: "Solo Barra", status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/barra")

      html = render_click(lv, "mark_item_ready", %{"id" => to_string(item.id)})
      # Order moves to "Listos para servir" section — no longer in pending queue
      assert html =~ "Listos para servir"
    end
  end

  # ---------------------------------------------------------------------------
  # Bug regression: barra must show orders whose status advanced to "ready"
  # while a drink item is still "sent" (Bug 2)
  # ---------------------------------------------------------------------------

  describe "pending drinks visible when order status is ready (Bug 2)" do
    test "shows order in barra if a drink is still sent, even when order.status == ready", %{
      conn: conn
    } do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id, "Refresco Pendiente")
      # Simulate: kitchen used mark_order_ready while 1 drink was still "sent"
      order = insert_order(%{customer_name: "Orden Casi Lista", status: "ready"})
      insert_order_item(order.id, mi.id, %{status: "sent"})

      {:ok, _lv, html} = live(conn, "/barra")
      assert html =~ "Refresco Pendiente"
    end

    test "partial mark: 3 of 4 drinks ready — remaining sent drink still shows", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi_a = insert_menu_item(drink_cat.id, "Bebida A")
      mi_b = insert_menu_item(drink_cat.id, "Bebida B")
      mi_c = insert_menu_item(drink_cat.id, "Bebida C")
      mi_d = insert_menu_item(drink_cat.id, "Bebida D Pendiente")
      order = insert_order(%{customer_name: "Cuatro Bebidas", status: "sent"})
      insert_order_item(order.id, mi_a.id, %{status: "ready"})
      insert_order_item(order.id, mi_b.id, %{status: "ready"})
      insert_order_item(order.id, mi_c.id, %{status: "ready"})
      insert_order_item(order.id, mi_d.id, %{status: "sent"})

      {:ok, _lv, html} = live(conn, "/barra")
      assert html =~ "Bebida D Pendiente"
      refute html =~ "Bebida A"
      refute html =~ "Bebida B"
      refute html =~ "Bebida C"
    end

    test "order disappears from barra once all drinks (including last one) are ready", %{
      conn: conn
    } do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id, "Última Bebida")
      order = insert_order(%{customer_name: "Última Mesa", status: "ready"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/barra")

      html = render_click(lv, "mark_item_ready", %{"id" => to_string(item.id)})
      # Item name no longer shown in the pending section (moved to ready)
      refute html =~ "Última Bebida"
      # Order moves to "Listos para servir" section (customer name still shown there)
      assert html =~ "Listos para servir"
      assert html =~ "Última Mesa"
    end
  end

  describe "pedido/pedidos pluralization" do
    test "shows pedido (singular) for one pending drink order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id, "Bebida Singular")
      order = insert_order(%{customer_name: "Solo Uno", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})

      {:ok, _lv, html} = live(conn, "/barra")
      assert html =~ "pedido"
    end
  end

  describe "drink item with notes" do
    test "shows item notes when present", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id, "Café con instrucciones")
      order = insert_order(%{customer_name: "Con Notas Barra", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent", notes: "sin azúcar"})

      {:ok, _lv, html} = live(conn, "/barra")
      assert html =~ "sin azúcar"
    end
  end

  # ---------------------------------------------------------------------------
  # REGRESSION: mark_all_drinks_ready (Todo listo barra) must bulk-mark
  # all sent drink items as ready and move them to "Listos para servir"
  # ---------------------------------------------------------------------------

  describe "mark_all_drinks_ready — Todo listo barra regression" do
    test "all sent drink items become ready after mark_all_drinks_ready", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi1 = insert_menu_item(drink_cat.id, "Latte Todo Listo")
      mi2 = insert_menu_item(drink_cat.id, "Cappuccino Todo Listo")
      order = insert_order(%{customer_name: "Mesa Barra Listo", status: "sent"})
      item1 = insert_order_item(order.id, mi1.id, %{status: "sent"})
      item2 = insert_order_item(order.id, mi2.id, %{status: "sent"})

      {:ok, lv, html_before} = live(conn, "/barra")
      assert html_before =~ "Latte Todo Listo"

      render_click(lv, "mark_all_drinks_ready", %{"id" => to_string(order.id)})

      reloaded1 = CRC.Repo.get!(CRC.Orders.OrderItem, item1.id)
      reloaded2 = CRC.Repo.get!(CRC.Orders.OrderItem, item2.id)
      assert reloaded1.status == "ready"
      assert reloaded2.status == "ready"
    end

    test "order moves out of pending queue after mark_all_drinks_ready", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id, "Mocha Desaparece")
      order = insert_order(%{customer_name: "Mesa Desaparece Barra", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})

      {:ok, lv, html_before} = live(conn, "/barra")
      assert html_before =~ "Mocha Desaparece"

      html_after = render_click(lv, "mark_all_drinks_ready", %{"id" => to_string(order.id)})
      refute html_after =~ "Mocha Desaparece"
    end

    test "shows flash message after mark_all_drinks_ready", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, "Bebida Flash Barra")
      order = insert_order(%{customer_name: "Mesa Flash Barra", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})

      {:ok, lv, _} = live(conn, "/barra")
      html = render_click(lv, "mark_all_drinks_ready", %{"id" => to_string(order.id)})
      assert html =~ "lista en barra"
    end

    test "already-ready drinks are not re-processed", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi1 = insert_menu_item(cat.id, "Ya Lista Barra")
      mi2 = insert_menu_item(cat.id, "Pendiente Barra")
      order = insert_order(%{customer_name: "Mesa Mixta Barra Ready", status: "sent"})
      item_ready = insert_order_item(order.id, mi1.id, %{status: "ready"})
      item_sent = insert_order_item(order.id, mi2.id, %{status: "sent"})

      {:ok, lv, _} = live(conn, "/barra")
      render_click(lv, "mark_all_drinks_ready", %{"id" => to_string(order.id)})

      reloaded_ready = CRC.Repo.get!(CRC.Orders.OrderItem, item_ready.id)
      reloaded_sent = CRC.Repo.get!(CRC.Orders.OrderItem, item_sent.id)
      assert reloaded_ready.status == "ready"
      assert reloaded_sent.status == "ready"
    end

    test "cocina items in the same order are NOT marked ready by barra", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      drink_mi = insert_menu_item(cat.id, "Bebida Barra", "barra")
      food_mi = insert_menu_item(cat.id, "Taco No Barra", "cocina")
      order = insert_order(%{customer_name: "Mesa Mixta Food Barra", status: "sent"})
      drink_item = insert_order_item(order.id, drink_mi.id, %{status: "sent"})
      food_item = insert_order_item(order.id, food_mi.id, %{status: "sent"})

      {:ok, lv, _} = live(conn, "/barra")
      render_click(lv, "mark_all_drinks_ready", %{"id" => to_string(order.id)})

      reloaded_drink = CRC.Repo.get!(CRC.Orders.OrderItem, drink_item.id)
      reloaded_food = CRC.Repo.get!(CRC.Orders.OrderItem, food_item.id)
      assert reloaded_drink.status == "ready"
      assert reloaded_food.status == "sent"
    end
  end

  # ---------------------------------------------------------------------------
  # Temperature tabs (Calientes / Frías) and "Preparar" claims
  # ---------------------------------------------------------------------------

  defp insert_typed_drink(name, barra_type) do
    {:ok, item} =
      Catalog.create_menu_item(%{
        name: name,
        price: "60.00",
        category_id: insert_category().id,
        destination: "barra",
        barra_type: barra_type
      })

    item
  end

  defp sent_order_with(name, menu_items) do
    order = insert_order(%{customer_name: name, status: "sent"})
    items = for mi <- menu_items, do: insert_order_item(order.id, mi.id, %{status: "sent"})
    {order, items}
  end

  describe "temperature tabs" do
    test "shows only the selected tab's drinks", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      sent_order_with("Mesa Café", [insert_typed_drink("Capuchino Tab", "caliente")])
      sent_order_with("Mesa Frappé", [insert_typed_drink("Frappé Tab", "fria")])

      {:ok, _lv, html} = live(conn, "/barra?tipo=caliente")
      assert html =~ "Capuchino Tab"
      refute html =~ "Frappé Tab"

      {:ok, _lv, html} = live(conn, "/barra?tipo=fria")
      assert html =~ "Frappé Tab"
      refute html =~ "Capuchino Tab"
    end

    test "without ?tipo opens the first tab that has pending drinks", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      sent_order_with("Solo Frías", [insert_typed_drink("Limonada Tab", "fria")])

      {:ok, _lv, html} = live(conn, "/barra")
      assert html =~ "Limonada Tab"
    end

    test "an unpinned tab follows new drinks; a pinned one stays put", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, free_lv, _} = live(conn, "/barra")
      {:ok, pinned_lv, _} = live(conn, "/barra?tipo=caliente")

      {order, _} = sent_order_with("Llega Fría", [insert_typed_drink("Malteada Tab", "fria")])
      Phoenix.PubSub.broadcast(CRC.PubSub, "orders", {:order_updated, order.id})

      assert render(free_lv) =~ "Malteada Tab"
      refute render(pinned_lv) =~ "Malteada Tab"
      assert render(pinned_lv) =~ "Nada pendiente en esta pestaña"
    end
  end

  describe "Preparar (claim) / Soltar" do
    test "claiming shows who is preparing and swaps Preparar for Soltar", %{conn: conn} do
      {conn, user} = auth_conn(conn)

      {_order, [item]} =
        sent_order_with("Mesa Claim", [insert_typed_drink("Latte Claim", "caliente")])

      {:ok, lv, html} = live(conn, "/barra?tipo=caliente")
      assert html =~ "Preparar"

      html = render_click(lv, "start_items", %{"ids" => to_string(item.id)})
      assert html =~ "Tú estás preparando"
      assert html =~ "Soltar"
      assert CRC.Repo.get!(CRC.Orders.OrderItem, item.id).started_by_id == user.id

      html = render_click(lv, "release_items", %{"ids" => to_string(item.id)})
      refute html =~ "preparando"
      assert CRC.Repo.get!(CRC.Orders.OrderItem, item.id).started_by_id == nil
    end

    test "a drink another barista already took can't be claimed again", %{conn: conn} do
      {conn, _me} = auth_conn(conn)
      other = insert_user(%{name: "Barista Luis"})

      {_order, [item]} =
        sent_order_with("Mesa Ocupada", [insert_typed_drink("Moka Claim", "caliente")])

      {:ok, 1} = Orders.start_items([item.id], other.id)

      {:ok, lv, html} = live(conn, "/barra?tipo=caliente")
      assert html =~ "Barista Luis preparando"
      refute html =~ "⏳ Preparar"

      html = render_click(lv, "start_items", %{"ids" => to_string(item.id)})
      assert html =~ "Otro barista ya las está preparando"
      assert CRC.Repo.get!(CRC.Orders.OrderItem, item.id).started_by_id == other.id
    end
  end

  describe "per-drink claim (Tomar) and protection" do
    test "Tomar claims a single drink so a big comanda can be split", %{conn: conn} do
      {conn, user} = auth_conn(conn)

      {_order, [a, b]} =
        sent_order_with("Mesa Grande", [
          insert_typed_drink("Latte Split", "caliente"),
          insert_typed_drink("Moka Split", "caliente")
        ])

      {:ok, lv, _} = live(conn, "/barra?tipo=caliente")
      html = render_click(lv, "start_items", %{"ids" => to_string(a.id)})

      assert CRC.Repo.get!(CRC.Orders.OrderItem, a.id).started_by_id == user.id
      assert CRC.Repo.get!(CRC.Orders.OrderItem, b.id).started_by_id == nil
      # The other drink is still free for someone else
      assert html =~ "Tomar"
    end

    test "another barista's drink shows their name instead of Listo and can't be marked",
         %{conn: conn} do
      {conn, _me} = auth_conn(conn)
      other = insert_user(%{name: "Barista Ana"})

      {_order, [item]} =
        sent_order_with("Mesa Ana", [insert_typed_drink("Chai Ana", "caliente")])

      {:ok, 1} = Orders.start_items([item.id], other.id)
      {:ok, lv, _} = live(conn, "/barra?tipo=caliente")

      refute has_element?(lv, ~s(button[phx-click="mark_item_ready"][phx-value-id="#{item.id}"]))

      # A stale screen can still send it: the server refuses
      html = render_click(lv, "mark_item_ready", %{"id" => to_string(item.id)})
      assert html =~ "Barista Ana la está preparando"
      assert CRC.Repo.get!(CRC.Orders.OrderItem, item.id).status == "sent"
    end

    test "Todo listo on someone else's drinks asks for a second tap", %{conn: conn} do
      {conn, _me} = auth_conn(conn)
      other = insert_user(%{name: "Barista Ana"})

      {order, [item]} =
        sent_order_with("Mesa Confirmar", [insert_typed_drink("Flat White", "caliente")])

      {:ok, 1} = Orders.start_items([item.id], other.id)
      {:ok, lv, _} = live(conn, "/barra?tipo=caliente")

      card = "#drink-order-#{order.id}-caliente"
      html = lv |> element("#{card} button", "Todo listo") |> render_click()
      assert html =~ "Barista Ana está preparando parte de esto"
      assert CRC.Repo.get!(CRC.Orders.OrderItem, item.id).status == "sent"

      lv |> element("#{card} button", "Sí, todo listo") |> render_click()
      assert CRC.Repo.get!(CRC.Orders.OrderItem, item.id).status == "ready"
    end

    test "Todo listo on my own or free drinks needs no confirmation", %{conn: conn} do
      {conn, _me} = auth_conn(conn)

      {order, [item]} =
        sent_order_with("Mesa Libre", [insert_typed_drink("Americano Libre", "caliente")])

      {:ok, lv, _} = live(conn, "/barra?tipo=caliente")
      lv |> element("#drink-order-#{order.id}-caliente button", "Todo listo") |> render_click()
      assert CRC.Repo.get!(CRC.Orders.OrderItem, item.id).status == "ready"
    end
  end

  describe "grouped view row label" do
    test "shows the comanda and the person, not the person alone", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      mi = insert_typed_drink("Chai Agrupado", "caliente")
      order = insert_order(%{customer_name: "Cumple Sofía", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent", for_person: "Diego"})

      {:ok, lv, _} = live(conn, "/barra?tipo=caliente")
      html = render_click(lv, "set_view_mode", %{"mode" => "grouped"})

      assert html =~ "Cumple Sofía"
      assert html =~ "Diego"
    end
  end

  describe "queue numbers (1 = waited longest)" do
    defp sent_minutes_ago(item, minutes) do
      at = DateTime.utc_now() |> DateTime.add(-minutes * 60) |> DateTime.truncate(:second)

      CRC.Repo.update_all(
        from(oi in CRC.Orders.OrderItem, where: oi.id == ^item.id),
        set: [sent_at: at]
      )
    end

    test "per-order view numbers cards from the oldest", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      mi = insert_typed_drink("Café Turno", "caliente")
      {new_order, [new_item]} = sent_order_with("Mesa Nueva", [mi])
      {old_order, [old_item]} = sent_order_with("Mesa Vieja", [mi])
      sent_minutes_ago(new_item, 2)
      sent_minutes_ago(old_item, 15)

      {:ok, lv, _} = live(conn, "/barra?tipo=caliente")

      assert lv
             |> element("#drink-order-#{old_order.id}-caliente span[title='Turno 1']")
             |> has_element?()

      assert lv
             |> element("#drink-order-#{new_order.id}-caliente span[title='Turno 2']")
             |> has_element?()
    end

    test "grouped view puts the longest-waiting drink first, not the biggest batch", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      chai = insert_typed_drink("Chai Solito", "caliente")
      latte = insert_typed_drink("Latte Montón", "caliente")
      {_, [chai_item]} = sent_order_with("Mesa Chai", [chai])
      {_, latte_items} = sent_order_with("Mesa Lattes", [latte, latte, latte])
      sent_minutes_ago(chai_item, 20)
      Enum.each(latte_items, &sent_minutes_ago(&1, 3))

      {:ok, lv, _} = live(conn, "/barra?tipo=caliente")
      render_click(lv, "set_view_mode", %{"mode" => "grouped"})

      assert lv |> element("#drink-group-#{chai.id} span[title='Turno 1']") |> has_element?()
      assert lv |> element("#drink-group-#{latte.id} span[title='Turno 2']") |> has_element?()
    end
  end
end
