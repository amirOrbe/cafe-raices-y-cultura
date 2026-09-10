defmodule CRCWeb.Waiter.OrderLiveCustomerTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CRC.E2EFixtures

  alias CRC.CRM
  alias CRC.Orders

  defp waiter_conn(conn) do
    user = create_waiter()
    {init_test_session(conn, %{"user_id" => user.id}), user}
  end

  describe "associate customer" do
    setup %{conn: conn} do
      {conn, user} = waiter_conn(conn)
      order = create_order(%{customer_name: "Mesa 3", user_id: user.id})
      %{conn: conn, order: order, user: user}
    end

    test "search and pick a customer associates it to the order", %{conn: conn, order: order} do
      customer = create_customer(%{name: "Ana López", phone: "5511112222"})

      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      lv |> element("button", "Asociar cliente de lealtad") |> render_click()

      lv
      |> element("#customer-search input[type='text']")
      |> render_keyup(%{"value" => "Ana"})

      lv |> element("#customer-search button", "Ana López") |> render_click()

      assert render(lv) =~ "Cliente asociado: Ana López"
      assert Orders.get_order!(order.id).customer_id == customer.id
    end

    test "register a new customer inline and associate it", %{conn: conn, order: order} do
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      lv |> element("button", "Asociar cliente de lealtad") |> render_click()
      lv |> element("#customer-search button", "Registrar cliente nuevo") |> render_click()

      lv
      |> form("#customer-search form", customer: %{name: "nuevo cliente", phone: "5599990000"})
      |> render_submit()

      assert render(lv) =~ "Cliente asociado: Nuevo Cliente"
      assert [%{name: "Nuevo Cliente"}] = CRM.list_customers()
    end

    test "shows the loyalty banner with visits and pending reward", %{
      conn: conn,
      order: order,
      user: user
    } do
      customer = create_customer(%{name: "Frecuente"})
      create_reward_tier(%{visits_required: 1, benefit: "Café gratis"})

      # one prior closed visit → reward earned
      prev = create_order(%{customer_name: "x", user_id: user.id}) |> associate_customer(customer)
      close_order_for(prev, user)

      {:ok, _} = Orders.update_order(order, %{customer_id: customer.id})

      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")

      assert html =~ "Frecuente"
      assert html =~ "1 visita"
      assert html =~ "Café gratis"
    end

    test "remove customer clears the association", %{conn: conn, order: order} do
      customer = create_customer()
      {:ok, _} = Orders.update_order(order, %{customer_id: customer.id})

      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")
      html = lv |> element("button", "Quitar") |> render_click()

      assert html =~ "Cliente quitado"
      assert Orders.get_order!(order.id).customer_id == nil
    end
  end

  describe "redeem reward at checkout" do
    setup %{conn: conn} do
      {conn, user} = waiter_conn(conn)
      dish = create_food_item(create_category().id, "Café de olla")
      customer = create_customer(%{name: "Leal"})
      create_reward_tier(%{visits_required: 1, benefit: "Café gratis", benefit_menu_item_id: dish.id})

      # earn a reward from a prior closed visit
      prev = create_order(%{customer_name: "x", user_id: user.id}) |> associate_customer(customer)
      close_order_for(prev, user)

      order = create_order(%{customer_name: "Mesa 5", user_id: user.id}) |> associate_customer(customer)
      %{conn: conn, order: order, customer: customer, dish: dish, user: user}
    end

    test "apply reward adds a $0 comp line without changing the total", %{
      conn: conn,
      order: order,
      dish: dish,
      user: user
    } do
      # a paid item so the order has a real total
      add_item(order.id, dish.id, 1)
      subtotal_before = Orders.calculate_order_total(Orders.get_order!(order.id))

      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")
      html = lv |> element("button", "Aplicar: Café gratis") |> render_click()

      assert html =~ "Recompensa aplicada"
      assert html =~ "Recompensa"

      reloaded = Orders.get_order!(order.id)
      comp = Enum.find(reloaded.order_items, &(not is_nil(&1.loyalty_redemption_id)))
      assert comp && Decimal.equal?(comp.unit_price, Decimal.new(0))
      assert Decimal.equal?(Orders.calculate_order_total(reloaded), subtotal_before)

      _ = user
    end

    test "remove reward deletes the comp line", %{conn: conn, order: order} do
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")
      lv |> element("button", "Aplicar: Café gratis") |> render_click()

      html = lv |> element("button[phx-click='remove_reward']") |> render_click()
      assert html =~ "Recompensa quitada"

      reloaded = Orders.get_order!(order.id)
      refute Enum.any?(reloaded.order_items, &(not is_nil(&1.loyalty_redemption_id)))
    end
  end
end
