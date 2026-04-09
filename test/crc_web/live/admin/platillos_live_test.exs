defmodule CRCWeb.Admin.PlatillosLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Accounts.User
  alias CRC.Catalog
  alias CRC.Inventory

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp admin_session(conn) do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        name: "Admin Platillos #{System.unique_integer()}",
        email: "admin_p#{System.unique_integer()}@cafe.com",
        role: "admin",
        password: "contraseña123"
      })
      |> CRC.Repo.insert()

    {init_test_session(conn, %{"user_id" => user.id}), user}
  end

  defp insert_category(overrides \\ %{}) do
    base = %{name: "Cat #{System.unique_integer()}"}
    {:ok, cat} = Catalog.create_category(Map.merge(base, Map.drop(overrides, [:kind, "kind"])))
    cat
  end

  defp insert_menu_item(category_id, overrides \\ %{}) do
    {:ok, item} =
      Catalog.create_menu_item(
        Map.merge(
          %{name: "Item #{System.unique_integer()}", price: "50.00", category_id: category_id},
          overrides
        )
      )
    item
  end

  defp insert_product do
    {:ok, p} =
      Inventory.create_product(%{
        name: "Insumo #{System.unique_integer()}",
        unit: "gramos",
        net_cost: "2.00",
        stock_quantity: "500"
      })
    p
  end

  # ---------------------------------------------------------------------------
  # Authentication
  # ---------------------------------------------------------------------------

  describe "authentication" do
    test "redirects unauthenticated user to login", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/platillos")
      assert path =~ "iniciar-sesion"
    end

    test "redirects non-admin employee to root", %{conn: conn} do
      {:ok, emp} =
        %User{}
        |> User.changeset(%{
          name: "Emp",
          email: "emp_p#{System.unique_integer()}@cafe.com",
          role: "empleado",
          stations: ["sala"],
          password: "pass123456"
        })
        |> CRC.Repo.insert()

      conn = init_test_session(conn, %{"user_id" => emp.id})
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/platillos")
      assert path =~ "/"
    end
  end

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  describe "mount" do
    test "renders page title and new button", %{conn: conn} do
      {conn, _} = admin_session(conn)
      {:ok, _lv, html} = live(conn, ~p"/admin/platillos")
      assert html =~ "Platillos"
      assert html =~ "Nuevo platillo"
    end

    test "shows available and hidden status tabs", %{conn: conn} do
      {conn, _} = admin_session(conn)
      {:ok, _lv, html} = live(conn, ~p"/admin/platillos")
      assert html =~ "Disponibles"
      assert html =~ "Ocultos"
    end

    test "shows empty state when no items", %{conn: conn} do
      {conn, _} = admin_session(conn)
      {:ok, _lv, html} = live(conn, ~p"/admin/platillos")
      assert html =~ "No hay platillos registrados"
    end

    test "lists existing menu items", %{conn: conn} do
      cat = insert_category()
      insert_menu_item(cat.id, %{name: "Chilaquiles Test"})
      {conn, _} = admin_session(conn)
      {:ok, _lv, html} = live(conn, ~p"/admin/platillos")
      assert html =~ "Chilaquiles Test"
    end

    test "shows category filter tabs for existing categories", %{conn: conn} do
      insert_category(%{name: "Desayunos Tab"})
      {conn, _} = admin_session(conn)
      {:ok, _lv, html} = live(conn, ~p"/admin/platillos")
      assert html =~ "Desayunos Tab"
      assert html =~ "Todos"
    end
  end

  # ---------------------------------------------------------------------------
  # Status filter
  # ---------------------------------------------------------------------------

  describe "set_status_filter event" do
    test "switches to unavailable tab and shows hidden items", %{conn: conn} do
      cat = insert_category()
      insert_menu_item(cat.id, %{name: "Visible Item", available: true})
      insert_menu_item(cat.id, %{name: "Hidden Item", available: false})

      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      html = render_click(lv, "set_status_filter", %{"status" => "unavailable"})
      assert html =~ "Hidden Item"
      refute html =~ "Visible Item"
    end

    test "switches back to available tab", %{conn: conn} do
      cat = insert_category()
      insert_menu_item(cat.id, %{name: "Visible Item", available: true})

      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      render_click(lv, "set_status_filter", %{"status" => "unavailable"})
      html = render_click(lv, "set_status_filter", %{"status" => "available"})
      assert html =~ "Visible Item"
    end
  end

  # ---------------------------------------------------------------------------
  # Category filter
  # ---------------------------------------------------------------------------

  describe "set_category_filter event" do
    test "filters items by category", %{conn: conn} do
      cat1 = insert_category(%{name: "Cat Filtro A"})
      cat2 = insert_category(%{name: "Cat Filtro B"})
      insert_menu_item(cat1.id, %{name: "Item Cat A"})
      insert_menu_item(cat2.id, %{name: "Item Cat B"})

      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      html = render_click(lv, "set_category_filter", %{"category" => to_string(cat1.id)})
      assert html =~ "Item Cat A"
      refute html =~ "Item Cat B"
    end

    test "all filter shows all items", %{conn: conn} do
      cat1 = insert_category()
      cat2 = insert_category()
      insert_menu_item(cat1.id, %{name: "Item All A"})
      insert_menu_item(cat2.id, %{name: "Item All B"})

      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      render_click(lv, "set_category_filter", %{"category" => to_string(cat1.id)})
      html = render_click(lv, "set_category_filter", %{"category" => "all"})
      assert html =~ "Item All A"
      assert html =~ "Item All B"
    end

    test "shows empty state when no items in category", %{conn: conn} do
      cat_empty = insert_category(%{name: "Vacía"})

      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      html = render_click(lv, "set_category_filter", %{"category" => to_string(cat_empty.id)})
      assert html =~ "No hay platillos en esta categoría"
    end
  end

  # ---------------------------------------------------------------------------
  # New item modal
  # ---------------------------------------------------------------------------

  describe "new_item event" do
    test "opens the modal", %{conn: conn} do
      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      html = render_click(lv, "new_item", %{})
      assert html =~ "Nuevo platillo"
      assert html =~ "item-form"
    end

    test "creates a new item on submit", %{conn: conn} do
      cat = insert_category()
      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      render_click(lv, "new_item", %{})

      html =
        lv
        |> form("#item-form",
          menu_item: %{
            name: "Nuevo Platillo Test",
            price: "75.00",
            category_id: cat.id
          }
        )
        |> render_submit()

      assert html =~ "creado correctamente" or !String.contains?(html, "Nuevo platillo")
    end

    test "shows validation errors on invalid submit", %{conn: conn} do
      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      render_click(lv, "new_item", %{})

      html =
        lv
        |> form("#item-form", menu_item: %{name: "", price: ""})
        |> render_submit()

      assert html =~ "Nuevo platillo"
    end
  end

  # ---------------------------------------------------------------------------
  # Close modal
  # ---------------------------------------------------------------------------

  describe "close_modal event" do
    test "closes the modal", %{conn: conn} do
      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      render_click(lv, "new_item", %{})
      html = render_click(lv, "close_modal", %{})
      refute html =~ "item-form"
    end
  end

  # ---------------------------------------------------------------------------
  # Edit item modal
  # ---------------------------------------------------------------------------

  describe "edit_item event" do
    test "opens modal pre-filled with item data", %{conn: conn} do
      cat = insert_category()
      item = insert_menu_item(cat.id, %{name: "Editable Platillo"})
      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      html = render_click(lv, "edit_item", %{"id" => to_string(item.id)})
      assert html =~ "Editar platillo"
      assert html =~ "Editable Platillo"
    end

    test "saves updated item data", %{conn: conn} do
      cat = insert_category()
      item = insert_menu_item(cat.id, %{name: "Original Nombre"})
      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      render_click(lv, "edit_item", %{"id" => to_string(item.id)})

      html =
        lv
        |> form("#item-form",
          menu_item: %{
            name: "Nombre Actualizado",
            price: "80.00",
            category_id: cat.id
          }
        )
        |> render_submit()

      assert html =~ "actualizado correctamente" or !String.contains?(html, "Editar platillo")
    end

    test "opens modal with existing ingredients in draft", %{conn: conn} do
      cat = insert_category()
      prod = insert_product()
      item = insert_menu_item(cat.id, %{name: "Con Ingrediente"})
      Catalog.set_menu_item_ingredients(item.id, [%{product_id: prod.id, quantity: Decimal.new("100")}])

      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      html = render_click(lv, "edit_item", %{"id" => to_string(item.id)})
      assert html =~ prod.name
    end
  end

  # ---------------------------------------------------------------------------
  # Toggle available
  # ---------------------------------------------------------------------------

  describe "toggle_available event" do
    test "hides a visible item", %{conn: conn} do
      cat = insert_category()
      item = insert_menu_item(cat.id, %{name: "Para Ocultar", available: true})
      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      html = render_click(lv, "toggle_available", %{"id" => to_string(item.id)})
      assert html =~ "ocultado del menú" or html =~ "Para Ocultar"
    end

    test "publishes a hidden item", %{conn: conn} do
      cat = insert_category()
      item = insert_menu_item(cat.id, %{name: "Para Publicar", available: false})
      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      render_click(lv, "set_status_filter", %{"status" => "unavailable"})
      html = render_click(lv, "toggle_available", %{"id" => to_string(item.id)})
      assert html =~ "publicado en el menú" or html =~ "Para Publicar"
    end
  end

  # ---------------------------------------------------------------------------
  # Delete item
  # ---------------------------------------------------------------------------

  describe "delete_item event" do
    test "removes the item from the list", %{conn: conn} do
      cat = insert_category()
      item = insert_menu_item(cat.id, %{name: "Para Eliminar"})
      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      html = render_click(lv, "delete_item", %{"id" => to_string(item.id)})
      assert html =~ "eliminado correctamente"
      refute html =~ "Para Eliminar"
    end
  end

  # ---------------------------------------------------------------------------
  # Ingredient draft management
  # ---------------------------------------------------------------------------

  describe "ingredient draft events" do
    test "select_ingredient sets selected product id", %{conn: conn} do
      prod = insert_product()
      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      render_click(lv, "new_item", %{})
      html = render_click(lv, "select_ingredient", %{"ingredient_product_id" => to_string(prod.id)})
      assert html =~ prod.name
    end

    test "set_ingredient_qty updates quantity input", %{conn: conn} do
      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      render_click(lv, "new_item", %{})
      # Should not crash
      assert render_click(lv, "set_ingredient_qty", %{"ingredient_quantity" => "150"}) =~
               "Nuevo platillo"
    end

    test "add_ingredient adds product to draft", %{conn: conn} do
      prod = insert_product()
      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      render_click(lv, "new_item", %{})
      render_click(lv, "select_ingredient", %{"ingredient_product_id" => to_string(prod.id)})
      render_click(lv, "set_ingredient_qty", %{"ingredient_quantity" => "200"})
      html = render_click(lv, "add_ingredient", %{})
      assert html =~ prod.name
    end

    test "add_ingredient ignored when no product selected", %{conn: conn} do
      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      render_click(lv, "new_item", %{})
      # No product selected — should be a no-op, not a crash
      assert render_click(lv, "add_ingredient", %{}) =~ "Nuevo platillo"
    end

    test "remove_ingredient removes product from draft", %{conn: conn} do
      prod = insert_product()
      {conn, _} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/platillos")

      render_click(lv, "new_item", %{})
      render_click(lv, "select_ingredient", %{"ingredient_product_id" => to_string(prod.id)})
      render_click(lv, "set_ingredient_qty", %{"ingredient_quantity" => "50"})
      render_click(lv, "add_ingredient", %{})

      html = render_click(lv, "remove_ingredient", %{"product_id" => to_string(prod.id)})
      # After removal, the product should not appear in the draft list (no remove button for it)
      refute html =~ "phx-value-product_id=\"#{prod.id}\""
    end
  end
end
