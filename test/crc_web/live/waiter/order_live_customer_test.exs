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
end
