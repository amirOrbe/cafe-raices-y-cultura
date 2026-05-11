defmodule CRCWeb.Waiter.TableLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Accounts.User
  alias CRC.Orders

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Waiter",
          email: "waiter#{System.unique_integer()}@cafe.com",
          role: "empleado",
          stations: ["sala"],
          password: "pass123456"
        },
        overrides
      )

    {:ok, user} = %User{} |> User.changeset(attrs) |> CRC.Repo.insert()
    user
  end

  defp auth_conn(conn, role \\ "empleado") do
    user = insert_user(%{role: role})
    {init_test_session(conn, %{"user_id" => user.id}), user}
  end

  defp insert_order(overrides \\ %{}) do
    {:ok, order} = Orders.create_order(Map.merge(%{customer_name: "Juan"}, overrides))
    order
  end

  defp insert_table(overrides \\ %{}) do
    {:ok, table} =
      Orders.create_table(
        Map.merge(
          %{
            number: System.unique_integer([:positive]),
            label: "Mesa Test",
            capacity: 4,
            x_pct: 50.0,
            y_pct: 50.0
          },
          overrides
        )
      )

    table
  end

  # ---------------------------------------------------------------------------
  # Authentication
  # ---------------------------------------------------------------------------

  describe "authentication" do
    test "redirects to login when not authenticated", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, "/mesa")
      assert path =~ "/iniciar-sesion"
    end
  end

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  describe "mount" do
    test "shows 'no tables configured' state when no tables exist", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "No hay mesas configuradas"
    end

    test "shows active open orders in tableless section", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      insert_order(%{customer_name: "Sofía", status: "open"})
      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "Sofía"
    end

    test "shows sent orders", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      insert_order(%{customer_name: "Carlos", status: "sent"})
      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "Carlos"
    end

    test "shows ready orders", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      insert_order(%{customer_name: "María", status: "ready"})
      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "María"
    end

    test "does not show closed orders", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      insert_order(%{customer_name: "Cerrado", status: "closed"})
      {:ok, _lv, html} = live(conn, "/mesa")
      refute html =~ "Cerrado"
    end

    test "shows correct status badge for sent order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      insert_order(%{customer_name: "Pedro", status: "sent"})
      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "En cocina"
    end

    test "shows correct status badge for ready order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      insert_order(%{customer_name: "Ana", status: "ready"})
      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "Lista"
    end
  end

  # ---------------------------------------------------------------------------
  # Table selection → creates a dine-in order for a physical table
  # ---------------------------------------------------------------------------

  describe "table selection" do
    test "selecting a free table opens the confirmation modal", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      table = insert_table()
      {:ok, lv, _html} = live(conn, "/mesa")

      html = render_click(lv, "select_table", %{"id" => to_string(table.id)})
      # Modal shows the table number and "Abrir mesa" button
      assert html =~ to_string(table.number)
      assert html =~ "Abrir mesa"
    end

    test "closing the modal hides it", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      table = insert_table()
      {:ok, lv, _html} = live(conn, "/mesa")

      render_click(lv, "select_table", %{"id" => to_string(table.id)})
      html = render_click(lv, "close_modal")
      refute html =~ "Abrir mesa"
    end

    test "confirming opens an order and redirects to order page", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      table = insert_table()
      {:ok, lv, _html} = live(conn, "/mesa")

      render_click(lv, "select_table", %{"id" => to_string(table.id)})

      assert {:error, {:live_redirect, %{to: path}}} =
               render_click(lv, "create_order_for_table")

      assert path =~ "/mesa/"
    end

    test "selecting an occupied table redirects directly to the order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      table = insert_table()
      {:ok, order} = Orders.create_order(%{customer_name: "Mesa Ocupada", table_id: table.id})
      {:ok, lv, _html} = live(conn, "/mesa")

      assert {:error, {:live_redirect, %{to: path}}} =
               render_click(lv, "select_table", %{"id" => to_string(table.id)})

      assert path == "/mesa/#{order.id}"
    end
  end

  # ---------------------------------------------------------------------------
  # Grupo modal
  # ---------------------------------------------------------------------------

  describe "grupo modal" do
    test "open_group_modal shows the group creation form", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _html} = live(conn, "/mesa")

      html = render_click(lv, "open_group_modal")
      assert html =~ "Nuevo grupo"
      assert html =~ "Nombre del grupo"
    end

    test "close_modal hides the group modal", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _html} = live(conn, "/mesa")

      render_click(lv, "open_group_modal")
      html = render_click(lv, "close_modal")
      refute html =~ "Nombre del grupo"
    end

    test "create_group redirects to new order page", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _html} = live(conn, "/mesa")

      render_click(lv, "open_group_modal")

      assert {:error, {:live_redirect, %{to: path}}} = render_click(lv, "create_group")
      assert path =~ "/mesa/"
    end

    test "create_group with name and count builds correct customer name", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _html} = live(conn, "/mesa")

      render_click(lv, "open_group_modal")
      render_keyup(lv, "update_name_input", %{"value" => "Cumpleaños"})
      render_keyup(lv, "update_person_count_input", %{"value" => "8"})

      assert {:error, {:live_redirect, %{to: path}}} = render_click(lv, "create_group")

      order_id = path |> String.replace_leading("/mesa/", "") |> String.to_integer()
      order = Orders.get_order!(order_id)
      assert order.customer_name == "Cumpleaños · 8 personas"
      assert order.is_group == true
    end
  end

  # ---------------------------------------------------------------------------
  # Takeout modal
  # ---------------------------------------------------------------------------

  describe "takeout modal" do
    test "open_takeout_modal shows the takeout creation form", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _html} = live(conn, "/mesa")

      html = render_click(lv, "open_takeout_modal")
      assert html =~ "Para llevar"
      assert html =~ "Nombre del cliente"
    end

    test "close_modal hides the takeout modal", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _html} = live(conn, "/mesa")

      render_click(lv, "open_takeout_modal")
      html = render_click(lv, "close_modal")
      refute html =~ "Nueva orden de takeout"
    end

    test "create_takeout with empty name shows error", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _html} = live(conn, "/mesa")

      render_click(lv, "open_takeout_modal")
      # name_input is empty by default
      html = render_click(lv, "create_takeout")
      assert html =~ "Ingresa el nombre del cliente"
    end

    test "create_takeout with name redirects to order page", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _html} = live(conn, "/mesa")

      render_click(lv, "open_takeout_modal")
      render_keyup(lv, "update_name_input", %{"value" => "Cliente Takeout"})

      assert {:error, {:live_redirect, %{to: path}}} = render_click(lv, "create_takeout")
      assert path =~ "/mesa/"

      order_id = path |> String.replace_leading("/mesa/", "") |> String.to_integer()
      order = Orders.get_order!(order_id)
      assert order.customer_name == "Cliente Takeout"
      assert order.order_type == "takeout"
    end
  end

  # ---------------------------------------------------------------------------
  # update_name_input event
  # ---------------------------------------------------------------------------

  describe "update_name_input event" do
    test "tracks the input value in the group modal", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/mesa")

      render_click(lv, "open_group_modal")
      render_keyup(lv, "update_name_input", %{"value" => "Reserva Flores"})
      assert render(lv) =~ "Reserva Flores"
    end

    test "tracks the input value in the takeout modal", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/mesa")

      render_click(lv, "open_takeout_modal")
      render_keyup(lv, "update_name_input", %{"value" => "Ana García"})
      assert render(lv) =~ "Ana García"
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub updates
  # ---------------------------------------------------------------------------

  describe "PubSub" do
    test "refreshes list when order_updated is broadcast", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _html} = live(conn, "/mesa")

      order = insert_order(%{customer_name: "PubSub Test"})
      Phoenix.PubSub.broadcast(CRC.PubSub, "orders", {:order_updated, order.id})

      html = render(lv)
      assert html =~ "PubSub Test"
    end

    test "refreshes tables when tables_changed is broadcast", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, html_before} = live(conn, "/mesa")
      refute html_before =~ "99"  # table number not yet present

      table = insert_table(%{number: 99})
      Phoenix.PubSub.broadcast(CRC.PubSub, "restaurant_tables", :tables_changed)

      assert render(lv) =~ to_string(table.number)
    end
  end

  describe "nav events" do
    test "toggle_nav opens and closes nav", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/mesa")

      render_click(lv, "toggle_nav", %{})
      render_click(lv, "toggle_nav", %{})
      assert render(lv) =~ "Comandas"
    end

    test "close_nav closes nav", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/mesa")

      render_click(lv, "toggle_nav", %{})
      render_click(lv, "close_nav", %{})
      assert render(lv) =~ "Comandas"
    end
  end

  # ---------------------------------------------------------------------------
  # Visual indicators: overdue
  # ---------------------------------------------------------------------------

  describe "overdue indicator" do
    test "shows +15 min badge when sent item has sent_at > 15 min ago", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      alias CRC.Catalog

      {:ok, cat} = Catalog.create_category(%{name: "Cat Overdue #{System.unique_integer()}"})

      {:ok, mi} =
        Catalog.create_menu_item(%{name: "Platillo Lento", price: "80.00", category_id: cat.id})

      order = insert_order(%{customer_name: "Overdue Test", status: "sent"})

      old_sent_at =
        DateTime.utc_now() |> DateTime.add(-20 * 60, :second) |> DateTime.truncate(:second)

      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id,
        menu_item_id: mi.id,
        quantity: 1,
        status: "sent",
        sent_at: old_sent_at,
        inserted_at: old_sent_at,
        updated_at: old_sent_at
      })

      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "+15 min"
    end

    test "does not show +15 min badge for recently sent items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      alias CRC.Catalog

      {:ok, cat} = Catalog.create_category(%{name: "Cat Fresh #{System.unique_integer()}"})

      {:ok, mi} =
        Catalog.create_menu_item(%{name: "Platillo Rapido", price: "80.00", category_id: cat.id})

      order = insert_order(%{customer_name: "Fresh Test", status: "sent"})

      recent_sent_at =
        DateTime.utc_now() |> DateTime.add(-5 * 60, :second) |> DateTime.truncate(:second)

      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id,
        menu_item_id: mi.id,
        quantity: 1,
        status: "sent",
        sent_at: recent_sent_at,
        inserted_at: recent_sent_at,
        updated_at: recent_sent_at
      })

      {:ok, _lv, html} = live(conn, "/mesa")
      refute html =~ "+15 min"
    end
  end

  # ---------------------------------------------------------------------------
  # All items ready indicator (list view)
  # ---------------------------------------------------------------------------

  describe "all items ready indicator (list view)" do
    test "shows 'Lista para servir' in list view when all items are ready", %{conn: conn} do
      {conn, _user} = auth_conn(conn)
      alias CRC.Catalog

      table = insert_table()
      {:ok, cat} = Catalog.create_category(%{name: "Cat #{System.unique_integer()}"})

      {:ok, mi} =
        Catalog.create_menu_item(%{name: "Platillo Listo", price: "60.00", category_id: cat.id})

      order = insert_order(%{customer_name: "Lista Test", status: "sent", table_id: table.id})
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id,
        menu_item_id: mi.id,
        quantity: 1,
        status: "ready",
        sent_at: now,
        ready_at: now,
        inserted_at: now,
        updated_at: now
      })

      {:ok, lv, _html} = live(conn, "/mesa")
      render_click(lv, "set_view", %{"mode" => "list"})
      assert render(lv) =~ "Lista para servir"
    end
  end

  # ---------------------------------------------------------------------------
  # Order item count on cards
  # ---------------------------------------------------------------------------

  describe "order item count on cards" do
    test "shows 0 artículos when order has no items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      insert_order(%{customer_name: "Sin Items"})
      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "0 artículos"
    end

    test "shows singular artículo when order has exactly 1 item", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      alias CRC.Catalog

      {:ok, cat} = Catalog.create_category(%{name: "Cat #{System.unique_integer()}"})

      {:ok, mi} =
        Catalog.create_menu_item(%{name: "Solo Uno", price: "45.00", category_id: cat.id})

      order = insert_order(%{customer_name: "Un Item"})
      Orders.add_item(%{order_id: order.id, menu_item_id: mi.id, quantity: 1})

      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "1 artículo"
    end

    test "shows plural artículos when order has 2+ items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      alias CRC.Catalog

      {:ok, cat} = Catalog.create_category(%{name: "Cat #{System.unique_integer()}"})

      {:ok, mi1} =
        Catalog.create_menu_item(%{name: "Bebida A", price: "30.00", category_id: cat.id})

      {:ok, mi2} =
        Catalog.create_menu_item(%{name: "Bebida B", price: "35.00", category_id: cat.id})

      order = insert_order(%{customer_name: "Dos Items"})
      Orders.add_item(%{order_id: order.id, menu_item_id: mi1.id, quantity: 1})
      Orders.add_item(%{order_id: order.id, menu_item_id: mi2.id, quantity: 1})

      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "2 artículos"
    end
  end
end
