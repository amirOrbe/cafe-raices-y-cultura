defmodule CRCWeb.Admin.ClientesLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CRC.E2EFixtures

  alias CRC.CRM

  defp admin_conn(conn) do
    admin = create_admin()
    {init_test_session(conn, %{"user_id" => admin.id}), admin}
  end

  describe "access" do
    test "redirects a non-admin", %{conn: conn} do
      empleado = create_waiter()
      conn = init_test_session(conn, %{"user_id" => empleado.id})
      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/clientes")
    end
  end

  describe "list" do
    setup %{conn: conn} do
      {conn, admin} = admin_conn(conn)
      %{conn: conn, admin: admin}
    end

    test "shows active customers and filters by search", %{conn: conn} do
      create_customer(%{name: "Ana López", phone: "5511112222"})
      create_customer(%{name: "Pedro Ramírez", phone: "5533334444"})

      {:ok, lv, html} = live(conn, ~p"/admin/clientes")
      assert html =~ "Ana López"
      assert html =~ "Pedro Ramírez"

      html = render_change(element(lv, "form[phx-change=search]"), %{"query" => "ana"})
      assert html =~ "Ana López"
      refute html =~ "Pedro Ramírez"
    end

    test "hides inactive customers until the filter is switched", %{conn: conn} do
      inactive = create_customer(%{name: "Cliente Viejo"})
      CRM.deactivate_customer(inactive)

      {:ok, lv, html} = live(conn, ~p"/admin/clientes")
      refute html =~ "Cliente Viejo"

      html = render_click(element(lv, "button", "Inactivos"))
      assert html =~ "Cliente Viejo"
    end
  end

  describe "create / edit / deactivate" do
    setup %{conn: conn} do
      {conn, admin} = admin_conn(conn)
      %{conn: conn, admin: admin}
    end

    test "registers a new customer", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/admin/clientes")

      lv |> element("#btn-new-customer") |> render_click()

      html =
        lv
        |> form("#customer-form", customer: %{name: "nueva clienta", phone: "5599998888"})
        |> render_submit()

      assert html =~ "registrado correctamente"
      assert html =~ "Nueva Clienta"
      assert [%{name: "Nueva Clienta"}] = CRM.list_customers()
    end

    test "shows validation errors", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/admin/clientes")
      lv |> element("#btn-new-customer") |> render_click()

      html =
        lv
        |> form("#customer-form", customer: %{name: "", phone: ""})
        |> render_submit()

      assert html =~ "no puede estar en blanco"
    end

    test "edits an existing customer", %{conn: conn} do
      customer = create_customer(%{name: "Ana", phone: "5500000000"})
      {:ok, lv, _} = live(conn, ~p"/admin/clientes")

      lv |> element("#btn-edit-#{customer.id}") |> render_click()

      html =
        lv
        |> form("#customer-form", customer: %{name: "Ana", phone: "5512121212"})
        |> render_submit()

      assert html =~ "actualizado correctamente"
      assert CRM.get_customer!(customer.id).phone == "5512121212"
    end

    test "deactivating from the row toggle", %{conn: conn} do
      customer = create_customer(%{name: "Ana"})
      {:ok, lv, _} = live(conn, ~p"/admin/clientes")

      lv
      |> element("#btn-toggle-#{customer.id}")
      |> render_click()

      refute CRM.get_customer!(customer.id).active
    end

    test "blocks deleting a customer with orders", %{conn: conn} do
      customer = create_customer(%{name: "Con Comandas"})
      order = create_order()
      associate_customer(order, customer)

      {:ok, lv, _} = live(conn, ~p"/admin/clientes")
      lv |> element("#btn-edit-#{customer.id}") |> render_click()
      lv |> element("button", "Eliminar cliente") |> render_click()
      html = lv |> element("button", "Sí, eliminar") |> render_click()

      assert html =~ "tiene comandas o visitas asociadas"
      assert CRM.get_customer(customer.id)
    end
  end

  describe "detail page" do
    setup %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      %{conn: conn}
    end

    test "renders customer data and allows editing", %{conn: conn} do
      customer = create_customer(%{name: "Ana López", phone: "5511112222", email: "ana@x.com"})

      {:ok, lv, html} = live(conn, ~p"/admin/clientes/#{customer.id}")
      assert html =~ "Ana López"
      assert html =~ "5511112222"
      assert html =~ "ana@x.com"

      lv |> element("button", "Editar") |> render_click()

      html =
        lv
        |> form("#customer-edit-form", customer: %{name: "Ana López", phone: "5500000001"})
        |> render_submit()

      assert html =~ "actualizado correctamente"
      assert CRM.get_customer!(customer.id).phone == "5500000001"
    end

    test "redirects when the customer does not exist", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/clientes"}}} =
               live(conn, ~p"/admin/clientes/999999")
    end

    test "shows visits, spend and a pending reward that can be delivered", %{conn: conn} do
      staff = create_waiter()
      customer = create_customer(%{name: "Frecuente"})
      create_reward_tier(%{visits_required: 1, benefit: "Café gratis"})

      order =
        create_order(%{customer_name: "c", user_id: staff.id}) |> associate_customer(customer)

      close_order_for(order, staff)

      {:ok, lv, html} = live(conn, ~p"/admin/clientes/#{customer.id}")
      assert html =~ "Visitas"
      assert html =~ "Gasto total"
      assert html =~ "Café gratis"

      html = lv |> element("button", "Marcar entregada") |> render_click()
      assert html =~ "marcada como entregada"
      assert [%{status: "redeemed"}] = CRC.CRM.list_redemptions_for_customer(customer.id)
    end

    test "creates a personal package for the customer", %{conn: conn} do
      customer = create_customer(%{name: "VIP Cliente"})
      dish = create_food_item(create_category().id, "Latte")

      {:ok, lv, _} = live(conn, ~p"/admin/clientes/#{customer.id}")
      lv |> element("button", "Crear paquete") |> render_click()

      html =
        lv
        |> form("#package-modal form",
          package: %{name: "El combo VIP", price: "120"},
          items: %{"0" => %{menu_item_id: to_string(dish.id), quantity: "2"}}
        )
        |> render_submit()

      assert html =~ "Paquete personal creado"

      assert [%{name: "El Combo Vip", customer_id: cid}] =
               CRC.CRM.list_personal_packages(customer.id)

      assert cid == customer.id
    end
  end
end
